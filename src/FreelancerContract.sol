// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./StakingRewards.sol";

contract FreelancerContract is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STATE VARIABLES ---
    struct Project {
        string projectId;
        bool isActive;
        mapping(address => bool) appliedFreelancers;
    }

    struct Freelancer {
        string freelancerId;
        address freelancerAddress;
    }

    struct Business {
        string businessId;
        address businessAddress;
    }

    struct Escrow {
        string escrowId;
        address[] votingOracles;
        address freelancerAddress;
        address businessAddress;
        uint256 depositedAmount;
        IERC20 tokenAddress;
    }

    address private immutable i_owner;
    StakingRewards public immutable stakingContract; // <-- MADE IMMUTABLE

    mapping(string => Freelancer) public s_freelancers;
    mapping(string => Project) public s_projects;
    mapping(string => Business) public s_businesses;
    mapping(string => Escrow) public s_escrows;
    mapping(address => bool) public s_oracles;
    mapping(string => mapping(address => bool)) private s_hasVoted;
    mapping(string => uint256) private s_releaseVotes;
    mapping(string => uint256) private s_refundVotes;

    // --- EVENTS ---
    event FreelancerAdded(
        string indexed freelancerId,
        address indexed freelancerAddress
    );
    event BusinessAdded(
        string indexed businessId,
        address indexed businessAddress
    );
    event ProjectCreated(string indexed projectId);
    event ProjectDeactivated(string indexed projectId);
    event OracleAdded(address indexed oracleAddress);
    event OracleRemoved(address indexed oracleAddress);
    event EscrowCreated(
        string indexed escrowId,
        address indexed business,
        address indexed freelancer
    );
    event FundsDeposited(string indexed escrowId, uint256 amount);
    event FundsReleased(
        string indexed escrowId,
        address indexed to,
        uint256 amount
    );
    event FundsRefunded(
        string indexed escrowId,
        address indexed to,
        uint256 amount
    );
    event Voted(
        string indexed escrowId,
        address indexed oracle,
        bool voteForRelease
    );

    // --- MODIFIERS ---
    modifier onlyOwner() {
        require(msg.sender == i_owner, "OnlyOwner");
        _;
    }

    modifier onlyOracle() {
        require(s_oracles[msg.sender], "OnlyOracle");
        _;
    }

    // --- FUNCTIONS ---
    constructor(address _stakingContractAddress) {
        i_owner = msg.sender;
        stakingContract = StakingRewards(_stakingContractAddress);
    }

    function addBusiness(
        string calldata _businessId,
        address _businessAddress
    ) external onlyOwner {
        require(bytes(_businessId).length > 0, "EmptyBusinessId");
        require(_businessAddress != address(0), "ZeroAddress");
        require(
            bytes(s_businesses[_businessId].businessId).length == 0,
            "BusinessExists"
        );

        s_businesses[_businessId].businessId = _businessId;
        s_businesses[_businessId].businessAddress = _businessAddress;
        emit BusinessAdded(_businessId, _businessAddress);
    }

    function addFreelancer(
        string calldata _freelancerId,
        address _freelancerAddress
    ) external onlyOwner {
        require(bytes(_freelancerId).length > 0, "EmptyFreelancerId");
        require(_freelancerAddress != address(0), "ZeroAddress");

        s_freelancers[_freelancerId].freelancerId = _freelancerId;
        s_freelancers[_freelancerId].freelancerAddress = _freelancerAddress;
        emit FreelancerAdded(_freelancerId, _freelancerAddress);
    }

    function createProject(string calldata _projectId) external onlyOwner {
        require(bytes(_projectId).length > 0, "EmptyProjectId");
        s_projects[_projectId].isActive = true;
        s_projects[_projectId].projectId = _projectId;
        emit ProjectCreated(_projectId);
    }

    function deactivateProject(string calldata _projectId) external onlyOwner {
        s_projects[_projectId].isActive = false;
        emit ProjectDeactivated(_projectId);
    }

    function addOracle(address _oracleAddress) external onlyOwner {
        require(_oracleAddress != address(0), "ZeroAddress");
        require(
            stakingContract.balanceOf(_oracleAddress) > 0,
            "OracleMustHaveStake"
        );
        s_oracles[_oracleAddress] = true;
        emit OracleAdded(_oracleAddress);
    }

    function removeOracle(address _oracleAddress) external onlyOwner {
        s_oracles[_oracleAddress] = false;
        emit OracleRemoved(_oracleAddress);
    }

    function applyToProject(
        string calldata _projectId,
        address _freelancerAddress
    ) external {
        Project storage project = s_projects[_projectId];
        require(project.isActive, "ProjectNotActive");
        require(
            !project.appliedFreelancers[_freelancerAddress],
            "AlreadyApplied"
        );
        project.appliedFreelancers[_freelancerAddress] = true;
    }

    function createEscrow(
        string calldata _escrowId,
        address[] calldata _votingOracles,
        address _freelancer,
        address _tokenAddress
    ) external {
        require(bytes(_escrowId).length > 0, "EmptyEscrowId");
        require(_votingOracles.length % 2 != 0, "InvalidOracleCount");
        for (uint256 i = 0; i < _votingOracles.length; i++) {
            require(s_oracles[_votingOracles[i]], "NotAValidOracle");
        }
        Escrow storage newEscrow = s_escrows[_escrowId];
        newEscrow.escrowId = _escrowId;
        newEscrow.votingOracles = _votingOracles;
        newEscrow.freelancerAddress = _freelancer;
        newEscrow.businessAddress = msg.sender;
        newEscrow.depositedAmount = 0;
        newEscrow.tokenAddress = IERC20(_tokenAddress);
        emit EscrowCreated(_escrowId, msg.sender, _freelancer);
    }

    function depositFunds(uint256 _amount, string calldata _escrowId) external {
        Escrow storage escrow = s_escrows[_escrowId];
        require(msg.sender == escrow.businessAddress, "OnlyBusiness");
        require(_amount > 0, "ZeroAmount");
        escrow.depositedAmount += _amount;
        escrow.tokenAddress.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit FundsDeposited(_escrowId, _amount);
    }

    function vote(
        string calldata _escrowId,
        bool _release
    ) external onlyOracle {
        require(!s_hasVoted[_escrowId][msg.sender], "AlreadyVoted");
        s_hasVoted[_escrowId][msg.sender] = true;
        if (_release) {
            s_releaseVotes[_escrowId]++;
        } else {
            s_refundVotes[_escrowId]++;
        }
        emit Voted(_escrowId, msg.sender, _release);
    }

    function releaseFunds(string calldata _escrowId) external nonReentrant {
        Escrow storage escrow = s_escrows[_escrowId];
        require(
            msg.sender == escrow.businessAddress || s_oracles[msg.sender],
            "NotAuthorized"
        );
        require(_majorityVote(_escrowId, true), "MajorityVoteFailed");
        uint256 amountToRelease = escrow.depositedAmount;
        require(amountToRelease > 0, "NoFunds");
        escrow.depositedAmount = 0;
        escrow.tokenAddress.safeTransfer(
            escrow.freelancerAddress,
            amountToRelease
        );
        emit FundsReleased(
            _escrowId,
            escrow.freelancerAddress,
            amountToRelease
        );
    }

    function refundFunds(string calldata _escrowId) external nonReentrant {
        Escrow storage escrow = s_escrows[_escrowId];
        require(
            msg.sender == escrow.freelancerAddress || s_oracles[msg.sender],
            "NotAuthorized"
        );
        require(_majorityVote(_escrowId, false), "MajorityVoteFailed");
        uint256 amountToRefund = escrow.depositedAmount;
        require(amountToRefund > 0, "NoFunds");
        escrow.depositedAmount = 0;
        escrow.tokenAddress.safeTransfer(
            escrow.businessAddress,
            amountToRefund
        );
        emit FundsRefunded(_escrowId, escrow.businessAddress, amountToRefund);
    }

    function _majorityVote(
        string memory _escrowId,
        bool _forRelease
    ) private view returns (bool) {
        uint256 voteCount = _forRelease
            ? s_releaseVotes[_escrowId]
            : s_refundVotes[_escrowId];
        uint256 majority = (s_escrows[_escrowId].votingOracles.length / 2) + 1;
        return voteCount >= majority;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getEscrow(
        string memory _escrowId
    )
        external
        view
        returns (
            string memory,
            address[] memory,
            address,
            address,
            uint256,
            address
        )
    {
        Escrow storage escrow = s_escrows[_escrowId];
        return (
            escrow.escrowId,
            escrow.votingOracles,
            escrow.freelancerAddress,
            escrow.businessAddress,
            escrow.depositedAmount,
            address(escrow.tokenAddress)
        );
    }
}
