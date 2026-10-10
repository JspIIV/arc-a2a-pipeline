/**
 * PipelineView — A2A task pipeline visualiser
 * Shows the live flow: Poster → Arc Escrow → Primary Agent → Sub-Agent → Payout
 */
import { useReadContract } from 'wagmi'
import { ArrowRight, User, Cpu, ShieldCheck, Coins, Zap } from 'lucide-react'
import { AGENT_MARKET, addressUrl } from '../contracts'
import { ARC_CHAIN_ID } from '../config'
import { formatUsdc, shortAddr, TASK_STATUS } from '../utils'

// ── Struct types ──────────────────────────────────────────────────────
interface AgentStruct {
  id: bigint; name: string; capabilities: string[];
  pricePerTask: bigint; endpoint: string; owner: `0x${string}`;
  tasksCompleted: bigint; tasksFailed: bigint; reputation: bigint;
  bond: bigint; bondLocked: bigint; active: boolean;
}
interface TaskStruct {
  id: bigint; title: string; description: string; capability: string;
  budget: bigint; poster: `0x${string}`; assignedAgentId: bigint;
  status: number; agentBond: bigint; createdAt: bigint; deadlineTs: bigint;
  bondSettled: boolean; subAgentId: bigint; subAgentCost: bigint;
  completedAt: bigint; assignedAt: bigint;
}

// ── Sub-components ────────────────────────────────────────────────────
interface StepProps {
  icon: React.FC<{ className?: string; style?: React.CSSProperties }>
  label: string; sublabel?: string; active?: boolean; done?: boolean; accent?: string
}

function Step({ icon: Icon, label, sublabel, active, done, accent }: StepProps) {
  const iconColor   = done ? 'var(--success)' : active ? (accent ?? 'var(--accent)') : 'var(--subtle)'
  const borderColor = done ? 'rgba(141,216,159,0.35)' : active ? 'rgba(172,198,233,0.4)' : 'rgba(255,255,255,0.08)'
  return (
    <div className="flex flex-col items-center gap-2 min-w-0">
      <div
        className="w-11 h-11 rounded-2xl flex items-center justify-center transition-all"
        style={{
          background: done ? 'rgba(141,216,159,0.12)' : active ? 'rgba(172,198,233,0.12)' : 'rgba(255,255,255,0.04)',
          border: `1px solid ${borderColor}`,
        }}
      >
        <Icon className="w-5 h-5" style={{ color: iconColor }} />
      </div>
      <div className="text-center">
        <p className="text-[11px] font-semibold" style={{ color: done || active ? 'var(--ink)' : 'var(--subtle)' }}>
          {label}
        </p>
        {sublabel && (
          <p className="text-[10px] mono truncate max-w-[80px]" style={{ color: 'var(--subtle)' }}>
            {sublabel}
          </p>
        )}
      </div>
    </div>
  )
}

function Connector({ active }: { active: boolean }) {
  return (
    <div className="flex items-center mx-1 mb-5">
      <div
        className="h-px transition-all"
        style={{
          background: active
            ? 'linear-gradient(90deg,rgba(172,198,233,0.5),rgba(172,198,233,0.15))'
            : 'rgba(255,255,255,0.06)',
          width: 28, minWidth: 28,
        }}
      />
      <ArrowRight className="w-3 h-3 shrink-0" style={{ color: active ? 'var(--accent)' : 'rgba(255,255,255,0.12)' }} />
    </div>
  )
}

function Row({ label, value, muted, accent }: { label: string; value: string; muted?: boolean; accent?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span style={{ color: 'var(--subtle)' }}>{label}</span>
      <span className="font-semibold tabular-nums" style={{ color: accent ? 'var(--success)' : muted ? 'var(--subtle)' : 'var(--ink)' }}>
        {value}
      </span>
    </div>
  )
}

// ── Task card ─────────────────────────────────────────────────────────
function TaskPipeline({ id }: { id: bigint }) {
  const { data: rawTask } = useReadContract({
    ...AGENT_MARKET,
    functionName: 'getTask',
    args: [id],
    chainId: ARC_CHAIN_ID,
  })
  const task = rawTask as TaskStruct | undefined

  const { data: rawAgent } = useReadContract({
    ...AGENT_MARKET,
    functionName: 'getAgent',
    args: task?.assignedAgentId ? [task.assignedAgentId] : undefined,
    chainId: ARC_CHAIN_ID,
    query: { enabled: !!task && (task.assignedAgentId ?? 0n) > 0n },
  })
  const { data: rawSub } = useReadContract({
    ...AGENT_MARKET,
    functionName: 'getAgent',
    args: task?.subAgentId ? [task.subAgentId] : undefined,
    chainId: ARC_CHAIN_ID,
    query: { enabled: !!task && (task.subAgentId ?? 0n) > 0n },
  })
  const mainAgent = rawAgent as AgentStruct | undefined
  const subAgent  = rawSub   as AgentStruct | undefined

  if (!task) {
    return <div className="h-28 rounded-2xl animate-pulse" style={{ background: 'rgba(255,255,255,0.04)' }} />
  }

  const { title, budget, poster, assignedAgentId, subAgentId, subAgentCost, status: statusNum } = task
  const status      = TASK_STATUS[statusNum] ?? { label: 'Unknown', color: 'var(--subtle)' }
  const isOpen      = statusNum === 0
  const assigned    = statusNum >= 1
  const completed   = statusNum >= 2
  const paid        = statusNum === 5 || statusNum === 6   // Expired or Cancelled treated same
  const hasSubAgent = (subAgentId ?? 0n) > 0n

  const protocolFee   = (budget * 100n) / 10000n
  const primaryPayout = hasSubAgent
    ? budget - (subAgentCost ?? 0n) - protocolFee
    : budget - protocolFee

  return (
    <div className="rounded-2xl p-4 flex flex-col gap-3" style={{ background: 'var(--surface)', border: '1px solid var(--border)' }}>
      {/* Header */}
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <span className="pill shrink-0" style={{ background: `${status.color}20`, color: status.color, border: `1px solid ${status.color}40` }}>
            {status.label}
          </span>
          <span className="text-sm font-medium truncate" style={{ color: 'var(--ink)' }}>
            {title}
          </span>
        </div>
        <a
          href={addressUrl(AGENT_MARKET.address)}
          target="_blank" rel="noreferrer"
          className="text-sm font-semibold tabular-nums shrink-0 hover:underline"
          style={{ color: 'var(--accent)' }}
        >
          {formatUsdc(budget)} USDC
        </a>
      </div>

      {/* Pipeline steps */}
      <div className="flex items-start overflow-x-auto pb-1 gap-0">
        <Step icon={User} label="Poster" sublabel={shortAddr(poster)} active done={assigned} />
        <Connector active={true} />
        <Step icon={ShieldCheck} label="Arc Escrow" sublabel={`${formatUsdc(budget)} USDC`} active={isOpen} done={completed} />
        <Connector active={assigned} />
        <Step
          icon={Cpu}
          label={mainAgent?.name ?? 'Agent'}
          sublabel={assigned ? `#${assignedAgentId}` : 'Pending'}
          active={assigned && !completed}
          done={completed}
        />
        {hasSubAgent && (
          <>
            <Connector active={assigned} />
            <Step
              icon={Zap}
              label={subAgent?.name ?? 'Sub-agent'}
              sublabel={`−${formatUsdc(subAgentCost ?? 0n)} USDC`}
              active={assigned && !completed}
              done={completed}
            />
          </>
        )}
        <Connector active={completed} />
        <Step
          icon={Coins}
          label="Payout"
          sublabel={completed ? `${formatUsdc(primaryPayout)} USDC` : '—'}
          active={completed && !paid}
          done={paid}
          accent="var(--success)"
        />
      </div>

      {/* Fee breakdown */}
      {completed && (
        <div className="grid gap-1 px-3 py-2 rounded-xl text-xs" style={{ background: 'rgba(172,198,233,0.05)', border: '1px solid rgba(172,198,233,0.12)' }}>
          <Row label="Total escrow"     value={`${formatUsdc(budget)} USDC`} />
          {hasSubAgent && <Row label="Sub-agent fee" value={`−${formatUsdc(subAgentCost ?? 0n)} USDC`} muted />}
          <Row label="Protocol fee (1%)" value={`−${formatUsdc(protocolFee)} USDC`} muted />
          <div className="border-t mt-1 pt-1" style={{ borderColor: 'rgba(172,198,233,0.15)' }}>
            <Row label="Agent payout" value={`${formatUsdc(primaryPayout)} USDC`} accent />
          </div>
        </div>
      )}
    </div>
  )
}

// ── Public export ─────────────────────────────────────────────────────
export default function PipelineView() {
  const { data: taskCount } = useReadContract({
    ...AGENT_MARKET,
    functionName: 'taskCount',
    chainId: ARC_CHAIN_ID,
  })

  const count = Number(taskCount ?? 0n)
  const ids   = Array.from({ length: Math.min(count, 20) }, (_, i) => BigInt(count - i))

  return (
    <div className="space-y-4">
      <div>
        <h2 className="display text-2xl font-bold" style={{ color: 'var(--ink)' }}>
          A2A Pipeline
        </h2>
        <p className="text-sm mt-0.5" style={{ color: 'var(--subtle)' }}>
          Live agent-to-agent payment flow on Arc · {count} task{count !== 1 ? 's' : ''}
        </p>
      </div>

      {count === 0 ? (
        <div
          className="flex flex-col items-center justify-center py-16 rounded-3xl gap-3"
          style={{ background: 'var(--surface)', border: '1px dashed var(--border)' }}
        >
          <Zap className="w-8 h-8" style={{ color: 'var(--subtle)' }} />
          <p className="display text-lg font-semibold" style={{ color: 'var(--ink)' }}>No pipelines yet</p>
          <p className="text-sm max-w-xs text-center text-pretty" style={{ color: 'var(--subtle)' }}>
            Post a task on the Task Board to see the A2A payment flow visualised here.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {ids.map(id => <TaskPipeline key={id.toString()} id={id} />)}
        </div>
      )}
    </div>
  )
}
