// Quota data types + the collapsed/expanded window logic, ported from the Swift
// app so the numbers match exactly.

export interface QuotaWindow {
  label: string
  remaining_percent?: number | null
  remaining_amount?: number | null
  currency?: string | null
  resets_at?: string | null
  detail?: string | null
  warning?: boolean
}

export interface QuotaProvider {
  provider: string
  label: string
  status: string // "ok" | "unavailable" | "error" | a transient status
  plan?: string | null
  windows: QuotaWindow[]
  details?: string[]
  message?: string | null
}

export interface QuotaPayload {
  generated_at?: string
  broker?: string
  providers: QuotaProvider[]
}

// A window is "used up" at <=5% remaining or a spent-out credit balance.
const LIMIT_REACHED_REMAINING_PERCENT = 5.0

export function limitReached(w: QuotaWindow): boolean {
  if (w.remaining_percent != null && w.remaining_percent <= LIMIT_REACHED_REMAINING_PERCENT) return true
  if (w.remaining_amount != null && w.remaining_amount <= 0) return true
  return false
}

export function providerIsExhausted(p: QuotaProvider): boolean {
  return p.status === "ok" && p.windows.some(limitReached)
}

export function providerMinimum(p: QuotaProvider): number | null {
  const pcts = p.windows.map((w) => w.remaining_percent).filter((v): v is number => v != null)
  return pcts.length ? Math.min(...pcts) : null
}

function parseDate(iso?: string | null): number | null {
  if (!iso) return null
  const t = Date.parse(iso)
  return Number.isNaN(t) ? null : t
}

// The "current session" window — the short (~5h) window whose remaining % the
// COLLAPSED provider row shows. Identify by a "session" label (Codex "Session",
// Claude "Current session"), else the soonest-resetting window, else the first.
export function sessionWindow(p: QuotaProvider): QuotaWindow | null {
  const named = p.windows.find((w) => w.label.toLowerCase().includes("session"))
  if (named) return named
  const dated = p.windows
    .map((w) => ({ w, t: parseDate(w.resets_at) }))
    .filter((x): x is { w: QuotaWindow; t: number } => x.t != null)
  if (dated.length) return dated.reduce((a, b) => (b.t < a.t ? b : a)).w
  return p.windows[0] ?? null
}

export function sessionRemainingPercent(p: QuotaProvider): number | null {
  return sessionWindow(p)?.remaining_percent ?? null
}

export function collapsedRemainingPercent(p: QuotaProvider): number | null {
  const reached = p.windows.filter(limitReached).map((w) => w.remaining_percent).filter((v): v is number => v != null)
  if (reached.length) return Math.min(...reached)
  const session = sessionRemainingPercent(p)
  if (session != null) return session
  return providerMinimum(p)
}

// The "Account credits" window carries a $ balance instead of a %.
export function accountCreditsWindow(p: QuotaProvider): QuotaWindow | null {
  return p.windows.find((w) => w.label === "Account credits") ?? null
}

export function formatAmount(amount: number, currency?: string | null): string {
  try {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: currency || "USD",
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(amount)
  } catch {
    return `$${amount.toFixed(2)}`
  }
}

// "in 3h" / "in 2d 4h" / "now" — relative to now.
export function relativeReset(iso?: string | null): string | null {
  const t = parseDate(iso)
  if (t == null) return null
  const secs = Math.round((t - Date.now()) / 1000)
  if (secs <= 0) return "now"
  const d = Math.floor(secs / 86400)
  const h = Math.floor((secs % 86400) / 3600)
  const m = Math.floor((secs % 3600) / 60)
  if (d > 0) return h > 0 ? `in ${d}d ${h}h` : `in ${d}d`
  if (h > 0) return m > 0 ? `in ${h}h ${m}m` : `in ${h}h`
  return `in ${Math.max(1, m)}m`
}

export function relativeAge(epochSeconds: number): string {
  const secs = Math.max(0, Math.round(Date.now() / 1000 - epochSeconds))
  if (secs < 60) return "just now"
  const m = Math.floor(secs / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

// The brief line under a provider label in the collapsed row.
export function providerSummary(p: QuotaProvider, connected: boolean): string {
  if (!connected) return "Disconnected"
  if (p.status !== "ok") {
    if (p.message) return p.message
    return p.status.charAt(0).toUpperCase() + p.status.slice(1)
  }
  const reached = p.windows.filter(limitReached)
  if (reached.length) {
    const labels = reached.map((w) => w.label).join(", ")
    return `${labels} limit${reached.length > 1 ? "s" : ""} reached`
  }
  const credits = accountCreditsWindow(p)
  if (credits && credits.remaining_amount != null) {
    return `${formatAmount(credits.remaining_amount, credits.currency)} available`
  }
  const session = sessionWindow(p)
  if (session && session.remaining_percent != null) {
    const pct = Math.round(session.remaining_percent)
    const reset = relativeReset(session.resets_at)
    return reset ? `${pct}% left · resets ${reset}` : `${pct}% left`
  }
  return "OK"
}
