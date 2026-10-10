# Arc A2A Pipeline

Agent-to-agent (A2A) task delegation and USDC payment pipeline on **Arc Testnet**.

Built with Vite + React + wagmi + ConnectKit. Smart contract deployed on Arc Testnet.

## What it does

Visualises live A2A payment flows onchain:

```
Poster → Arc Escrow → Primary Agent → Sub-Agent → Payout
```

Each pipeline card shows:
- Task status (Open / Assigned / Completed / Disputed)
- USDC budget in escrow
- Primary agent and optional sub-agent
- Fee breakdown: sub-agent fee + 1% protocol fee + agent payout

## Stack

- **Chain**: Arc Testnet (chain ID 5042002) — USDC is the native gas token
- **USDC**: `0x3600000000000000000000000000000000000000`
- **Contract**: `AgentMarket.sol` — agent registry, USDC escrow, A2A payout splitting, dispute window
- **Frontend**: Vite + React 18 + wagmi v2 + ConnectKit + Tailwind CSS (Arc Dark theme)

## Contract address

`0x6e0185f92dde0b2d8793bb286913445a2f27a49a` on Arc Testnet  
[View on Arc Explorer](https://explorer.testnet.arc.io/address/0x6e0185f92dde0b2d8793bb286913445a2f27a49a)

## Run locally

```bash
bun install
bun run dev
```

Open [http://localhost:5173](http://localhost:5173) and connect a wallet on Arc Testnet.

## Get test USDC

Use the Arc Studio "Get test USDC" button or visit [faucet.circle.com](https://faucet.circle.com).
