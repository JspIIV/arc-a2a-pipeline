import artifact from '../contracts/out/AgentMarket.sol/AgentMarket.json'

export const AGENT_MARKET = {
  address: '0x6e0185f92dde0b2d8793bb286913445a2f27a49a' as `0x${string}`,
  abi: artifact.abi,
} as const

export const ARC_EXPLORER = 'https://explorer.testnet.arc.io'

export function txUrl(hash: string)     { return `${ARC_EXPLORER}/tx/${hash}` }
export function addressUrl(addr: string){ return `${ARC_EXPLORER}/address/${addr}` }
