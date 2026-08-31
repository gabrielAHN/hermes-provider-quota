// Data layer — shells out to the SAME helper scripts the Swift app used
// (~/.local/bin/hermes-desktop-quotas, hermes-local-quotas) via Bun.spawn, plus a
// native scan of local agent sessions for the Local pet.

import { join } from "node:path"
import { homedir } from "node:os"
import { existsSync, readdirSync, statSync } from "node:fs"
import type { QuotaPayload } from "./quota.ts"
import { familyForModel } from "./theme.ts"

const BIN = join(homedir(), ".local", "bin")

interface RunResult {
  ok: boolean
  stdout: Uint8Array
  stderr: string
}

// Login shell so the helper's shebang + PATH resolve, mirroring the Swift runHelper.
async function runHelper(name: string, args: string[] = []): Promise<RunResult> {
  const helper = join(BIN, name)
  try {
    const proc = Bun.spawn(["/bin/bash", "-lc", 'exec "$0" "$@"', helper, ...args], {
      stdout: "pipe",
      stderr: "pipe",
    })
    const [stdout, stderr, exit] = await Promise.all([
      new Response(proc.stdout).arrayBuffer(),
      new Response(proc.stderr).text(),
      proc.exited,
    ])
    return { ok: exit === 0, stdout: new Uint8Array(stdout), stderr }
  } catch (err) {
    return { ok: false, stdout: new Uint8Array(), stderr: String(err) }
  }
}

async function run(cmd: string[]): Promise<string> {
  try {
    const proc = Bun.spawn(cmd, { stdout: "pipe", stderr: "ignore" })
    const [out] = await Promise.all([new Response(proc.stdout).text(), proc.exited])
    return out
  } catch {
    return ""
  }
}

export type SourceKind = "hermes" | "local"

export interface QuotaResult {
  ok: boolean
  payload?: QuotaPayload
  error?: string
}

export async function fetchQuotas(kind: SourceKind): Promise<QuotaResult> {
  const name = kind === "local" ? "hermes-local-quotas" : "hermes-desktop-quotas"
  const res = await runHelper(name)
  if (!res.ok) return { ok: false, error: res.stderr.trim() || "Helper failed" }
  try {
    const payload = JSON.parse(new TextDecoder().decode(res.stdout)) as QuotaPayload
    if (!payload.providers || payload.providers.length === 0) {
      return { ok: false, error: kind === "local" ? "Sign in to your local providers" : "Sign in to Hermes" }
    }
    return { ok: true, payload }
  } catch (err) {
    return { ok: false, error: `Bad quota JSON: ${err}` }
  }
}

// ── Activity (drives the pet) ───────────────────────────────────────────────

export type SessionStatus = "working" | "idle"

export interface SessionMark {
  busy: boolean
  families: string[] // provider families in order, e.g. ["openai-codex", "anthropic"]
  status: SessionStatus
}

export interface Activity {
  busy: boolean
  sessions: SessionMark[]
}

// Hermes pet timing windows (seconds), ported from the Swift app.
const HERMES_ENDED_GRACE = 6
const HERMES_FRESH_WINDOW = 75
const HERMES_ZOMBIE_WINDOW = 900

function toEpoch(v: unknown): number | null {
  if (typeof v === "number") return v > 1e12 ? v / 1000 : v
  if (typeof v === "string") {
    const t = Date.parse(v)
    if (!Number.isNaN(t)) return t / 1000
    const n = Number(v)
    if (!Number.isNaN(n)) return n > 1e12 ? n / 1000 : n
  }
  return null
}

export async function fetchHermesActivity(): Promise<Activity> {
  const res = await runHelper("hermes-desktop-quotas", ["--activity"])
  if (!res.ok) return { busy: false, sessions: [] }
  let data: any
  try {
    data = JSON.parse(new TextDecoder().decode(res.stdout))
  } catch {
    return { busy: false, sessions: [] }
  }
  const now = Date.now() / 1000
  const sessions: SessionMark[] = []
  let busyAny = false
  for (const s of data.sessions ?? []) {
    const active = Boolean(s.is_active)
    const lastActive = toEpoch(s.last_active)
    const ended = toEpoch(s.ended_at)
    let show = false
    let busy = false
    if (active && (lastActive == null || now - lastActive <= HERMES_ZOMBIE_WINDOW)) {
      show = true
      busy = true
    } else if (ended != null && now - ended <= HERMES_ENDED_GRACE) {
      show = true
    } else if (lastActive != null && now - lastActive <= HERMES_FRESH_WINDOW) {
      show = true
    }
    if (!show) continue
    const families: string[] = Array.isArray(s.providers) ? s.providers.filter(Boolean) : []
    if (busy) busyAny = true
    sessions.push({ busy, families, status: busy ? "working" : "idle" })
  }
  return { busy: busyAny, sessions }
}

// ── Local session scan (claude / codex / opencode) ──────────────────────────

const LOCAL_BUSY_WINDOW = 20
const LOCAL_PRESENT_WINDOW = 180
const CODEX_BUSY_WINDOW = 90
const OPENCODE_BUSY_WINDOW = 120

function newestMtime(dir: string, suffix: string, maxDepth: number): number | null {
  let newest: number | null = null
  const walk = (d: string, depth: number) => {
    let entries: string[]
    try {
      entries = readdirSync(d)
    } catch {
      return
    }
    for (const name of entries) {
      const p = join(d, name)
      let st
      try {
        st = statSync(p)
      } catch {
        continue
      }
      if (st.isDirectory()) {
        if (depth < maxDepth) walk(p, depth + 1)
      } else if (name.endsWith(suffix)) {
        const m = st.mtimeMs / 1000
        if (newest == null || m > newest) newest = m
      }
    }
  }
  walk(dir, 0)
  return newest
}

async function scanClaude(): Promise<SessionMark[]> {
  const ps = await run(["/bin/ps", "-axo", "command="])
  const live = ps
    .split("\n")
    .filter((l) => /(^|\/)claude(\s|$)/.test(l) && (l.includes("--session-id") || l.includes("--resume") || l.includes(" -r ")))
    .filter((l) => !/(claude\s+(mcp|config|migrate|update|doctor|install))/.test(l))
  if (live.length === 0) return []
  const newest = newestMtime(join(homedir(), ".claude", "projects"), ".jsonl", 3)
  const now = Date.now() / 1000
  const busy = newest != null && now - newest <= LOCAL_BUSY_WINDOW
  // One mark per live session process.
  return live.map(() => ({ busy, families: ["anthropic"], status: busy ? "working" : "idle" }) as SessionMark)
}

async function scanCodex(): Promise<SessionMark[]> {
  const base = join(homedir(), ".codex", "sessions")
  if (!existsSync(base)) return []
  const newest = newestMtime(base, ".jsonl", 4)
  if (newest == null) return []
  const now = Date.now() / 1000
  const age = now - newest
  if (age > LOCAL_PRESENT_WINDOW) return []
  const busy = age <= CODEX_BUSY_WINDOW
  return [{ busy, families: ["openai-codex"], status: busy ? "working" : "idle" }]
}

async function scanOpencode(): Promise<SessionMark[]> {
  const db = join(homedir(), ".local", "share", "opencode", "opencode.db")
  if (!existsSync(db)) return []
  const out = await run([
    "/usr/bin/sqlite3",
    "-readonly",
    db,
    "SELECT time_updated FROM session WHERE parent_id IS NULL ORDER BY time_updated DESC LIMIT 10",
  ])
  const now = Date.now() / 1000
  const marks: SessionMark[] = []
  for (const line of out.split("\n")) {
    const ms = Number(line.trim())
    if (!ms) continue
    const age = now - ms / 1000
    if (age > LOCAL_PRESENT_WINDOW) continue
    const busy = age <= OPENCODE_BUSY_WINDOW
    marks.push({ busy, families: ["openrouter"], status: busy ? "working" : "idle" })
  }
  return marks
}

export async function fetchLocalActivity(): Promise<Activity> {
  const [claude, codex, opencode] = await Promise.all([scanClaude(), scanCodex(), scanOpencode()])
  const sessions = [...claude, ...codex, ...opencode]
  return { busy: sessions.some((s) => s.busy), sessions }
}

// ── Pets ────────────────────────────────────────────────────────────────────

export interface PetInfo {
  id: string
  displayName: string
}

// Ids the picker hides (matching PetCatalog.isHidden).
function petHidden(id: string): boolean {
  return id.startsWith("lulu") || id.endsWith("cat")
}

export async function fetchPetsList(): Promise<PetInfo[]> {
  // Union of what's installed on disk and what the gateway serves, deduped.
  const out: PetInfo[] = listLocalPets()
  const seen = new Set(out.map((p) => p.id))
  const res = await runHelper("hermes-desktop-quotas", ["/api/plugins/provider-quota/pets"])
  if (res.ok) {
    try {
      const data = JSON.parse(new TextDecoder().decode(res.stdout))
      for (const p of data.pets ?? []) {
        const id = String(p.id)
        if (petHidden(id) || seen.has(id)) continue
        seen.add(id)
        out.push({ id, displayName: String(p.displayName || id) })
      }
    } catch {
      // ignore a bad gateway response; the on-disk list stands
    }
  }
  return out
}

// Fallback: scan the on-disk pet dirs directly (no gateway needed).
function listLocalPets(): PetInfo[] {
  const out: PetInfo[] = []
  for (const dir of [join(homedir(), ".hermes", "pets"), join(homedir(), ".hermes", "pets-cache")]) {
    if (!existsSync(dir)) continue
    for (const id of readdirSync(dir)) {
      if (id.startsWith(".") || petHidden(id)) continue
      const d = join(dir, id)
      try {
        if (!statSync(d).isDirectory()) continue
      } catch {
        continue
      }
      if (existsSync(join(d, "spritesheet.webp")) || existsSync(join(d, "spritesheet.png"))) {
        if (!out.some((p) => p.id === id)) out.push({ id, displayName: id })
      }
    }
  }
  return out
}

// Resolve a pet's spritesheet to a local file path. Prefers the on-disk asset;
// otherwise downloads it from the gateway via the helper. Returns null if absent.
export async function spritesheetPath(id: string): Promise<string | null> {
  for (const dir of [join(homedir(), ".hermes", "pets"), join(homedir(), ".hermes", "pets-cache")]) {
    for (const ext of ["webp", "png"]) {
      const p = join(dir, id, `spritesheet.${ext}`)
      if (existsSync(p)) return p
    }
  }
  const out = join(homedir(), ".hermes", "pets-cache", `${id}.download.webp`)
  const res = await runHelper("hermes-desktop-quotas", [
    `/api/plugins/provider-quota/pets/${id}/spritesheet`,
    out,
  ])
  return res.ok && existsSync(out) ? out : null
}
