// SPDX-License-Identifier: MIT


// pragma solidity ^0.8.28;

// import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
// import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";


// contract FreelancerContract is ReentrancyGuard {

//     using SafeERC20 for IERC20;

//     enum State { Paid, Unpaid, Pending }

//     struct FreelancerPayment {
//         string freelancerId;
//         string projectId;
//         uint256 totalAmount;
//         State state;
//     }

//     struct Milestone {
//         string milestoneId;
//         string projectId;
//         uint256 milestoneNumber;
//         uint256 milestoneCompleted;
//         mapping(uint256 => FreelancerPayment) freelancerPayments;
//     }

//     struct Project {
//         string projectId;
//         bool isActive;
//         uint256 totalApplications;
//         mapping(string => uint256) appliedFreelancers;
//         mapping(string => Milestone) milestones;
//     }

//     struct Freelancer {
//         string freelancerId;
//         address freelancerAddress;
//         mapping(string => Project) projects;
//     }

//     struct Business {
//         string businessId;
//         address businessAddress;
//         mapping(string => Project) projects;
//     }

//     struct Hiring {
//         string hiringId;
//         mapping(string => Freelancer) freelancers;
//         bool feesStatus;
//     }

//     struct Oracle {
//         string oracleId;
//         address oracleAddress;
//     }

//     struct Escrow {
//         string escrowId;
//         address[] votingOracles;
//         address freelancerAddress;
//         address businessAddress;
//         string projectId;
//         uint256 depositedAmount;
//         IERC20 tokenAddress;
//     }

//     address private immutable owner;

//     mapping(string => Freelancer) public freelancers;
//     mapping(string => Project) public projects;
//     mapping(string => Business) public businesses;
//     mapping(string => Hiring) public hirings;
//     mapping(string => Oracle) public oracles;
//     mapping(string => Escrow) public escrows;

//     mapping(address => bool) public isOracles;
//     mapping(address => mapping(bool => bool)) public oracleVotes;

//     event FreelancerAdded(string indexed freelancerId, address freelancerAddress);
//     event BusinessAdded(string indexed businessId, address businessAddress);
//     event ProjectCreated(string indexed projectId, bool isActive);
//     event MilestoneAdded(string indexed projectId, string milestoneId);
//     event PaymentAdded(string indexed milestoneId, uint256 paymentId);
//     event FundsDeposited(address businessAddress, uint256 amount);
//     event FundsReleased(address freelancerAddress, uint256 amount);
//     event FundsRefunded(address freelancerAddress, uint256 amount);

//     constructor() {
//         owner = msg.sender;
//     }

//     modifier onlyOwner() {
//         require(msg.sender == owner, "Not the contract owner");
//         _;
//     }

//     modifier onlyBuyerOrOracle(string memory _escrowId) {
//         require(msg.sender == escrows[_escrowId].businessAddress || isOracles[msg.sender], "Not Authorized!");
//         _;
//     }

//     modifier onlyWhenDeposited(string memory _escrowId) {
//         require(escrows[_escrowId].depositedAmount > 0, "No funds to release or refund!");
//         _;
//     }

//     modifier onlySellerOrOracle(string memory _escrowId) {
//         require(msg.sender == escrows[_escrowId].freelancerAddress || isOracles[msg.sender], "Not Authorized!");
//         _;
//     }

//     function addBusiness(string memory _businessId, address _businessAddress) public onlyOwner {
//         require(bytes(_businessId).length != 0, "Business ID cannot be empty");
//         require(_businessAddress != address(0), "Business address cannot be 0");

//         require(bytes(businesses[_businessId].businessId).length == 0, "Business ID already exists");
//         businesses[_businessId].businessId = _businessId;

//         businesses[_businessId].businessAddress = _businessAddress;
//         emit BusinessAdded(_businessId, _businessAddress);
//     }

//     function addFreelancerToDehix(string memory _freelancerId, address _freelancerAddress) external onlyOwner {
//         require(bytes(_freelancerId).length != 0, "Freelancer ID cannot be empty");
//         require(_freelancerAddress != address(0), "Freelancer address cannot be 0");

//         freelancers[_freelancerId].freelancerId = _freelancerId;
//         freelancers[_freelancerId].freelancerAddress = _freelancerAddress;
//         emit FreelancerAdded(_freelancerId, _freelancerAddress);
//     }

//     function createProjectToDehix(string memory _businessId, string memory _projectId) external onlyOwner returns (string memory) {
//         require(bytes(_projectId).length != 0, "Project ID cannot be empty");
//         projects[_projectId].projectId = _projectId;
//         projects[_projectId].isActive = true;

//         emit ProjectCreated(_projectId, true);
//         return _projectId;
//     }

//     function addMilestone(string memory _projectId, uint256 _milestoneNumber, string memory _milestoneId) external onlyOwner {
//         require(projects[_projectId].isActive, "Project is not active");

//         projects[_projectId].milestones[_milestoneId].milestoneId = _milestoneId;
//         projects[_projectId].milestones[_milestoneId].projectId = _projectId;
//         projects[_projectId].milestones[_milestoneId].milestoneNumber = _milestoneNumber;
//         projects[_projectId].milestones[_milestoneId].milestoneCompleted = 0;

//         emit MilestoneAdded(_projectId, _milestoneId);
//     }

//     function addFreelancerPayment(string memory _milestoneId, string memory _freelancerId, string memory _projectId, uint256 _amount, State _state) external onlyOwner {
//         Milestone storage milestone = projects[_projectId].milestones[_milestoneId];
//         uint256 paymentId = milestone.milestoneCompleted++;
//         milestone.freelancerPayments[paymentId] = FreelancerPayment({freelancerId: _freelancerId, projectId: _projectId, totalAmount: _amount, state: _state});

//         emit PaymentAdded(_milestoneId, paymentId);
//     }

//     function applyToProject(string memory _projectId, string memory _freelancerId) external {
//         Project storage project = projects[_projectId];
//         require(project.isActive, "Project is not active");
//         require(project.appliedFreelancers[_freelancerId] == 0, "Freelancer has already applied to this project");
//         project.appliedFreelancers[_freelancerId] = 1; // Mark freelancer as applied
//         project.totalApplications++;

//     }

//     function deactivateProject(string memory _projectId) external onlyOwner {
//         projects[_projectId].isActive = false;
//     }

//     function assignOracle(string memory _oracleId, address _oracleAddress) external onlyOwner {
//         oracles[_oracleId].oracleId = _oracleId;
//         oracles[_oracleId].oracleAddress = _oracleAddress;
//     }

//     function createEscrow(string memory _escrowId, address[] memory _votingOracles, address _freelancer, address _business, string memory _projectId, address _tokenAddress) public {
//         require(_votingOracles.length == 1 || _votingOracles.length == 3 || _votingOracles.length == 5, "Number of arbiters must be 1, 3, or 5");
//         escrows[_escrowId].escrowId = _escrowId;
//         escrows[_escrowId].votingOracles = _votingOracles;
//         escrows[_escrowId].freelancerAddress = _freelancer;
//         escrows[_escrowId].businessAddress = _business;
//         escrows[_escrowId].projectId = _projectId;
//         escrows[_escrowId].depositedAmount = 0;
//         escrows[_escrowId].tokenAddress = IERC20(_tokenAddress);

//         for (uint256 i = 0; i < _votingOracles.length; i++) {
//             require(_votingOracles[i] != address(0), "Arbiter address cannot be zero");
//             isOracles[_votingOracles[i]] = true;
//         }
//     }

//     function depositFundsToEscrow(uint256 _amount, string memory _escrowId) external {
//         require(msg.sender == escrows[_escrowId].businessAddress, "Only buyer can deposit funds!");
//         require(_amount > 0, "Deposit must be greater than zero!");

//         escrows[_escrowId].tokenAddress.safeTransferFrom(msg.sender, address(this), _amount);
//         escrows[_escrowId].depositedAmount += _amount;

//         emit FundsDeposited(msg.sender, _amount);
//     }

//     function releaseEscrowFunds(string memory _escrowId) external onlyBuyerOrOracle(_escrowId) onlyWhenDeposited(_escrowId) nonReentrant {
//         //checked the vernability is solved.
//         require(_majorityVote(_escrowId, true), "Majority vote required to release funds!");

//         escrows[_escrowId].tokenAddress.safeTransfer(escrows[_escrowId].freelancerAddress, escrows[_escrowId].depositedAmount);
//         escrows[_escrowId].depositedAmount = 0;
//         emit FundsReleased(escrows[_escrowId].freelancerAddress, escrows[_escrowId].depositedAmount);
//     }

//     function refundFundsOfEscrow(string memory _escrowId) external onlySellerOrOracle(_escrowId) onlyWhenDeposited(_escrowId) {
//         require(_majorityVote(_escrowId, false), "Majority vote required to refund funds!");

//         escrows[_escrowId].tokenAddress.safeTransfer(escrows[_escrowId].businessAddress, escrows[_escrowId].depositedAmount);
//         emit FundsRefunded(escrows[_escrowId].businessAddress, escrows[_escrowId].depositedAmount);
//         escrows[_escrowId].depositedAmount = 0;
//     }

//     function getMilestone(string memory _projectId, string memory _milestoneId) external view returns (string memory milestoneId, string memory projectId, uint256 milestoneNumber, uint256 milestoneCompleted) {
//         Milestone storage milestone = projects[_projectId].milestones[_milestoneId];
//         return (milestone.milestoneId, milestone.projectId, milestone.milestoneNumber, milestone.milestoneCompleted);
//     }

//     function getFreelancerPayment(string memory _projectId, string memory _milestoneId, uint256 _paymentIndex) external view returns (string memory freelancerId, string memory projectId, uint256 totalAmount, State state) {
//         Milestone storage milestone = projects[_projectId].milestones[_milestoneId];
//         FreelancerPayment storage payment = milestone.freelancerPayments[_paymentIndex];
//         return (payment.freelancerId, payment.projectId, payment.totalAmount, payment.state);
//     }

//     function escrow(string memory _escrowId) external view returns (string memory escrowId, address[] memory votingOracles, address freelancerAddress, address businessAddress, string memory projectId, uint256 depositedAmount) {
//         Escrow storage escrowDetails = escrows[_escrowId];
//         return (escrowDetails.escrowId, escrowDetails.votingOracles, escrowDetails.freelancerAddress, escrowDetails.businessAddress, escrowDetails.projectId, escrowDetails.depositedAmount);
//     }

//     function _majorityVote(string memory _escrowId, bool release) private view returns (bool) {
//         uint256 votes = 0;
//         uint256 oracleCount = escrows[_escrowId].votingOracles.length;
//         for (uint256 i = 0; i < oracleCount; i++) {
//             if (_oracleVoted(escrows[_escrowId].votingOracles[i], release)) {
//                 votes++;
//             }
//         }
//         return votes > escrows[_escrowId].votingOracles.length / 2;
//     }

//     function vote(bool release) external {
//         require(isOracles[msg.sender], "Only arbiters can vote!");
//         oracleVotes[msg.sender][release] = true;
//     }

//     function _oracleVoted(address _oracle, bool _release) private view returns (bool) {
//         return oracleVotes[_oracle][_release];
//     }
// }

 

// src/FreelancerContract.sol

pragma solidity ^0.8.28;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract FreelancerContract is ReentrancyGuard {
    using SafeERC20 for IERC20;

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

    mapping(string => Freelancer) public s_freelancers;
    mapping(string => Project) public s_projects;
    mapping(string => Business) public s_businesses;
    mapping(string => Escrow) public s_escrows;
    mapping(address => bool) public s_oracles;

    mapping(string => mapping(address => bool)) private s_hasVoted;
    mapping(string => uint256) private s_releaseVotes;
    mapping(string => uint256) private s_refundVotes;

    event FreelancerAdded(string indexed freelancerId, address indexed freelancerAddress);
    event BusinessAdded(string indexed businessId, address indexed businessAddress);
    event ProjectCreated(string indexed projectId);
    event ProjectDeactivated(string indexed projectId);
    event OracleAdded(address indexed oracleAddress);
    event OracleRemoved(address indexed oracleAddress);
    event EscrowCreated(string indexed escrowId, address indexed business, address indexed freelancer);
    event FundsDeposited(string indexed escrowId, uint256 amount);
    event FundsReleased(string indexed escrowId, address indexed to, uint256 amount);
    event FundsRefunded(string indexed escrowId, address indexed to, uint256 amount);
    event Voted(string indexed escrowId, address indexed oracle, bool voteForRelease);

    modifier onlyOwner() {
        require(msg.sender == i_owner, "OnlyOwner");
        _;
    }

    modifier onlyOracle() {
        require(s_oracles[msg.sender], "OnlyOracle");
        _;
    }

    constructor() {
        i_owner = msg.sender;
    }

    function addBusiness(string memory _businessId, address _businessAddress) external onlyOwner {
        require(bytes(_businessId).length > 0, "EmptyBusinessId");
        require(_businessAddress != address(0), "ZeroAddress");
        require(bytes(s_businesses[_businessId].businessId).length == 0, "BusinessExists");

        Business storage newBusiness = s_businesses[_businessId];
        newBusiness.businessId = _businessId;
        newBusiness.businessAddress = _businessAddress;
        
        emit BusinessAdded(_businessId, _businessAddress);
    }

    function addFreelancer(string memory _freelancerId, address _freelancerAddress) external onlyOwner {
        require(bytes(_freelancerId).length > 0, "EmptyFreelancerId");
        require(_freelancerAddress != address(0), "ZeroAddress");

        Freelancer storage newFreelancer = s_freelancers[_freelancerId];
        newFreelancer.freelancerId = _freelancerId;
        newFreelancer.freelancerAddress = _freelancerAddress;

        emit FreelancerAdded(_freelancerId, _freelancerAddress);
    }

    function createProject(string memory _projectId) external onlyOwner {
        require(bytes(_projectId).length > 0, "EmptyProjectId");
        
        Project storage newProject = s_projects[_projectId];
        newProject.projectId = _projectId;
        newProject.isActive = true;

        emit ProjectCreated(_projectId);
    }

    function deactivateProject(string memory _projectId) external onlyOwner {
        s_projects[_projectId].isActive = false;
        emit ProjectDeactivated(_projectId);
    }

    function addOracle(address _oracleAddress) external onlyOwner {
        require(_oracleAddress != address(0), "ZeroAddress");
        s_oracles[_oracleAddress] = true;
        emit OracleAdded(_oracleAddress);
    }

    function removeOracle(address _oracleAddress) external onlyOwner {
        s_oracles[_oracleAddress] = false;
        emit OracleRemoved(_oracleAddress);
    }

    function applyToProject(string memory _projectId, address _freelancerAddress) external {
        Project storage project = s_projects[_projectId];
        require(project.isActive, "ProjectNotActive");
        require(!project.appliedFreelancers[_freelancerAddress], "AlreadyApplied");
        
        project.appliedFreelancers[_freelancerAddress] = true;
    }

    function createEscrow(string memory _escrowId, address[] memory _votingOracles, address _freelancer, address _tokenAddress) external {
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

    function depositFunds(uint256 _amount, string memory _escrowId) external {
        Escrow storage escrow = s_escrows[_escrowId];
        require(msg.sender == escrow.businessAddress, "OnlyBusiness");
        require(_amount > 0, "ZeroAmount");

        escrow.depositedAmount += _amount;
        escrow.tokenAddress.safeTransferFrom(msg.sender, address(this), _amount);

        emit FundsDeposited(_escrowId, _amount);
    }

    function vote(string memory _escrowId, bool _release) external onlyOracle {
        require(!s_hasVoted[_escrowId][msg.sender], "AlreadyVoted");

        s_hasVoted[_escrowId][msg.sender] = true;
        if (_release) {
            s_releaseVotes[_escrowId]++;
        } else {
            s_refundVotes[_escrowId]++;
        }
        emit Voted(_escrowId, msg.sender, _release);
    }

    function releaseFunds(string memory _escrowId) external nonReentrant {
        Escrow storage escrow = s_escrows[_escrowId];
        require(msg.sender == escrow.businessAddress || s_oracles[msg.sender], "NotAuthorized");
        require(_majorityVote(_escrowId, true), "MajorityVoteFailed");
        
        uint256 amountToRelease = escrow.depositedAmount;
        require(amountToRelease > 0, "NoFunds");

        escrow.depositedAmount = 0;
        
        escrow.tokenAddress.safeTransfer(escrow.freelancerAddress, amountToRelease);
        emit FundsReleased(_escrowId, escrow.freelancerAddress, amountToRelease);
    }

    function refundFunds(string memory _escrowId) external nonReentrant {
        Escrow storage escrow = s_escrows[_escrowId];
        require(msg.sender == escrow.freelancerAddress || s_oracles[msg.sender], "NotAuthorized");
        require(_majorityVote(_escrowId, false), "MajorityVoteFailed");

        uint256 amountToRefund = escrow.depositedAmount;
        require(amountToRefund > 0, "NoFunds");

        escrow.depositedAmount = 0;

        escrow.tokenAddress.safeTransfer(escrow.businessAddress, amountToRefund);
        emit FundsRefunded(_escrowId, escrow.businessAddress, amountToRefund);
    }
    
    function _majorityVote(string memory _escrowId, bool _forRelease) private view returns (bool) {
        uint256 voteCount = _forRelease ? s_releaseVotes[_escrowId] : s_refundVotes[_escrowId];
        uint256 majority = (s_escrows[_escrowId].votingOracles.length / 2) + 1;
        return voteCount >= majority;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    // NEW GETTER FUNCTION
    function getEscrow(string memory _escrowId) external view returns (string memory, address[] memory, address, address, uint256, address) {
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