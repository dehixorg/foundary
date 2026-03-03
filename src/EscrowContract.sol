// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// IMPORTS
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// CONTRACT
contract FreelanceMarketplace is ReentrancyGuard, Ownable {

    using SafeERC20 for IERC20;

    // CONSTRUCTOR
    constructor() Ownable(msg.sender) {}

    // ENUM FOR TASK STATUS
    enum Status {
        Open,
        Proposed,
        Accepted,
        Funded,
        Submitted,
        Approved,
        Disputed,
        Resolved,
        Refunded
    }

    // STRUCT FOR TOKEN PAYMENT
    struct TokenPayment {
        address token;      // address(0) means ETH
        uint256 amount;     // token amount
    }

    // STRUCT FOR TASK
    struct Task {
        address client;         // task creator
        address freelancer;     // assigned freelancer

        string title;           // task title
        string description;     // task description

        uint256 deadline;       // deadline timestamp
        uint256 submissionTime; // when freelancer submitted

        Status status;          // current task status

        TokenPayment[] proposal; // multi-token proposal
    }

    // STORAGE VARIABLES
    uint256 public taskCounter;                        // total tasks
    uint256 public constant MAX_TOKENS = 5;            // limit proposal tokens
    uint256 public constant DISPUTE_WINDOW = 48 hours; // 48 hour window

    mapping(uint256 => Task) private tasks;            // taskId => Task

    // EVENTS
    event TaskCreated(uint256 indexed id);
    event PaymentProposed(uint256 indexed id);
    event ProposalAccepted(uint256 indexed id);
    event TaskFunded(uint256 indexed id);
    event WorkSubmitted(uint256 indexed id);
    event TaskApproved(uint256 indexed id);
    event TaskDisputed(uint256 indexed id);
    event TaskResolved(uint256 indexed id, bool freelancerWon);

    // MODIFIER: ONLY CLIENT
    modifier onlyClient(uint256 id) {
        require(msg.sender == tasks[id].client, "Not client");
        _;
    }

    // MODIFIER: ONLY FREELANCER
    modifier onlyFreelancer(uint256 id) {
        require(msg.sender == tasks[id].freelancer, "Not freelancer");
        _;
    }

    // MODIFIER: CHECK STATUS
    modifier inStatus(uint256 id, Status s) {
        require(tasks[id].status == s, "Invalid state");
        _;
    }

    // CREATE TASK FUNCTION
    function createTask(
        string calldata _title,
        string calldata _description,
        address _freelancer,
        uint256 _deadline
    ) external {

        require(_freelancer != address(0), "Invalid freelancer");

        taskCounter++;

        Task storage t = tasks[taskCounter];

        t.client = msg.sender;
        t.freelancer = _freelancer;
        t.title = _title;
        t.description = _description;
        t.deadline = _deadline;
        t.status = Status.Open;

        emit TaskCreated(taskCounter);
    }

    // FREELANCER PROPOSE PAYMENT
    function proposePayment(
        uint256 id,
        address[] calldata tokens,
        uint256[] calldata amounts
    )
        external
        onlyFreelancer(id)
        inStatus(id, Status.Open)
    {
        require(tokens.length == amounts.length, "Length mismatch");
        require(tokens.length > 0, "Empty proposal");
        require(tokens.length <= MAX_TOKENS, "Too many tokens");

        Task storage t = tasks[id];

        delete t.proposal;

        for (uint256 i = 0; i < tokens.length; i++) {
            require(amounts[i] > 0, "Zero amount");
            t.proposal.push(TokenPayment(tokens[i], amounts[i]));
        }

        t.status = Status.Proposed;

        emit PaymentProposed(id);
    }

    // CLIENT ACCEPT PROPOSAL
    function acceptProposal(uint256 id)
        external
        onlyClient(id)
        inStatus(id, Status.Proposed)
    {
        tasks[id].status = Status.Accepted;

        emit ProposalAccepted(id);
    }

    // CLIENT FUND TASK
    function fundTask(uint256 id)
        external
        payable
        nonReentrant
        onlyClient(id)
        inStatus(id, Status.Accepted)
    {
        Task storage t = tasks[id];

        uint256 ethRequired;

        // CHECK PHASE
        for (uint256 i = 0; i < t.proposal.length; i++) {
            if (t.proposal[i].token == address(0)) {
                ethRequired += t.proposal[i].amount;
            }
        }

        require(msg.value == ethRequired, "Incorrect ETH");

        // INTERACTION PHASE
        for (uint256 i = 0; i < t.proposal.length; i++) {
            if (t.proposal[i].token != address(0)) {
                IERC20(t.proposal[i].token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    t.proposal[i].amount
                );
            }
        }

        // EFFECT PHASE
        t.status = Status.Funded;

        emit TaskFunded(id);
    }

    // FREELANCER SUBMIT WORK
    function submitWork(uint256 id)
        external
        onlyFreelancer(id)
        inStatus(id, Status.Funded)
    {
        tasks[id].submissionTime = block.timestamp;
        tasks[id].status = Status.Submitted;

        emit WorkSubmitted(id);
    }

    // CLIENT APPROVE TASK
    function approve(uint256 id)
        external
        nonReentrant
        onlyClient(id)
        inStatus(id, Status.Submitted)
    {
        _release(id);

        tasks[id].status = Status.Approved;

        emit TaskApproved(id);
    }

    // CLIENT RAISE DISPUTE
    function dispute(uint256 id)
        external
        onlyClient(id)
        inStatus(id, Status.Submitted)
    {
        require(
            block.timestamp <= tasks[id].submissionTime + DISPUTE_WINDOW,
            "Dispute window expired"
        );

        tasks[id].status = Status.Disputed;

        emit TaskDisputed(id);
    }

    // ADMIN RESOLVE DISPUTE
    function resolve(uint256 id, bool freelancerWins)
        external
        onlyOwner
        nonReentrant
        inStatus(id, Status.Disputed)
    {
        if (freelancerWins) {
            _release(id);
        } else {
            _refund(id);
        }

        tasks[id].status = Status.Resolved;

        emit TaskResolved(id, freelancerWins);
    }

    // INTERNAL RELEASE FUNCTION
    function _release(uint256 id) internal {

        Task storage t = tasks[id];

        for (uint256 i = 0; i < t.proposal.length; i++) {
            if (t.proposal[i].token == address(0)) {
                payable(t.freelancer).transfer(t.proposal[i].amount);
            } else {
                IERC20(t.proposal[i].token).safeTransfer(
                    t.freelancer,
                    t.proposal[i].amount
                );
            }
        }
    }

    // INTERNAL REFUND FUNCTION
    function _refund(uint256 id) internal {

        Task storage t = tasks[id];

        for (uint256 i = 0; i < t.proposal.length; i++) {
            if (t.proposal[i].token == address(0)) {
                payable(t.client).transfer(t.proposal[i].amount);
            } else {
                IERC20(t.proposal[i].token).safeTransfer(
                    t.client,
                    t.proposal[i].amount
                );
            }
        }
    }

    // VIEW BASIC TASK INFO
    function getTaskBasic(uint256 id)
        external
        view
        returns (
            address client,
            address freelancer,
            Status status
        )
    {
        Task storage t = tasks[id];
        return (t.client, t.freelancer, t.status);
    }
}