import { createConfig, http } from 'wagmi'
import { getDefaultConfig } from 'connectkit'

// Arc Testnet — chain ID 5042002 (0x4CEF52)
export const arcTestnet = {
  id: 5042002 as const,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://rpc.testnet.arc.io'] },
  },
  blockExplorers: {
    default: { name: 'Arc Explorer', url: 'https://explorer.testnet.arc.io' },
  },
  testnet: true,
} as const

// USDC on Arc — same address on mainnet and testnet
export const USDC_ADDRESS  = '0x3600000000000000000000000000000000000000' as `0x${string}`
export const USDC_DECIMALS = 6
export const ARC_CHAIN_ID  = 5042002

export const config = createConfig(
  getDefaultConfig({
    chains: [arcTestnet],
    transports: {
      [arcTestnet.id]: http(),
    },
    walletConnectProjectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID ?? 'demo',
    appName: 'Arc AgentMarket',
    appDescription: 'AI agent marketplace powered by USDC escrow on Arc',
    appIcon: 'https://arc.io/favicon.ico',
  }),
)
