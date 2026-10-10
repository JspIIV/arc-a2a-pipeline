import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { Zap } from 'lucide-react'
import WalletCard   from './components/WalletCard'
import PipelineView from './components/PipelineView'

export default function App() {
  const { isConnected } = useAccount()

  return (
    <div className="min-h-dvh flex flex-col">

      {/* ── Navbar ─────────────────────────────────────────────── */}
      <header
        className="sticky top-0 z-40 border-b"
        style={{
          borderColor: 'var(--border)',
          background: 'rgba(13,27,47,0.92)',
          backdropFilter: 'blur(20px)',
          WebkitBackdropFilter: 'blur(20px)',
        }}
      >
        <div className="max-w-4xl mx-auto px-4 h-14 flex items-center justify-between gap-4">

          {/* Brand */}
          <div className="flex items-center gap-2.5">
            <div
              className="w-8 h-8 rounded-xl flex items-center justify-center"
              style={{
                background: 'linear-gradient(135deg, rgba(18,45,69,0.9) 0%, rgba(16,97,166,0.35) 100%)',
                border: '1px solid rgba(172,198,233,0.3)',
              }}
            >
              <Zap className="w-4 h-4" style={{ color: 'var(--accent)' }} />
            </div>
            <div>
              <p className="display font-semibold text-sm leading-tight" style={{ color: 'var(--ink)' }}>
                Arc A2A
              </p>
              <p className="text-[10px] uppercase font-semibold tracking-widest" style={{ color: 'var(--accent)', letterSpacing: '0.1em' }}>
                Agent Pipeline
              </p>
            </div>
          </div>

          {/* Right */}
          <div className="flex items-center gap-3">
            <span
              className="hidden sm:flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-semibold"
              style={{
                background: 'rgba(172,198,233,0.08)',
                border: '1px solid rgba(172,198,233,0.22)',
                color: 'var(--accent)',
                letterSpacing: '0.06em',
                textTransform: 'uppercase',
              }}
            >
              <span className="w-1.5 h-1.5 rounded-full" style={{ background: 'var(--success)' }} />
              Arc Testnet
            </span>
            <ConnectKitButton />
          </div>
        </div>
      </header>

      {/* ── Body ───────────────────────────────────────────────── */}
      <div className="max-w-4xl mx-auto w-full px-4 py-8 flex-1 flex flex-col gap-6">
        {isConnected && <WalletCard />}
        <PipelineView />
      </div>

      {/* ── Footer ─────────────────────────────────────────────── */}
      <footer className="max-w-4xl mx-auto w-full px-4 pb-6">
        <p className="text-center text-[11px]" style={{ color: 'var(--subtle)' }}>
          Arc A2A · USDC escrow &amp; agent-to-agent payments on Arc Testnet ·{' '}
          <a
            href="https://explorer.testnet.arc.io/address/0x6e0185f92dde0b2d8793bb286913445a2f27a49a"
            target="_blank" rel="noreferrer"
            className="hover:underline"
            style={{ color: 'var(--accent)' }}
          >
            contract
          </a>
        </p>
      </footer>
    </div>
  )
}
