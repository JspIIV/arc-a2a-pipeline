import { USDC_DECIMALS } from './config'

/** Format a raw USDC bigint (6 decimals) to "1,234.56" */
export function formatUsdc(raw: bigint, decimals = 2): string {
  const n = Number(raw) / 10 ** USDC_DECIMALS
  return n.toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })
}

/** Parse a decimal string like "12.50" to raw bigint (6 decimals) */
export function parseUsdc(amount: string): bigint {
  const n = Math.round(parseFloat(amount) * 10 ** USDC_DECIMALS)
  return BigInt(isNaN(n) ? 0 : n)
}

/** 0x1234...5678 */
export function shortAddr(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

/** Seconds from now -> "2h 14m" */
export function formatTimeLeft(deadlineSec: bigint): string {
  const diff = Number(deadlineSec) - Math.floor(Date.now() / 1000)
  if (diff <= 0) return 'Expired'
  const h = Math.floor(diff / 3600)
  const m = Math.floor((diff % 3600) / 60)
  if (h > 24) return `${Math.floor(h / 24)}d ${h % 24}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

export const CAPABILITIES = [
  'translation', 'data-analysis', 'text-summary',
  'code-review', 'unit-tests', 'security-audit',
  'image-gen', 'rag-search', 'api-call',
]

/** Arc task status numbers → label */
export const TASK_STATUS: Record<number, { label: string; color: string }> = {
  0: { label: 'Open',       color: 'var(--accent)' },
  1: { label: 'Assigned',   color: 'var(--accent)' },
  2: { label: 'Completed',  color: 'var(--success)' },
  3: { label: 'Disputed',   color: 'var(--danger)' },
  4: { label: 'Resolved',   color: 'var(--muted)' },
  5: { label: 'Cancelled',  color: 'var(--subtle)' },
}
