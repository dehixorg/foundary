// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract StakingRewards is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STATE VARIABLES ---
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;
    address public immutable owner;

    uint256 public duration;
    uint256 public finishAt;
    uint256 public updatedAt;
    uint256 public rewardRate;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    // --- EVENTS ---
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationSet(uint256 newDuration);
    event RewardNotified(uint256 newRate);

    constructor(address _stakingToken, address _rewardToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(finishAt, block.timestamp);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) /
            totalSupply;
    }

    function earned(address _account) public view returns (uint256) {
        return
            ((balanceOf[_account] *
                (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) +
            rewards[_account];
    }

    // FIX [L-01]: Use balance delta tracking to compute the actual number of
    // tokens received after the transfer. If the staking token charges a
    // transfer fee, the contract previously credited _amount to the user but
    // only held (amount - fee) tokens — creating an accounting mismatch that
    // would eventually cause withdrawals to fail with insufficient balance.
    //
    // Pattern:
    //   1. Snapshot the contract's token balance before the transfer.
    //   2. Execute the transfer.
    //   3. Derive actualReceived = balanceAfter - balanceBefore.
    //   4. Credit only actualReceived to the user and totalSupply.
    //
    // For standard ERC20 tokens with no fee, actualReceived == _amount so
    // behaviour is identical to before. For fee-on-transfer tokens the
    // accounting is now correct.
    function stake(
        uint256 _amount
    ) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");

        // FIX [L-01]: Record balance before transfer.
        uint256 balanceBefore = stakingToken.balanceOf(address(this));

        // Interaction — perform the transfer.
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);

        // FIX [L-01]: Compute how many tokens were actually received.
        uint256 actualReceived = stakingToken.balanceOf(address(this)) - balanceBefore;

        // Effects — credit only the tokens that arrived, not the requested _amount.
        balanceOf[msg.sender] += actualReceived;
        totalSupply += actualReceived;

        emit Staked(msg.sender, actualReceived);
    }

    function withdraw(
        uint256 _amount
    ) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "amount = 0");
        require(balanceOf[msg.sender] >= _amount, "insufficient balance");
        // Effects
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        // Interaction
        stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function getReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // FIX [M-01]: Already present — zero duration guard prevents the
    // division-by-zero DoS in notifyRewardAmount().
    function setRewardsDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "duration = 0");
        require(finishAt < block.timestamp, "reward duration not finished");
        duration = _duration;
        emit RewardsDurationSet(_duration);
    }

    function notifyRewardAmount(
        uint256 _amount
    ) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= finishAt) {
            rewardRate = _amount / duration;
        } else {
            uint256 remainingRewards = (finishAt - block.timestamp) *
                rewardRate;
            rewardRate = (_amount + remainingRewards) / duration;
        }
        require(rewardRate > 0, "reward rate = 0");
        uint256 rewardAmount = rewardRate * duration;
        require(
            rewardAmount <= rewardsToken.balanceOf(address(this)),
            "reward amount > balance"
        );
        finishAt = block.timestamp + duration;
        updatedAt = block.timestamp;
        emit RewardNotified(rewardRate);
    }

    function penalize(address _user) external nonReentrant onlyOwner {
        uint256 stakedAmount = balanceOf[_user];
        require(stakedAmount > 0, "user has no staked tokens");
        // Effects
        balanceOf[_user] = 0;
        totalSupply -= stakedAmount;
        rewards[_user] = 0;
        // Interaction
        stakingToken.safeTransfer(owner, stakedAmount);
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }
}
