import { useReadContract } from 'wagmi'
import { AGENT_MARKET } from '../contracts'
import { ARC_CHAIN_ID } from '../config'

// ── Read hooks — A2A pipeline ────────────────────────────────────────

export function useTaskCount() {
  return useReadContract({
    ...AGENT_MARKET,
    functionName: 'taskCount',
    chainId: ARC_CHAIN_ID,
  })
}

export function useTask(id?: bigint) {
  return useReadContract({
    ...AGENT_MARKET,
    functionName: 'getTask',
    args: id !== undefined ? [id] : undefined,
    chainId: ARC_CHAIN_ID,
    query: { enabled: id !== undefined },
  })
}

export function useAgent(id?: bigint) {
  return useReadContract({
    ...AGENT_MARKET,
    functionName: 'getAgent',
    args: id !== undefined ? [id] : undefined,
    chainId: ARC_CHAIN_ID,
    query: { enabled: id !== undefined },
  })
}

export function useAgentCount() {
  return useReadContract({
    ...AGENT_MARKET,
    functionName: 'agentCount',
    chainId: ARC_CHAIN_ID,
  })
}

export function useProtocolFeeBps() {
  return useReadContract({
    ...AGENT_MARKET,
    functionName: 'PROTOCOL_FEE_BPS',
    chainId: ARC_CHAIN_ID,
  })
}
