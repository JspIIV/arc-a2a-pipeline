// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  AgentMarket
/// @notice Agent-to-agent (A2A) task delegation with USDC escrow on Arc.
///
///   Protocol fee : 1% of every settled task budget (PROTOCOL_FEE_BPS = 100)
///   Agent bond   : 50% of task budget locked for the duration of the task
///   Dispute window: 24 hours after task completion
///   Max task duration: 7 days from assignment (hard safety cap)
contract AgentMarket is Ownable2Step, ReentrancyGuard {
    // ─── Constants ───────────────────────────────────────────────────────────
    uint256 public constant PROTOCOL_FEE_BPS      = 100;          // 1 %
    uint256 public constant BOND_BPS              = 5_000;         // 50 %
    uint256 public constant MIN_REPUTATION        = 0;
    uint256 public constant MAX_REPUTATION        = 100;
    uint256 public constant REP_SUCCESS_DELTA     = 2;
    uint256 public constant REP_FAIL_DELTA        = 8;
    uint256 public constant DISPUTE_WINDOW_SECONDS = 86_400;       // 24 h  (fix #2)
    uint256 public constant MAX_TASK_DURATION      = 7 days;       // fix #1

    // ─── Immutables ──────────────────────────────────────────────────────────
    IERC20 public immutable usdc;
    address public immutable feeRecipient;                          // fix #4

    // ─── Data structures ─────────────────────────────────────────────────────
    struct Agent {
        uint256 id;
        string  name;
        string[] capabilities;
        uint256 pricePerTask;
        string  endpoint;
        address owner;
        uint256 tasksCompleted;
        uint256 tasksFailed;
        uint256 reputation;
        uint256 bond;
        uint256 bondLocked;
        bool    active;
    }

    enum TaskStatus {
        Open,
        InProgress,
        Completed,
        Disputed,
        Refunded,
        Expired,
        Cancelled
    }

    struct Task {
        uint256    id;
        string     title;
        string     description;
        string     capability;
        uint256    budget;
        address    poster;
        uint256    assignedAgentId;
        TaskStatus status;
        uint256    agentBond;
        uint256    createdAt;
        uint256    deadlineTs;
        bool       bondSettled;
        uint256    subAgentId;
        uint256    subAgentCost;
        uint256    completedAt;
        uint256    assignedAt;                                      // fix #1
    }

    // ─── Errors ──────────────────────────────────────────────────────────────
    error ZeroAddress();
    error EmptyString();
    error EmptyCapabilities();
    error InvalidAmount();
    error InvalidAgentId();
    error InvalidTaskId();
    error NotAgentOwner();
    error NotTaskPoster();
    error AgentInactive();
    error CapabilityNotSupported();
    error InsufficientFreeBond();
    error InvalidStatus();
    error InvalidSubAgent();
    error InvalidSubAgentCost();
    error DeadlineInPast();
    error DeadlinePassed();                                         // fix #6 (was DeadlineNotReached)
    error DeadlineRequired();                                       // fix #1
    error DisputeWindowNotPassed();                                 // fix #6 (was DisputeWindowPassed)
    error DisputeWindowExpired();                                   // used in disputeTask
    error NoDisputeWindow();
    error BondAlreadySettled();
    error TransferFailed();
    error InsufficientContractBalance();
    error PosterOwnsAgent();                                        // fix #8

    // ─── Events ──────────────────────────────────────────────────────────────
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string name);
    event BondStaked(uint256 indexed agentId, uint256 amount);
    event BondWithdrawn(uint256 indexed agentId, uint256 amount);
    event TaskPosted(uint256 indexed taskId, address indexed poster, uint256 budget);
    event TaskAssigned(uint256 indexed taskId, uint256 indexed agentId, uint256 bondLocked);
    event TaskCompleted(
        uint256 indexed taskId,
        uint256 indexed agentId,
        uint256 paidToAgent,
        uint256 subAgentId,
        uint256 subAgentCost
    );
    event TaskAccepted(uint256 indexed taskId);                     // fix #2
    event TaskFinalized(uint256 indexed taskId);
    event TaskDisputed(uint256 indexed taskId, address indexed poster, string reason);
    event DisputeResolved(uint256 indexed taskId, bool refundPoster);
    event TaskExpired(uint256 indexed taskId);
    event TaskCancelled(uint256 indexed taskId);

    // ─── Storage ─────────────────────────────────────────────────────────────
    uint256 private _agentCounter;
    uint256 private _taskCounter;

    mapping(uint256 => Agent)  private _agents;
    mapping(uint256 => Task)   private _tasks;

    mapping(uint256 => mapping(bytes32 => bool)) private _agentHasCapability;
    mapping(bytes32 => uint256[]) private _agentsByCapability;

    mapping(uint256 => bool)    private _taskPaidOut;
    mapping(uint256 => uint256) private agentPendingBond;

    // ─── Constructor ─────────────────────────────────────────────────────────
    /// @param usdc_          ERC-20 USDC address
    /// @param initialOwner   Contract owner / dispute arbitrator
    /// @param feeRecipient_  Address that receives the 1% protocol fee    (fix #4)
    constructor(address usdc_, address initialOwner, address feeRecipient_) Ownable(initialOwner) {
        if (usdc_ == address(0) || initialOwner == address(0) || feeRecipient_ == address(0))
            revert ZeroAddress();
        usdc         = IERC20(usdc_);
        feeRecipient = feeRecipient_;
    }

    // ─── Agent management ────────────────────────────────────────────────────

    function registerAgent(
        string calldata name,
        string[] calldata capabilities,
        uint256 pricePerTask,
        string calldata endpoint
    ) external {
        _validateNonEmpty(name);
        _validateNonEmpty(endpoint);
        if (capabilities.length == 0) revert EmptyCapabilities();

        _agentCounter++;
        uint256 agentId = _agentCounter;

        Agent storage agent = _agents[agentId];
        agent.id         = agentId;
        agent.name       = name;
        agent.pricePerTask = pricePerTask;
        agent.endpoint   = endpoint;
        agent.owner      = msg.sender;
        agent.reputation = 50;
        agent.active     = true;

        for (uint256 i = 0; i < capabilities.length; i++) {
            _validateNonEmpty(capabilities[i]);
            bytes32 capabilityHash = keccak256(bytes(capabilities[i]));
            if (!_agentHasCapability[agentId][capabilityHash]) {
                _agentHasCapability[agentId][capabilityHash] = true;
                _agentsByCapability[capabilityHash].push(agentId);
            }
            agent.capabilities.push(capabilities[i]);
        }

        emit AgentRegistered(agentId, msg.sender, name);
    }

    function stakeAgentBond(uint256 agentId, uint256 amount) external nonReentrant {
        _ensureValidAgent(agentId);
        if (amount == 0) revert InvalidAmount();

        Agent storage agent = _agents[agentId];
        if (agent.owner != msg.sender) revert NotAgentOwner();

        _transferFrom(msg.sender, address(this), amount);
        agent.bond += amount;

        emit BondStaked(agentId, amount);
    }

    function withdrawAgentBond(uint256 agentId, uint256 amount) external nonReentrant {
        _ensureValidAgent(agentId);
        if (amount == 0) revert InvalidAmount();

        Agent storage agent = _agents[agentId];
        if (agent.owner != msg.sender) revert NotAgentOwner();

        uint256 freeBond = agent.bond - agent.bondLocked;
        if (amount > freeBond) revert InsufficientFreeBond();
        if (agent.bond - amount < agentPendingBond[agentId]) revert InsufficientFreeBond();

        agent.bond -= amount;
        _transfer(msg.sender, amount);

        emit BondWithdrawn(agentId, amount);
    }

    // ─── Task lifecycle ──────────────────────────────────────────────────────

    /// @notice Post a task and escrow the budget.
    /// @param deadlineMs  Unix deadline in milliseconds — MUST be non-zero.   (fix #1)
    function postTask(
        string calldata title,
        string calldata description,
        string calldata capability,
        uint256 budget,
        uint256 deadlineMs
    ) external nonReentrant {
        _validateNonEmpty(title);
        _validateNonEmpty(description);
        _validateNonEmpty(capability);
        if (budget == 0) revert InvalidAmount();
        if (deadlineMs == 0) revert DeadlineRequired();             // fix #1: reject zero deadline

        uint256 deadlineTs = deadlineMs / 1000;
        if (deadlineTs <= block.timestamp) revert DeadlineInPast();

        _taskCounter++;
        uint256 taskId = _taskCounter;

        Task storage task = _tasks[taskId];
        task.id          = taskId;
        task.title       = title;
        task.description = description;
        task.capability  = capability;
        task.budget      = budget;
        task.poster      = msg.sender;
        task.status      = TaskStatus.Open;
        task.createdAt   = block.timestamp;
        task.deadlineTs  = deadlineTs;

        _transferFrom(msg.sender, address(this), budget);

        emit TaskPosted(taskId, msg.sender, budget);
    }

    function assignTask(uint256 taskId, uint256 agentId) external {
        _ensureValidTask(taskId);
        _ensureValidAgent(agentId);

        Task storage task = _tasks[taskId];
        if (task.poster != msg.sender) revert NotTaskPoster();
        if (task.status != TaskStatus.Open) revert InvalidStatus();
        if (block.timestamp >= task.deadlineTs) revert DeadlinePassed(); // fix #6

        Agent storage agent = _agents[agentId];
        if (!agent.active) revert AgentInactive();
        if (agent.owner == msg.sender) revert PosterOwnsAgent();    // fix #8

        bytes32 capHash = keccak256(bytes(task.capability));
        if (!_agentHasCapability[agentId][capHash]) revert CapabilityNotSupported();

        uint256 requiredBond = (task.budget * BOND_BPS) / 10_000;
        uint256 freeBond     = agent.bond - agent.bondLocked;
        if (freeBond < requiredBond) revert InsufficientFreeBond();

        agent.bondLocked += requiredBond;

        task.assignedAgentId = agentId;
        task.agentBond       = requiredBond;
        task.status          = TaskStatus.InProgress;
        task.assignedAt      = block.timestamp;                     // fix #1

        emit TaskAssigned(taskId, agentId, requiredBond);
    }

    /// @notice Mark a task complete and record sub-agent.
    ///         Payment is deferred until acceptTask or finalizeTask.
    function completeTask(uint256 taskId, uint256 subAgentId, uint256 subAgentCost) external nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.status != TaskStatus.InProgress) revert InvalidStatus();

        Agent storage mainAgent = _agents[task.assignedAgentId];
        if (mainAgent.owner != msg.sender) revert NotAgentOwner();

        uint256 totalFee   = (task.budget * PROTOCOL_FEE_BPS) / 10_000;
        uint256 paidToAgent;

        if (subAgentId > 0) {
            _ensureValidAgent(subAgentId);
            Agent storage sub = _agents[subAgentId];
            if (!sub.active) revert AgentInactive();                // fix #7: sub-agent must be active
            if (subAgentId == task.assignedAgentId) revert InvalidSubAgent(); // fix #7: no self-delegation
            if (subAgentCost == 0) revert InvalidSubAgentCost();

            uint256 maxSubPay = task.budget - totalFee;
            if (subAgentCost > maxSubPay) revert InvalidSubAgentCost();

            paidToAgent = maxSubPay - subAgentCost;

            task.subAgentId   = subAgentId;
            task.subAgentCost = subAgentCost;
        } else {
            if (subAgentCost != 0) revert InvalidSubAgentCost();
            paidToAgent       = task.budget - totalFee;
            task.subAgentId   = 0;
            task.subAgentCost = 0;
        }

        task.status      = TaskStatus.Completed;
        task.completedAt = block.timestamp;
        _taskPaidOut[taskId] = false;
        agentPendingBond[task.assignedAgentId] += task.agentBond;

        mainAgent.tasksCompleted += 1;
        mainAgent.reputation = _increaseReputation(mainAgent.reputation, REP_SUCCESS_DELTA);

        emit TaskCompleted(taskId, task.assignedAgentId, paidToAgent, task.subAgentId, task.subAgentCost);
    }

    /// @notice Poster explicitly accepts the result, paying out immediately    (fix #2)
    ///         and skipping the rest of the dispute window.
    function acceptTask(uint256 taskId) external nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.poster != msg.sender) revert NotTaskPoster();
        if (task.status != TaskStatus.Completed) revert InvalidStatus();

        _settleTask(taskId, task);

        emit TaskAccepted(taskId);
    }

    /// @notice Anyone can finalize after the 24-hour dispute window expires.
    function finalizeTask(uint256 taskId) external nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.status != TaskStatus.Completed) revert InvalidStatus();
        if (task.bondSettled) revert BondAlreadySettled();

        uint256 completedAt = task.completedAt;
        if (completedAt == 0) revert NoDisputeWindow();
        // fix #6: was DisputeWindowPassed — the window must have passed to finalize
        if (block.timestamp < completedAt + DISPUTE_WINDOW_SECONDS) revert DisputeWindowNotPassed();

        _settleTask(taskId, task);

        emit TaskFinalized(taskId);
    }

    function disputeTask(uint256 taskId, string calldata reason) external {
        _ensureValidTask(taskId);
        _validateNonEmpty(reason);

        Task storage task = _tasks[taskId];
        if (task.poster != msg.sender) revert NotTaskPoster();
        if (task.status != TaskStatus.Completed) revert InvalidStatus();

        uint256 completedAt = task.completedAt;
        if (completedAt == 0) revert NoDisputeWindow();
        if (block.timestamp > completedAt + DISPUTE_WINDOW_SECONDS) revert DisputeWindowExpired();

        task.status = TaskStatus.Disputed;

        emit TaskDisputed(taskId, msg.sender, reason);
    }

    function resolveDispute(uint256 taskId, bool refundPoster) external onlyOwner nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.status != TaskStatus.Disputed) revert InvalidStatus();

        Agent storage mainAgent = _agents[task.assignedAgentId];

        if (refundPoster) {
            if (mainAgent.bond < task.agentBond) revert InsufficientFreeBond();

            uint256 totalRefund = task.budget + task.agentBond;
            if (usdc.balanceOf(address(this)) < totalRefund) revert InsufficientContractBalance();

            if (!task.bondSettled) {
                _releaseAgentBond(task, mainAgent);
                agentPendingBond[task.assignedAgentId] -= task.agentBond;
            }

            mainAgent.bond      -= task.agentBond;
            mainAgent.tasksFailed += 1;
            mainAgent.reputation = _decreaseReputation(mainAgent.reputation, REP_FAIL_DELTA);

            task.status = TaskStatus.Refunded;

            _transfer(task.poster, task.budget);
            _transfer(task.poster, task.agentBond);
        } else {
            if (!_taskPaidOut[taskId]) {
                _settleTask(taskId, task);
            } else if (!task.bondSettled) {
                _releaseAgentBond(task, mainAgent);
                agentPendingBond[task.assignedAgentId] -= task.agentBond;
            }

            task.status = TaskStatus.Completed;
        }

        emit DisputeResolved(taskId, refundPoster);
    }

    function expireTask(uint256 taskId) external nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.status != TaskStatus.Open) revert InvalidStatus();
        if (task.deadlineTs == 0 || block.timestamp < task.deadlineTs) revert DeadlinePassed(); // fix #6

        task.status = TaskStatus.Expired;
        _transfer(task.poster, task.budget);

        emit TaskExpired(taskId);
    }

    function cancelTask(uint256 taskId) external nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.poster != msg.sender) revert NotTaskPoster();
        if (task.status != TaskStatus.Open) revert InvalidStatus();

        task.status = TaskStatus.Cancelled;
        _transfer(task.poster, task.budget);

        emit TaskCancelled(taskId);
    }

    /// @notice Poster aborts an in-progress task after it misses its deadline  (fix #1)
    ///         OR after MAX_TASK_DURATION since assignment (hard safety cap).
    function abortTask(uint256 taskId) external nonReentrant {
        _ensureValidTask(taskId);

        Task storage task = _tasks[taskId];
        if (task.poster != msg.sender) revert NotTaskPoster();
        if (task.status != TaskStatus.InProgress) revert InvalidStatus();

        bool deadlineExpired  = task.deadlineTs > 0 && block.timestamp >= task.deadlineTs;
        bool maxDurationHit   = task.assignedAt > 0 &&
                                block.timestamp >= task.assignedAt + MAX_TASK_DURATION;

        if (!deadlineExpired && !maxDurationHit) revert DeadlinePassed(); // fix #1 + fix #6

        Agent storage mainAgent = _agents[task.assignedAgentId];
        _releaseAgentBond(task, mainAgent);
        mainAgent.reputation = _decreaseReputation(mainAgent.reputation, REP_FAIL_DELTA);

        task.status = TaskStatus.Cancelled;
        _transfer(task.poster, task.budget);

        emit TaskCancelled(taskId);
    }

    // ─── Views ───────────────────────────────────────────────────────────────

    function getAgent(uint256 id) external view returns (Agent memory) {
        _ensureValidAgent(id);
        return _agents[id];
    }

    function getTask(uint256 id) external view returns (Task memory) {
        _ensureValidTask(id);
        return _tasks[id];
    }

    function agentCount() external view returns (uint256) { return _agentCounter; }
    function taskCount()  external view returns (uint256) { return _taskCounter; }

    function getAgentsByCapability(string calldata capability) external view returns (uint256[] memory) {
        _validateNonEmpty(capability);
        return _agentsByCapability[keccak256(bytes(capability))];
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    /// @dev Shared payout logic used by acceptTask, finalizeTask, and resolveDispute.
    function _settleTask(uint256 taskId, Task storage task) internal {
        if (task.bondSettled) revert BondAlreadySettled();

        Agent storage mainAgent = _agents[task.assignedAgentId];
        uint256 totalFee   = (task.budget * PROTOCOL_FEE_BPS) / 10_000;
        uint256 paidToAgent;

        if (task.subAgentId > 0) {
            Agent storage subAgent = _agents[task.subAgentId];
            uint256 maxSubPay = task.budget - totalFee;
            paidToAgent = maxSubPay - task.subAgentCost;
            _transfer(subAgent.owner, task.subAgentCost);
        } else {
            paidToAgent = task.budget - totalFee;
        }

        _transfer(mainAgent.owner, paidToAgent);
        _transfer(feeRecipient, totalFee);                          // fix #4: fee to feeRecipient

        _releaseAgentBond(task, mainAgent);
        agentPendingBond[task.assignedAgentId] -= task.agentBond;
        _taskPaidOut[taskId] = true;
    }

    function _releaseAgentBond(Task storage task, Agent storage agent) internal {
        if (task.bondSettled) revert BondAlreadySettled();
        agent.bondLocked  -= task.agentBond;
        task.bondSettled   = true;
    }

    function _increaseReputation(uint256 current, uint256 delta) internal pure returns (uint256) {
        uint256 next = current + delta;
        return next > MAX_REPUTATION ? MAX_REPUTATION : next;
    }

    function _decreaseReputation(uint256 current, uint256 delta) internal pure returns (uint256) {
        if (current <= MIN_REPUTATION + delta) return MIN_REPUTATION;
        return current - delta;
    }

    function _ensureValidAgent(uint256 agentId) internal view {
        if (agentId == 0 || agentId > _agentCounter) revert InvalidAgentId();
    }

    function _ensureValidTask(uint256 taskId) internal view {
        if (taskId == 0 || taskId > _taskCounter) revert InvalidTaskId();
    }

    function _validateNonEmpty(string calldata value) internal pure {
        if (bytes(value).length == 0) revert EmptyString();
    }

    function _transferFrom(address from, address to, uint256 amount) internal {
        bool ok = usdc.transferFrom(from, to, amount);
        if (!ok) revert TransferFailed();
    }

    function _transfer(address to, uint256 amount) internal {
        bool ok = usdc.transfer(to, amount);
        if (!ok) revert TransferFailed();
    }
}
