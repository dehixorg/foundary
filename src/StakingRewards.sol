// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title  StakingRewards
 * @notice Single-sided staking contract: users deposit `stakingToken` and
 *         earn `rewardsToken` emissions over a fixed-length campaign window.
 *
 * Audit fixes applied
 * ───────────────────
 * [M-01] Fee-on-transfer desync (stake)
 *        Previously the contract credited `_amount` to the user before
 *        knowing how many tokens actually arrived. For fee-on-transfer tokens
 *        this inflated `balanceOf` and `totalSupply`, eventually making the
 *        last stakers unable to withdraw. Fixed by measuring the real delta.
 *
 * [M-02] Precision loss in rewardRate (notifyRewardAmount)
 *        Plain integer division `_amount / duration` rounds to zero when the
 *        reward token has few decimals (e.g. USDC = 6 dec) and the campaign
 *        is long. Fixed by storing rates scaled by PRECISION (1e18) and
 *        scaling back only when computing per-user payouts.
 */
contract StakingRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Internal precision multiplier used to avoid truncation in reward
    ///      rate arithmetic. All stored rates are multiplied by this factor;
    ///      the scale is removed only in `earned()` and `rewardPerToken()`.
    uint256 private constant PRECISION = 1e18;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;
    address public immutable owner;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Length of the current (or next) reward campaign in seconds.
    uint256 public duration;

    /// @notice Timestamp at which the current campaign ends.
    uint256 public finishAt;

    /// @notice Timestamp of the last reward-accounting update.
    uint256 public updatedAt;

    /// @notice [M-02 FIX] Reward tokens distributed per second, scaled by
    ///         PRECISION to preserve sub-unit precision for low-decimal tokens.
    ///         E.g. for a 30-day USDC campaign the raw division would round to
    ///         zero; storing `_amount * PRECISION / duration` keeps the
    ///         fractional part alive until payout.
    uint256 public rewardRate;

    /// @notice Accumulated reward-per-staked-token, scaled by PRECISION.
    uint256 public rewardPerTokenStored;

    /// @notice Snapshot of `rewardPerTokenStored` at the last time each user
    ///         touched the contract — used to compute incremental earnings.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Pending reward balance for each user (in raw reward-token units).
    mapping(address => uint256) public rewards;

    /// @notice Total staked tokens held by the contract (real balance).
    uint256 public totalSupply;

    /// @notice Staked balance credited to each user (real balance after fees).
    mapping(address => uint256) public balanceOf;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationSet(uint256 newDuration);
    event RewardNotified(uint256 newRate);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _stakingToken, address _rewardToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardToken);
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    /**
     * @dev Snapshots global reward state and, for real accounts, settles the
     *      caller's pending earnings before any state-mutating function runs.
     *      Passing `address(0)` updates only the global accumulators.
     */
    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    /// @notice Returns the lesser of `finishAt` and the current timestamp,
    ///         capping reward accrual once the campaign ends.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt, block.timestamp);
    }

    /// @notice Cumulative reward tokens earned per staked token since
    ///         deployment, scaled by PRECISION.
    /// @dev    [M-02] Both `rewardRate` and the return value are stored at
    ///         PRECISION scale. The PRECISION factors cancel inside `earned()`
    ///         when we divide by PRECISION once, giving a correct raw payout.
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            // rewardRate is already * PRECISION, so no extra scale needed here.
            (rewardRate * (lastTimeRewardApplicable() - updatedAt)) /
            totalSupply;
    }

    /// @notice Raw reward tokens owed to `_account` (not yet claimed).
    function earned(address _account) public view returns (uint256) {
        return
            ((balanceOf[_account] *
                (rewardPerToken() - userRewardPerTokenPaid[_account])) /
                PRECISION) + rewards[_account];
    }

    // -------------------------------------------------------------------------
    // User-facing functions
    // -------------------------------------------------------------------------

    /**
     * @notice Deposit `_amount` staking tokens.
     *
     * [M-01 FIX] Balance-delta pattern
     * ─────────────────────────────────
     * We snapshot the contract's token balance before the transfer, execute
     * the transfer, then compute `actualReceived = after - before`. Only this
     * delta is credited to the user and `totalSupply`. For standard ERC20s
     * `actualReceived == _amount`; for fee-on-transfer tokens it equals the
     * net amount — preventing the accounting inflation that would lock later
     * stakers' funds.
     */
    function stake(
        uint256 _amount
    ) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");

        // [M-01] Snapshot balance before transfer.
        uint256 balanceBefore = stakingToken.balanceOf(address(this));

        // Interaction — pull tokens from the caller.
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        // [M-01] Derive actual tokens received (handles transfer-fee tokens).
        uint256 actualReceived = stakingToken.balanceOf(address(this)) - balanceBefore;

        // Effects — credit only what arrived.
        balanceOf[msg.sender] += actualReceived;
        totalSupply += actualReceived;

        emit Staked(msg.sender, actualReceived);
    }

    /**
     * @notice Withdraw `_amount` previously staked tokens.
     */
    function withdraw(
        uint256 _amount
    ) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");
        require(balanceOf[msg.sender] >= _amount, "insufficient balance");

        // Effects before interaction (checks-effects-interactions).
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;

        // Interaction — return tokens to the caller.
        stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Claim all pending reward tokens.
     */
    function getReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // -------------------------------------------------------------------------
    // Owner functions
    // -------------------------------------------------------------------------

    /**
     * @notice Set the campaign duration (seconds). Must be called before
     *         `notifyRewardAmount`. Cannot be changed mid-campaign.
     */
    function setRewardsDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "duration = 0");
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
        emit RewardsDurationSet(_duration);
    }

    /**
     * @notice Fund and (re-)start a reward campaign.
     *
     * [M-02 FIX] Precision-preserving rewardRate
     * ────────────────────────────────────────────
     * Previously: `rewardRate = _amount / duration`
     *   → rounds to 0 when `_amount` (e.g. 1 000 USDC = 1_000_000 units) is
     *     smaller than `duration` (e.g. 30 days = 2_592_000 seconds).
     *
     * Now: `rewardRate = _amount * PRECISION / duration`
     *   → stores the rate at 1e18 scale, keeping fractional precision alive.
     *   → `rewardPerToken()` and `earned()` divide by PRECISION at payout,
     *     yielding the correct raw token amount to the user.
     *
     * The solvency check is also updated: `rewardRate * duration / PRECISION`
     * recovers the original token amount for comparison with the vault balance.
     *
     * @param _amount Reward tokens to distribute over the campaign window.
     *                The contract must already hold at least this many tokens.
     */
    function notifyRewardAmount(
        uint256 _amount
    ) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= finishAt) {
            // Fresh campaign — [M-02] scale up by PRECISION before dividing.
            rewardRate = (_amount * PRECISION) / duration;
        } else {
            // Campaign still running — roll over leftover rewards.
            // `rewardRate` is already PRECISION-scaled, so remaining is in
            // raw token units after dividing by PRECISION.
            uint256 remainingRewards = ((finishAt - block.timestamp) * rewardRate) /
                PRECISION;
            rewardRate = ((_amount + remainingRewards) * PRECISION) / duration;
        }

        require(rewardRate > 0, "reward rate = 0");

        // Solvency check — convert scaled rate back to raw token units.
        uint256 rewardAmount = (rewardRate * duration) / PRECISION;
        require(
            rewardAmount <= rewardsToken.balanceOf(address(this)),
            "reward amount > balance"
        );

        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
        emit RewardNotified(rewardRate);
    }

    /**
     * @notice Slash a misbehaving user's entire stake and send it to the owner.
     * @dev    Clears both the staked balance and any pending reward to prevent
     *         the penalised user from claiming earnings after slashing.
     */
    function penalize(address _user) external nonReentrant onlyOwner {
        uint256 stakedAmount = balanceOf[_user];
        require(stakedAmount > 0, "user has no staked tokens");

        // Effects.
        balanceOf[_user] = 0;
        totalSupply -= stakedAmount;
        rewards[_user] = 0;

        // Interaction.
        stakingToken.safeTransfer(owner, stakedAmount);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }
}
