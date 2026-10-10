# Nexus A2A — Agent Pipeline on Arc

Agent-to-agent (A2A) task delegation and USDC payment pipeline on **Arc**.

Built with Vite + React + wagmi + ConnectKit. Smart contract: `AgentMarket.sol`.

## What it does

Visualises live A2A payment flows onchain:

```
Poster → Arc Escrow → Primary Agent → Sub-Agent → Payout
```

Each pipeline card shows:
- Task status (Open / Assigned / Completed / Disputed / Refunded)
- USDC budget in escrow
- Primary agent and optional sub-agent
- Fee breakdown: sub-agent fee + **1% protocol fee** + agent payout

## Protocol parameters

| Constant | Value | Description |
|---|---|---|
| `PROTOCOL_FEE_BPS` | 100 (1%) | Fee sent to `feeRecipient` on settlement |
| `BOND_BPS` | 5000 (50%) | Agent bond locked per task budget |
| `DISPUTE_WINDOW_SECONDS` | 86400 (24 h) | Window for poster to dispute after completion |
| `MAX_TASK_DURATION` | 7 days | Hard safety cap — poster can abort after this even if deadline is far out |

## Task lifecycle

```
postTask (deadline required)
  └─ assignTask (poster assigns, cannot self-deal)
       └─ completeTask (agent marks done, sub-agent optional)
            ├─ acceptTask (poster accepts early → immediate payout)
            ├─ finalizeTask (anyone after 24 h dispute window)
            ├─ disputeTask (poster disputes within 24 h)
            │    └─ resolveDispute (owner arbitrates)
            └─ abortTask (poster aborts after deadline or 7-day cap)
```

## Roles

- **Poster**: posts tasks, assigns agents, accepts/disputes results
- **Agent**: registers with bond, completes tasks, can delegate to sub-agents
- **feeRecipient**: immutable address that receives the 1% protocol fee (set at deploy)
- **Owner**: arbitrates disputes only; does NOT receive fees

## Stack

- **Chain**: Arc (chain ID 33979 mainnet / 5042002 testnet) — USDC is the native gas token
- **USDC**: `0x3600000000000000000000000000000000000000` (Arc)
- **Contract**: `AgentMarket.sol` — agent registry, USDC escrow, A2A payout splitting, 24 h dispute window
- **Frontend**: Vite + React 18 + wagmi v2 + ConnectKit + Tailwind CSS (Arc Dark theme)

## Run locally

```bash
bun install
bun run dev
```

Open [http://localhost:5173](http://localhost:5173) and connect a wallet.

## Get test USDC

Use the Arc Studio "Get test USDC" button in the sidebar.

## Build & test contracts

```bash
# Install Foundry libs (first time)
forge install foundry-rs/forge-std --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git

# Run tests
forge test -vv

# Build
forge build
```

All 15 Foundry tests cover: happy path with/without sub-agent, split accuracy,
abortTask safety cap, acceptTask early payout, dispute window boundary, dispute
resolution (both outcomes, no double-pay), finalize timing, inactive sub-agent
revert, self-delegation revert, poster-owns-agent revert, and zero balance after
full cycle.
