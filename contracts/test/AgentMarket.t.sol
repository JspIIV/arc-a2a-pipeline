// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AgentMarket} from "../AgentMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ─── Mock 6-decimal USDC ─────────────────────────────────────────────────────
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) { return 6; }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Test contract ────────────────────────────────────────────────────────────
contract AgentMarketTest is Test {
    // ── Addresses ──────────────────────────────────────────────────────────
    address owner        = makeAddr("owner");
    address feeRecip     = makeAddr("feeRecipient");
    address poster       = makeAddr("poster");
    address agentOwner   = makeAddr("agentOwner");
    address subOwner     = makeAddr("subOwner");
    address stranger     = makeAddr("stranger");

    // ── Contracts ──────────────────────────────────────────────────────────
    MockUSDC usdc;
    AgentMarket market;

    // ── Constants ──────────────────────────────────────────────────────────
    uint256 constant BUDGET    = 1_000e6;         // 1 000 USDC
    uint256 constant BOND_AMT  = 500e6;           // 50 % of budget
    uint256 constant DEADLINE  = 7 days;          // far enough in the future

    // ── Helpers ────────────────────────────────────────────────────────────
    uint256 mainAgentId;
    uint256 subAgentId;
    string[] caps;

    function setUp() public {
        usdc   = new MockUSDC();
        market = new AgentMarket(address(usdc), owner, feeRecip);

        // Mint
        usdc.mint(poster,     100_000e6);
        usdc.mint(agentOwner, 100_000e6);
        usdc.mint(subOwner,   100_000e6);

        // Approve
        vm.prank(poster);    usdc.approve(address(market), type(uint256).max);
        vm.prank(agentOwner);usdc.approve(address(market), type(uint256).max);
        vm.prank(subOwner);  usdc.approve(address(market), type(uint256).max);

        // Register main agent
        caps = new string[](1);
        caps[0] = "coding";

        vm.prank(agentOwner);
        market.registerAgent("MainBot", caps, 100e6, "http://mainbot.ai");
        mainAgentId = 1;

        // Stake main agent bond (needs ≥ 50 % of any budget)
        vm.prank(agentOwner);
        market.stakeAgentBond(mainAgentId, BOND_AMT * 5);

        // Register sub-agent
        string[] memory subCaps = new string[](1);
        subCaps[0] = "coding";
        vm.prank(subOwner);
        market.registerAgent("SubBot", subCaps, 50e6, "http://subbot.ai");
        subAgentId = 2;

        vm.prank(subOwner);
        market.stakeAgentBond(subAgentId, BOND_AMT * 5);
    }

    // ── Utility: post & assign a task ──────────────────────────────────────
    function _postAndAssign() internal returns (uint256 taskId) {
        vm.prank(poster);
        market.postTask(
            "Task title",
            "Do some coding",
            "coding",
            BUDGET,
            (block.timestamp + DEADLINE) * 1000
        );
        taskId = market.taskCount();

        vm.prank(poster);
        market.assignTask(taskId, mainAgentId);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 1. Happy path: post → assign → complete → finalize, exact split
    // ══════════════════════════════════════════════════════════════════════════
    function test_HappyPath_WithSubAgent() public {
        uint256 taskId = _postAndAssign();

        uint256 subCost = 100e6;

        vm.prank(agentOwner);
        market.completeTask(taskId, subAgentId, subCost);

        // Advance past 24-hour dispute window
        vm.warp(block.timestamp + 86_401);

        uint256 agentBefore   = usdc.balanceOf(agentOwner);
        uint256 subBefore     = usdc.balanceOf(subOwner);
        uint256 feeBefore     = usdc.balanceOf(feeRecip);
        uint256 contractBefore = usdc.balanceOf(address(market));

        market.finalizeTask(taskId);

        // Expected fee = 1 % of BUDGET = 10 USDC
        uint256 fee     = (BUDGET * 100) / 10_000;         // 10e6
        uint256 mainPay = BUDGET - fee - subCost;           // 890e6
        uint256 subPay  = subCost;                          // 100e6

        assertEq(usdc.balanceOf(agentOwner), agentBefore + mainPay, "main agent payout");
        assertEq(usdc.balanceOf(subOwner),   subBefore  + subPay,   "sub-agent payout");
        assertEq(usdc.balanceOf(feeRecip),   feeBefore  + fee,      "protocol fee");

        // Sanity: sum equals budget
        assertEq(mainPay + subPay + fee, BUDGET, "split sums to budget");

        // Contract balance decreased by exactly BUDGET (bond stays in contract)
        assertEq(usdc.balanceOf(address(market)), contractBefore - BUDGET, "contract balance");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. No sub-agent: main agent gets budget minus fee only
    // ══════════════════════════════════════════════════════════════════════════
    function test_HappyPath_NoSubAgent() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.warp(block.timestamp + 86_401);

        uint256 agentBefore = usdc.balanceOf(agentOwner);
        uint256 feeBefore   = usdc.balanceOf(feeRecip);

        market.finalizeTask(taskId);

        uint256 fee     = (BUDGET * 100) / 10_000;
        uint256 mainPay = BUDGET - fee;

        assertEq(usdc.balanceOf(agentOwner), agentBefore + mainPay, "agent payout no-sub");
        assertEq(usdc.balanceOf(feeRecip),   feeBefore + fee,       "fee no-sub");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3. abortTask succeeds after MAX_TASK_DURATION even if deadline is far out
    // ══════════════════════════════════════════════════════════════════════════
    function test_AbortTask_MaxDurationSafetyCap() public {
        // Post with a deadline of 30 days
        vm.prank(poster);
        market.postTask(
            "Long task",
            "Takes ages",
            "coding",
            BUDGET,
            (block.timestamp + 30 days) * 1000
        );
        uint256 taskId = market.taskCount();

        vm.prank(poster);
        market.assignTask(taskId, mainAgentId);

        // Advance past MAX_TASK_DURATION (7 days) but NOT past the 30-day deadline
        vm.warp(block.timestamp + 7 days + 1);

        uint256 posterBefore = usdc.balanceOf(poster);

        vm.prank(poster);
        market.abortTask(taskId);

        assertEq(usdc.balanceOf(poster), posterBefore + BUDGET, "poster refunded after max duration");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4. postTask rejects deadlineMs == 0
    // ══════════════════════════════════════════════════════════════════════════
    function test_PostTask_RejectsZeroDeadline() public {
        vm.expectRevert(AgentMarket.DeadlineRequired.selector);
        vm.prank(poster);
        market.postTask("T", "D", "coding", BUDGET, 0);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5. acceptTask by poster pays immediately inside window
    // ══════════════════════════════════════════════════════════════════════════
    function test_AcceptTask_PayoutImmediate() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        // Still inside the 24-hour window
        vm.warp(block.timestamp + 1 hours);

        uint256 agentBefore = usdc.balanceOf(agentOwner);

        vm.prank(poster);
        market.acceptTask(taskId);

        uint256 fee = (BUDGET * 100) / 10_000;
        assertEq(usdc.balanceOf(agentOwner), agentBefore + BUDGET - fee, "agent paid on accept");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 6. acceptTask by non-poster reverts
    // ══════════════════════════════════════════════════════════════════════════
    function test_AcceptTask_RevertsIfNotPoster() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.expectRevert(AgentMarket.NotTaskPoster.selector);
        vm.prank(stranger);
        market.acceptTask(taskId);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 7. disputeTask inside window works, outside it reverts
    // ══════════════════════════════════════════════════════════════════════════
    function test_DisputeTask_WindowBoundary() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        // Inside window — should succeed
        vm.prank(poster);
        market.disputeTask(taskId, "not happy");

        // Restore to Completed to test outside-window revert
        // We need a fresh task
        uint256 taskId2 = _postAndAssign();
        vm.prank(agentOwner);
        market.completeTask(taskId2, 0, 0);

        vm.warp(block.timestamp + 86_401);

        vm.expectRevert(AgentMarket.DisputeWindowExpired.selector);
        vm.prank(poster);
        market.disputeTask(taskId2, "too late");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8. resolveDispute(true): poster refund + bond slash
    // ══════════════════════════════════════════════════════════════════════════
    function test_ResolveDispute_RefundPoster() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.prank(poster);
        market.disputeTask(taskId, "bad work");

        uint256 posterBefore      = usdc.balanceOf(poster);
        uint256 agentBondBefore   = market.getAgent(mainAgentId).bond;

        vm.prank(owner);
        market.resolveDispute(taskId, true);

        // Poster gets budget + slashed bond
        assertEq(usdc.balanceOf(poster), posterBefore + BUDGET + BOND_AMT, "poster full refund + slash");

        // Agent bond reduced
        assertEq(market.getAgent(mainAgentId).bond, agentBondBefore - BOND_AMT, "agent bond slashed");

        // Reputation decreased
        assertLt(market.getAgent(mainAgentId).reputation, 50, "reputation decreased");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9. resolveDispute(false) pays agent and does not pay twice
    // ══════════════════════════════════════════════════════════════════════════
    function test_ResolveDispute_FavorAgent_NoDuplicate() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.prank(poster);
        market.disputeTask(taskId, "disputing");

        uint256 agentBefore = usdc.balanceOf(agentOwner);

        vm.prank(owner);
        market.resolveDispute(taskId, false);

        uint256 fee     = (BUDGET * 100) / 10_000;
        uint256 mainPay = BUDGET - fee;
        assertEq(usdc.balanceOf(agentOwner), agentBefore + mainPay, "agent paid on resolve(false)");

        // Calling again should revert (task is now Completed/bondSettled)
        vm.expectRevert(AgentMarket.InvalidStatus.selector);
        vm.prank(owner);
        market.resolveDispute(taskId, false);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 10. finalizeTask before window reverts
    // ══════════════════════════════════════════════════════════════════════════
    function test_FinalizeTask_BeforeWindowReverts() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.expectRevert(AgentMarket.DisputeWindowNotPassed.selector);
        market.finalizeTask(taskId);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 11. finalizeTask twice reverts (bond already settled on second call)
    // ══════════════════════════════════════════════════════════════════════════
    function test_FinalizeTask_TwiceReverts() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.warp(block.timestamp + 86_401);
        market.finalizeTask(taskId);

        // After finalize the task status stays Completed but bondSettled = true;
        // the second call hits BondAlreadySettled before the status check.
        vm.expectRevert(AgentMarket.BondAlreadySettled.selector);
        market.finalizeTask(taskId);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 12. completeTask with inactive sub-agent reverts
    //     Uses vm.store to flip the `active` bool in the _agents mapping.
    //     _agents is at storage slot 2 (after _agentCounter at 0, _taskCounter at 1).
    //     Agent struct static layout (dynamic strings/arrays take 1 slot each):
    //       +0  id          +1  name(len)   +2  capabilities(len)
    //       +3  pricePerTask +4  endpoint(len) +5  owner
    //       +6  tasksCompleted +7 tasksFailed  +8  reputation
    //       +9  bond         +10 bondLocked    +11 active
    // ══════════════════════════════════════════════════════════════════════════
    function test_CompleteTask_InactiveSubAgentReverts() public {
        string[] memory c = new string[](1);
        c[0] = "coding";
        address sub3owner = makeAddr("sub3owner");
        usdc.mint(sub3owner, 100_000e6);
        vm.prank(sub3owner); usdc.approve(address(market), type(uint256).max);
        vm.prank(sub3owner); market.registerAgent("Sub3", c, 1e6, "http://s3.ai");
        uint256 sub3Id = market.agentCount();

        // Verify active is currently true
        assertTrue(market.getAgent(sub3Id).active, "sub3 should start active");

        // _agents mapping is at slot 5 (confirmed via `forge inspect AgentMarket storage-layout`)
        bytes32 base = keccak256(abi.encode(sub3Id, uint256(5)));
        // Slot base+11 holds the `active` bool
        vm.store(address(market), bytes32(uint256(base) + 11), bytes32(0));

        // Confirm the flip worked
        assertFalse(market.getAgent(sub3Id).active, "sub3 should be inactive after vm.store");

        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        vm.expectRevert(AgentMarket.AgentInactive.selector);
        market.completeTask(taskId, sub3Id, 50e6);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 13. completeTask with subAgentId == assignedAgentId reverts
    // ══════════════════════════════════════════════════════════════════════════
    function test_CompleteTask_SelfDelegationReverts() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        vm.expectRevert(AgentMarket.InvalidSubAgent.selector);
        market.completeTask(taskId, mainAgentId, 100e6);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 14. assignTask reverts when poster owns the agent (reputation farming)
    // ══════════════════════════════════════════════════════════════════════════
    function test_AssignTask_PosterOwnsAgent_Reverts() public {
        // Poster registers their own agent
        string[] memory c = new string[](1);
        c[0] = "coding";
        vm.prank(poster);
        market.registerAgent("PosterBot", c, 1e6, "http://posterbot.ai");
        uint256 posterAgentId = market.agentCount();

        // Stake enough bond
        vm.prank(poster); market.stakeAgentBond(posterAgentId, BOND_AMT * 5);

        // Post a task
        vm.prank(poster);
        market.postTask(
            "Self task",
            "Farming rep",
            "coding",
            BUDGET,
            (block.timestamp + DEADLINE) * 1000
        );
        uint256 taskId = market.taskCount();

        // Try to assign to own agent — must revert
        vm.expectRevert(AgentMarket.PosterOwnsAgent.selector);
        vm.prank(poster);
        market.assignTask(taskId, posterAgentId);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 15. Contract USDC balance returns to zero after full settlement + bond withdrawal
    // ══════════════════════════════════════════════════════════════════════════
    function test_ContractBalanceZeroAfterFullCycle() public {
        uint256 taskId = _postAndAssign();

        vm.prank(agentOwner);
        market.completeTask(taskId, 0, 0);

        vm.warp(block.timestamp + 86_401);
        market.finalizeTask(taskId);

        // Now the task budget has been paid out; bond is freed (unlocked) but still in contract.
        // Agent withdraws bond.
        uint256 freeBond = market.getAgent(mainAgentId).bond - market.getAgent(mainAgentId).bondLocked;
        vm.prank(agentOwner);
        market.withdrawAgentBond(mainAgentId, freeBond);

        // Contract should hold 0 (minus any other bond stakes; agent staked 5× BOND_AMT,
        // only 1× was used and freed; 4× remain staked).
        // So what remains is the 4 un-withdrawn stakes.
        // For a true zero we withdraw all remaining bond too.
        uint256 remainingBond = market.getAgent(mainAgentId).bond;
        if (remainingBond > 0) {
            vm.prank(agentOwner);
            market.withdrawAgentBond(mainAgentId, remainingBond);
        }
        uint256 remainingSub = market.getAgent(subAgentId).bond;
        if (remainingSub > 0) {
            vm.prank(subOwner);
            market.withdrawAgentBond(subAgentId, remainingSub);
        }

        assertEq(usdc.balanceOf(address(market)), 0, "contract balance zero after full cycle");
    }
}
