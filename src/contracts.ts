export const AGENT_MARKET_ABI = [
  // ── Events ──────────────────────────────────────────────────────────
  { type: 'event', name: 'AgentRegistered',   inputs: [{ name: 'agent',  type: 'address', indexed: true }, { name: 'name', type: 'string', indexed: false }, { name: 'bondAmount', type: 'uint256', indexed: false }] },
  { type: 'event', name: 'AgentDeregistered', inputs: [{ name: 'agent',  type: 'address', indexed: true }] },
  { type: 'event', name: 'TaskPosted',        inputs: [{ name: 'taskId', type: 'uint256', indexed: true }, { name: 'poster', type: 'address', indexed: true }, { name: 'budget', type: 'uint256', indexed: false }, { name: 'description', type: 'string', indexed: false }] },
  { type: 'event', name: 'TaskAssigned',      inputs: [{ name: 'taskId', type: 'uint256', indexed: true }, { name: 'agent',  type: 'address', indexed: true }] },
  { type: 'event', name: 'TaskCompleted',     inputs: [{ name: 'taskId', type: 'uint256', indexed: true }, { name: 'agent',  type: 'address', indexed: true }, { name: 'subAgent', type: 'address', indexed: false }] },
  { type: 'event', name: 'TaskFinalized',     inputs: [{ name: 'taskId', type: 'uint256', indexed: true }, { name: 'agentPay', type: 'uint256', indexed: false }, { name: 'subAgentPay', type: 'uint256', indexed: false }, { name: 'protocolFee', type: 'uint256', indexed: false }] },
  { type: 'event', name: 'TaskDisputed',      inputs: [{ name: 'taskId', type: 'uint256', indexed: true }, { name: 'disputer', type: 'address', indexed: true }] },
  { type: 'event', name: 'TaskAborted',       inputs: [{ name: 'taskId', type: 'uint256', indexed: true }] },
  { type: 'event', name: 'DisputeResolved',   inputs: [{ name: 'taskId', type: 'uint256', indexed: true }, { name: 'winner', type: 'address', indexed: true }] },

  // ── Views ────────────────────────────────────────────────────────────
  {
    type: 'function', stateMutability: 'view', name: 'getAgent',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [{ name: '', type: 'tuple', components: [
      { name: 'id',             type: 'uint256' },
      { name: 'name',           type: 'string'  },
      { name: 'capabilities',   type: 'string[]'},
      { name: 'pricePerTask',   type: 'uint256' },
      { name: 'endpoint',       type: 'string'  },
      { name: 'owner',          type: 'address' },
      { name: 'tasksCompleted', type: 'uint256' },
      { name: 'tasksFailed',    type: 'uint256' },
      { name: 'reputation',     type: 'uint256' },
      { name: 'bond',           type: 'uint256' },
      { name: 'bondLocked',     type: 'uint256' },
      { name: 'active',         type: 'bool'    },
    ]}],
  },
  {
    type: 'function', stateMutability: 'view', name: 'getTask',
    inputs: [{ name: 'id', type: 'uint256' }],
    outputs: [{ name: '', type: 'tuple', components: [
      { name: 'id',              type: 'uint256' },
      { name: 'title',           type: 'string'  },
      { name: 'description',     type: 'string'  },
      { name: 'capability',      type: 'string'  },
      { name: 'budget',          type: 'uint256' },
      { name: 'poster',          type: 'address' },
      { name: 'assignedAgentId', type: 'uint256' },
      { name: 'status',          type: 'uint8'   },
      { name: 'agentBond',       type: 'uint256' },
      { name: 'createdAt',       type: 'uint256' },
      { name: 'deadlineTs',      type: 'uint256' },
      { name: 'bondSettled',     type: 'bool'    },
      { name: 'subAgentId',      type: 'uint256' },
      { name: 'subAgentCost',    type: 'uint256' },
      { name: 'completedAt',     type: 'uint256' },
      { name: 'assignedAt',      type: 'uint256' },
    ]}],
  },
  { type: 'function', stateMutability: 'view', name: 'taskCount',        inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { type: 'function', stateMutability: 'view', name: 'agentCount',       inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { type: 'function', stateMutability: 'view', name: 'PROTOCOL_FEE_BPS', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { type: 'function', stateMutability: 'view', name: 'BOND_BPS',         inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { type: 'function', stateMutability: 'view', name: 'feeRecipient',     inputs: [], outputs: [{ name: '', type: 'address' }] },
  { type: 'function', stateMutability: 'view', name: 'agentPendingBond', inputs: [{ name: 'agentId', type: 'uint256' }], outputs: [{ name: '', type: 'uint256' }] },
  { type: 'function', stateMutability: 'view', name: 'getAgentsByCapability', inputs: [{ name: 'capability', type: 'string' }], outputs: [{ name: '', type: 'uint256[]' }] },

  // ── Writes ───────────────────────────────────────────────────────────
  { type: 'function', stateMutability: 'nonpayable', name: 'registerAgent',   inputs: [{ name: 'name', type: 'string' }, { name: 'endpoint', type: 'string' }], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'deregisterAgent', inputs: [], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'postTask',        inputs: [{ name: 'description', type: 'string' }, { name: 'budget', type: 'uint256' }], outputs: [{ name: 'taskId', type: 'uint256' }] },
  { type: 'function', stateMutability: 'nonpayable', name: 'assignTask',      inputs: [{ name: 'taskId', type: 'uint256' }, { name: 'agentAddr', type: 'address' }], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'completeTask',    inputs: [{ name: 'taskId', type: 'uint256' }, { name: 'subAgent', type: 'address' }], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'finalizeTask',    inputs: [{ name: 'taskId', type: 'uint256' }], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'disputeTask',     inputs: [{ name: 'taskId', type: 'uint256' }], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'abortTask',       inputs: [{ name: 'taskId', type: 'uint256' }], outputs: [] },
  { type: 'function', stateMutability: 'nonpayable', name: 'resolveDispute',  inputs: [{ name: 'taskId', type: 'uint256' }, { name: 'favorAgent', type: 'bool' }], outputs: [] },
] as const

export const AGENT_MARKET = {
  address: '0x6e0185f92dde0b2d8793bb286913445a2f27a49a' as `0x${string}`,
  abi: AGENT_MARKET_ABI,
} as const

export const ARC_EXPLORER = 'https://explorer.testnet.arc.io'
export const USDC_ADDRESS  = '0x3600000000000000000000000000000000000000' as `0x${string}`
export const ARC_CHAIN_ID  = 5042002

export function txUrl(hash: string)      { return `${ARC_EXPLORER}/tx/${hash}` }
export function addressUrl(addr: string) { return `${ARC_EXPLORER}/address/${addr}` }
