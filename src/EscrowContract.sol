// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract EscrowContract is ReentrancyGuard {

    using SafeERC20 for IERC20;

    address private immutable i_owner;

    /// @notice Maximum unique tokens allowed per escrow.
    /// @dev Prevents DoS caused by unbounded token arrays.
    uint256 private constant MAX_TOKENS_PER_ESCROW = 5;

    constructor() {
        i_owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == i_owner, "OnlyOwner");
        _;
    }

    struct Escrow {
        string escrowId;
        address client;
        address freelancer;
        address[] tokens;
        bool active;
    }

    mapping(string => Escrow) private s_escrows;

    mapping(string => mapping(address => uint256)) private s_tokenBalances;

    event EscrowCreated(
        string indexed escrowId,
        address indexed client,
        address indexed freelancer
    );

    event FundsDeposited(
        string indexed escrowId,
        address token,
        uint256 amount
    );

    event FundsReleased(
        string indexed escrowId
    );

    event FundsRefunded(
        string indexed escrowId
    );

    event DisputeResolved(
        string indexed escrowId,
        bool releasedToFreelancer
    );

    function createEscrow(
        string calldata _escrowId,
        address _freelancer
    ) external {
        require(bytes(_escrowId).length > 0, "EmptyEscrowId");
        require(_freelancer != address(0), "InvalidFreelancer");

        Escrow storage e = s_escrows[_escrowId];

        require(!e.active, "EscrowExists");

        e.escrowId = _escrowId;
        e.client = msg.sender;
        e.freelancer = _freelancer;
        e.active = true;

        emit EscrowCreated(
            _escrowId,
            msg.sender,
            _freelancer
        );
    }

    function depositToken(
        string calldata _escrowId,
        address token,
        uint256 amount
    ) external nonReentrant {
        Escrow storage e = s_escrows[_escrowId];

        require(e.active, "EscrowNotActive");
        require(msg.sender == e.client, "OnlyClient");
        require(token != address(0), "InvalidToken");
        require(amount > 0, "ZeroAmount");

        if (s_tokenBalances[_escrowId][token] == 0) {
            require(
                e.tokens.length < MAX_TOKENS_PER_ESCROW,
                "TooManyTokens"
            );

            e.tokens.push(token);
        }

        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        s_tokenBalances[_escrowId][token] += amount;

        emit FundsDeposited(
            _escrowId,
            token,
            amount
        );
    }

    function releaseFunds(
        string calldata _escrowId
    ) external nonReentrant {
        Escrow storage e = s_escrows[_escrowId];

        require(e.active, "EscrowClosed");
        require(msg.sender == e.client, "OnlyClient");

        _transferTokens(
            _escrowId,
            e.freelancer
        );

        e.active = false;

        emit FundsReleased(_escrowId);
    }

    function refundFunds(
        string calldata _escrowId
    ) external nonReentrant {
        Escrow storage e = s_escrows[_escrowId];

        require(e.active, "EscrowClosed");
        require(msg.sender == e.freelancer, "OnlyFreelancer");

        _transferTokens(
            _escrowId,
            e.client
        );

        e.active = false;

        emit FundsRefunded(_escrowId);
    }

    function resolveDispute(
        string calldata _escrowId,
        bool releaseToFreelancer
    ) external onlyOwner nonReentrant {
        Escrow storage e = s_escrows[_escrowId];

        require(e.active, "EscrowClosed");

        address receiver = releaseToFreelancer
            ? e.freelancer
            : e.client;

        _transferTokens(
            _escrowId,
            receiver
        );

        e.active = false;

        emit DisputeResolved(
            _escrowId,
            releaseToFreelancer
        );
    }

    function _transferTokens(
        string memory _escrowId,
        address receiver
    ) internal {
        Escrow storage e = s_escrows[_escrowId];

        for (uint256 i = 0; i < e.tokens.length; i++) {
            address token = e.tokens[i];

            uint256 amount =
                s_tokenBalances[_escrowId][token];

            if (amount > 0) {
                s_tokenBalances[_escrowId][token] = 0;

                IERC20(token).safeTransfer(
                    receiver,
                    amount
                );
            }
        }
    }

    function getEscrow(
        string calldata _escrowId
    )
        external
        view
        returns (
            address client,
            address freelancer,
            address[] memory tokens,
            bool active
        )
    {
        Escrow storage e = s_escrows[_escrowId];

        return (
            e.client,
            e.freelancer,
            e.tokens,
            e.active
        );
    }

    function getTokenBalance(
        string calldata _escrowId,
        address token
    ) external view returns (uint256) {
        return s_tokenBalances[_escrowId][token];
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }
}