// Window UI: header, sources row, per-source section, provider rows, window
// rows, action bar. Presentational — state + callbacks come from app.tsx.

import { Icon, type IconName } from "./icons.tsx"
import { C, HERMES, FONT, MONO, providerHex, providerLabel, providerIcon, barColor } from "./theme.ts"
import {
  type QuotaProvider,
  type QuotaWindow,
  accountCreditsWindow,
  collapsedRemainingPercent,
  formatAmount,
  limitReached,
  providerIsExhausted,
  providerSummary,
  relativeReset,
} from "./quota.ts"
import type { SourceKind } from "./settings.ts"

const WIDTH = 380

export function Bar({ pct, color, width = 104 }: { pct: number; color: string; width?: number }) {
  const w = Math.max(0, Math.min(100, pct))
  return (
    <div style={{ width, height: 6, borderRadius: 3, backgroundColor: C.track }}>
      <div style={{ width: `${w}%`, height: "100%", borderRadius: 3, backgroundColor: color }} />
    </div>
  )
}

export function Header({ summary, ok, updated }: { summary: string; ok: boolean; updated: string }) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "row",
        alignItems: "flex-start",
        justifyContent: "space-between",
        paddingLeft: 16,
        paddingRight: 16,
        paddingTop: 40,
        paddingBottom: 10,
      }}
    >
      <div style={{ gap: 3 }}>
        <text style={{ color: C.text, fontFamily: FONT, fontSize: 15, fontWeight: 650 }}>Provider Quotas</text>
        <text style={{ color: ok ? HERMES.green : HERMES.red, fontFamily: FONT, fontSize: 11 }}>{summary}</text>
        <text style={{ color: C.tertiary, fontFamily: FONT, fontSize: 11 }}>{updated}</text>
      </div>
      <Icon name="gauge" size={18} color={HERMES.blue} />
    </div>
  )
}

function Chip({
  label,
  on,
  color,
  onClick,
}: {
  label: string
  on: boolean
  color: string
  onClick: () => void
}) {
  return (
    <div
      onClick={onClick}
      style={{
        paddingLeft: 10,
        paddingRight: 10,
        height: 22,
        borderRadius: 7,
        display: "flex",
        alignItems: "center",
        opacity: on ? 1 : 0.55,
        backgroundColor: on ? "#FFFFFF14" : "#FFFFFF08",
        borderWidth: 1,
        borderColor: on ? color : C.border,
        hover: { backgroundColor: C.overlayStrong },
      }}
    >
      <text style={{ color: on ? color : C.secondary, fontFamily: FONT, fontSize: 11, fontWeight: 600 }}>{label}</text>
    </div>
  )
}

export function SourcesRow({
  hermesOn,
  localOn,
  hermesColor,
  localColor,
  onToggle,
}: {
  hermesOn: boolean
  localOn: boolean
  hermesColor: string
  localColor: string
  onToggle: (kind: SourceKind) => void
}) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "row",
        alignItems: "center",
        gap: 8,
        paddingLeft: 16,
        paddingRight: 16,
        paddingTop: 6,
        paddingBottom: 8,
      }}
    >
      <Icon name="network" size={15} color={hermesOn || localOn ? HERMES.blue : C.tertiary} />
      <text style={{ color: C.secondary, fontFamily: FONT, fontSize: 12, fontWeight: 600, flexGrow: 1 }}>Sources</text>
      <Chip label="Hermes" on={hermesOn} color={hermesColor} onClick={() => onToggle("hermes")} />
      <Chip label="Local" on={localOn} color={localColor} onClick={() => onToggle("local")} />
    </div>
  )
}

function IconBtn({ name, color, onClick }: { name: IconName; color: string; onClick?: () => void }) {
  return (
    <div
      onClick={onClick}
      style={{
        width: 24,
        height: 24,
        borderRadius: 6,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        hover: { backgroundColor: C.overlay },
      }}
    >
      <Icon name={name} size={14} color={color} />
    </div>
  )
}

export function SourceHeader({
  kind,
  connected,
  refreshing,
  petOn,
  hasPets,
  multiplePets,
  onRefresh,
  onTogglePet,
  onCyclePet,
  onLogin,
  onSetup,
}: {
  kind: SourceKind
  connected: boolean
  refreshing: boolean
  petOn: boolean
  hasPets: boolean
  multiplePets: boolean
  onRefresh: () => void
  onTogglePet: () => void
  onCyclePet: () => void
  onLogin: () => void
  onSetup: () => void
}) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "row",
        alignItems: "center",
        gap: 6,
        paddingLeft: 16,
        paddingRight: 12,
        paddingTop: 8,
        paddingBottom: 2,
      }}
    >
      <div style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: connected ? HERMES.green : HERMES.red }} />
      <text style={{ color: C.secondary, fontFamily: FONT, fontSize: 10, fontWeight: 600, flexGrow: 1 }}>
        {(kind === "hermes" ? "Hermes" : "Local").toUpperCase()}
      </text>
      {hasPets && <IconBtn name="pawPrint" color={petOn ? HERMES.blue : C.tertiary} onClick={onTogglePet} />}
      {hasPets && petOn && multiplePets && <IconBtn name="rotateCw" color={C.tertiary} onClick={onCyclePet} />}
      {kind === "hermes" && (
        <IconBtn name={connected ? "logOut" : "logIn"} color={connected ? HERMES.red : HERMES.green} onClick={onLogin} />
      )}
      {kind === "hermes" && <IconBtn name="settings" color={HERMES.blue} onClick={onSetup} />}
      <IconBtn name="refreshCw" color={refreshing ? C.faint : HERMES.blue} onClick={onRefresh} />
    </div>
  )
}

function StatusDot({ color, bad }: { color: string; bad: boolean }) {
  return (
    <div
      style={{
        width: 11,
        height: 11,
        borderRadius: 6,
        backgroundColor: bad ? "#00000000" : color,
        borderWidth: bad ? 2 : 0,
        borderColor: bad ? HERMES.red : "#00000000",
      }}
    />
  )
}

export function WindowRow({ slug, window: w }: { slug: string; window: QuotaWindow }) {
  const reached = limitReached(w)
  let value = "Unavailable"
  if (w.remaining_amount != null) value = `${formatAmount(w.remaining_amount, w.currency)} available`
  else if (reached) value = "Limit reached"
  else if (w.remaining_percent != null) value = `${Math.round(w.remaining_percent)}% left`
  const low = w.remaining_percent != null && w.remaining_percent <= 15
  const valueColor = reached ? HERMES.red : low ? HERMES.orange : C.secondary
  const reset = relativeReset(w.resets_at)
  const subtitle = w.detail || (reset ? `Resets ${reset}` : w.remaining_amount != null ? "Available to spend" : "No reset time")
  return (
    <div style={{ paddingLeft: 28, paddingRight: 16, paddingTop: 6, paddingBottom: 6, gap: 5 }}>
      <div style={{ display: "flex", flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
        <text style={{ color: C.secondary, fontFamily: FONT, fontSize: 12, fontWeight: 500 }}>{w.label}</text>
        <text style={{ color: valueColor, fontFamily: MONO, fontSize: 12, fontWeight: 600 }}>{value}</text>
      </div>
      {w.remaining_percent != null && <Bar pct={w.remaining_percent} color={barColor(slug, reached)} width={336} />}
      <text style={{ color: C.tertiary, fontFamily: FONT, fontSize: 10 }}>{subtitle}</text>
    </div>
  )
}

export function ProviderRow({
  kind,
  provider,
  connected,
  expanded,
  dotHidden,
  onToggleExpand,
  onToggleDot,
}: {
  kind: SourceKind
  provider: QuotaProvider
  connected: boolean
  expanded: boolean
  dotHidden: boolean
  onToggleExpand: () => void
  onToggleDot: () => void
}) {
  const color = providerHex(provider.provider)
  const exhausted = providerIsExhausted(provider)
  const bad = !connected || exhausted
  const pct = connected && provider.status === "ok" ? collapsedRemainingPercent(provider) : null
  const credits = accountCreditsWindow(provider)
  const showBar = pct != null && !(credits && credits.remaining_amount != null)
  return (
    <div style={{ paddingBottom: 2 }}>
      <div style={{ display: "flex", flexDirection: "row", alignItems: "center", paddingLeft: 12, paddingRight: 12, height: 46 }}>
        {/* Left: click to expand */}
        <div
          onClick={onToggleExpand}
          style={{ display: "flex", flexDirection: "row", alignItems: "center", gap: 8, flexGrow: 1, height: "100%", hover: { backgroundColor: C.overlay } }}
        >
          <Icon name={expanded ? "chevronDown" : "chevronRight"} size={13} color={C.tertiary} />
          <Icon name={providerIcon(provider.provider) as IconName} size={15} color={color} />
          <div style={{ gap: 3, flexGrow: 1 }}>
            <div style={{ display: "flex", flexDirection: "row", alignItems: "center", gap: 6 }}>
              <text style={{ color, fontFamily: FONT, fontSize: 13, fontWeight: 600 }}>{providerLabel(provider.provider)}</text>
              {provider.plan ? (
                <text style={{ color: C.tertiary, fontFamily: FONT, fontSize: 9, fontWeight: 600 }}>{provider.plan.toUpperCase()}</text>
              ) : null}
            </div>
            <text style={{ color: C.tertiary, fontFamily: FONT, fontSize: 11 }}>{providerSummary(provider, connected)}</text>
          </div>
        </div>
        {/* Right: bar + status dot + eye toggle */}
        <div style={{ display: "flex", flexDirection: "row", alignItems: "center", gap: 10 }}>
          {showBar && <Bar pct={pct!} color={barColor(provider.provider, exhausted)} />}
          <StatusDot color={color} bad={bad} />
          <IconBtn name={dotHidden ? "eyeOff" : "eye"} color={dotHidden ? C.tertiary : HERMES.blue} onClick={onToggleDot} />
        </div>
      </div>
      {expanded && connected && (
        <div style={{ paddingBottom: 6 }}>
          {provider.windows.length === 0 ? (
            <text style={{ color: HERMES.orange, fontFamily: FONT, fontSize: 11, paddingLeft: 28, paddingBottom: 6 }}>
              {provider.message || "No windows reported"}
            </text>
          ) : (
            provider.windows.map((w, i) => <WindowRow key={i} slug={provider.provider} window={w} />)
          )}
          {(provider.details ?? []).map((d, i) => (
            <text key={`d${i}`} style={{ color: C.tertiary, fontFamily: FONT, fontSize: 10, paddingLeft: 28, paddingBottom: 3 }}>
              {d}
            </text>
          ))}
        </div>
      )}
    </div>
  )
}

export function MessageRow({ text, color = C.tertiary }: { text: string; color?: string }) {
  return (
    <text style={{ color, fontFamily: FONT, fontSize: 12, paddingLeft: 16, paddingRight: 16, paddingTop: 8, paddingBottom: 8 }}>
      {text}
    </text>
  )
}

export function ActionBar({ onCheckUpdates, onClose }: { onCheckUpdates: () => void; onClose: () => void }) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "row",
        alignItems: "center",
        justifyContent: "flex-end",
        gap: 4,
        paddingLeft: 16,
        paddingRight: 12,
        paddingTop: 6,
        paddingBottom: 12,
      }}
    >
      <IconBtn name="rotateCw" color={HERMES.blue} onClick={onCheckUpdates} />
      <IconBtn name="x" color={HERMES.red} onClick={onClose} />
    </div>
  )
}

export { WIDTH }
