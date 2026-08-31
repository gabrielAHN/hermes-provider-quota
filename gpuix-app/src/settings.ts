// Persistence — a single JSON file replacing the Swift app's UserDefaults.
// ~/Library/Application Support/ProviderQuotas/settings.json

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { homedir } from "node:os"

const DIR = join(homedir(), "Library", "Application Support", "ProviderQuotas")
const FILE = join(DIR, "settings.json")

type Store = Record<string, unknown>

let store: Store = load()

function load(): Store {
  try {
    if (existsSync(FILE)) return JSON.parse(readFileSync(FILE, "utf8")) as Store
  } catch {
    // fall through to empty store on a corrupt file
  }
  return {}
}

function persist(): void {
  try {
    mkdirSync(dirname(FILE), { recursive: true })
    writeFileSync(FILE, JSON.stringify(store, null, 2))
  } catch {
    // best-effort; a read-only home shouldn't crash the UI
  }
}

export function getString(key: string): string | undefined {
  const v = store[key]
  return typeof v === "string" ? v : undefined
}

export function getBool(key: string, fallback: boolean): boolean {
  const v = store[key]
  return typeof v === "boolean" ? v : fallback
}

export function getNumber(key: string, fallback: number): number {
  const v = store[key]
  return typeof v === "number" ? v : fallback
}

export function set(key: string, value: unknown): void {
  if (value === undefined) delete store[key]
  else store[key] = value
  persist()
}

// ── Typed helpers mirroring the Swift keys ──────────────────────────────────

export type SourceKind = "hermes" | "local"

export const gatewayEnabled = (kind: SourceKind) => getBool(`gatewayEnabled.${kind}`, false)
export const setGatewayEnabled = (kind: SourceKind, on: boolean) => set(`gatewayEnabled.${kind}`, on)

export const petEnabled = (kind: SourceKind) => getBool(`petEnabled.${kind}`, true)
export const setPetEnabled = (kind: SourceKind, on: boolean) => set(`petEnabled.${kind}`, on)

export const selectedPet = (kind: SourceKind) =>
  getString(`selectedPet.${kind}`) ?? getString("selectedPet")
export const setSelectedPet = (kind: SourceKind, id: string) => set(`selectedPet.${kind}`, id)

export const petScale = () => getNumber("petScale", 1.5)
export const setPetScale = (scale: number) => set("petScale", scale)

export const dotHidden = (kind: SourceKind, slug: string) => getBool(`dotHidden.${kind}:${slug}`, false)
export const setDotHidden = (kind: SourceKind, slug: string, hidden: boolean) =>
  set(`dotHidden.${kind}:${slug}`, hidden)

export const sourceRepo = () => getString("sourceRepo")
export const setSourceRepo = (path: string) => set("sourceRepo", path)

// Last-good provider caching for the 15-min transient-error smoothing.
const LAST_GOOD_TTL_MS = 15 * 60 * 1000

export function cacheGood(kind: SourceKind, slug: string, provider: unknown): void {
  set(`goodQuota.${kind}:${slug}`, provider)
  set(`goodQuotaAt.${kind}:${slug}`, Date.now())
}

export function lastGood<T>(kind: SourceKind, slug: string): T | null {
  const at = getNumber(`goodQuotaAt.${kind}:${slug}`, 0)
  if (!at || Date.now() - at > LAST_GOOD_TTL_MS) return null
  const v = store[`goodQuota.${kind}:${slug}`]
  return (v as T) ?? null
}
