/**
 * Provider Quotas — a gpuix (GPU-rendered) standalone window showing provider
 * quotas + animated session "pets". Data comes from the same helper scripts the
 * old menu-bar app used (~/.local/bin/hermes-{desktop,local}-quotas).
 *
 * Desktop: bun run dev   ·   Binary: bun run build && ./dist/provider-quotas
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { render } from "@gpuix/react"

import { C, HERMES, providerHex } from "./theme.ts"
import { relativeAge, type QuotaProvider } from "./quota.ts"
import {
  fetchQuotas,
  fetchHermesActivity,
  fetchLocalActivity,
  fetchPetsList,
  type Activity,
  type PetInfo,
  type SourceKind,
} from "./data.ts"
import { loadSprite, type SpriteSheet } from "./sprite.ts"
import * as settings from "./settings.ts"
import { Header, SourcesRow, SourceHeader, ProviderRow, MessageRow, ActionBar, WIDTH } from "./components.tsx"
import { PetsStrip, type PetTileData } from "./pet.tsx"

const KINDS: SourceKind[] = ["hermes", "local"]

interface SourceState {
  enabled: boolean
  connected: boolean
  loading: boolean
  providers: QuotaProvider[]
  error?: string
  updatedAt?: number
}

function initialSource(kind: SourceKind): SourceState {
  const enabled = settings.gatewayEnabled(kind)
  return { enabled, connected: false, loading: enabled, providers: [] }
}

// ── Pets, isolated so the 10fps animation doesn't re-render the quota rows ────

function AnimatedPets({ tiles, scale }: { tiles: PetTileData[]; scale: number }) {
  const [phase, setPhase] = useState(0)
  const active = tiles.length > 0
  useEffect(() => {
    if (!active) return
    const id = setInterval(() => setPhase((p) => (p + 1) % 1680), 100)
    return () => clearInterval(id)
  }, [active])
  return <PetsStrip tiles={tiles} phase={phase} scale={scale} />
}

function App() {
  const [sources, setSources] = useState<Record<SourceKind, SourceState>>({
    hermes: initialSource("hermes"),
    local: initialSource("local"),
  })
  const [activity, setActivity] = useState<Record<SourceKind, Activity>>({
    hermes: { busy: false, sessions: [] },
    local: { busy: false, sessions: [] },
  })
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [pets, setPets] = useState<PetInfo[]>([])
  const [sprites, setSprites] = useState<Record<string, SpriteSheet | null>>({})
  const [refreshing, setRefreshing] = useState<Record<SourceKind, boolean>>({ hermes: false, local: false })

  // Mirror the persisted pet prefs in state so toggles re-render.
  const [petOn, setPetOn] = useState<Record<SourceKind, boolean>>({
    hermes: settings.petEnabled("hermes"),
    local: settings.petEnabled("local"),
  })
  const [selected, setSelected] = useState<Record<SourceKind, string | undefined>>({
    hermes: settings.selectedPet("hermes") ?? "nukey",
    local: settings.selectedPet("local") ?? "nukey",
  })
  const [scale, setScale] = useState<number>(settings.petScale())
  const [hiddenTick, setHiddenTick] = useState(0) // bump to re-read dotHidden

  const quotaInFlight = useRef<Record<SourceKind, boolean>>({ hermes: false, local: false })
  const actInFlight = useRef<Record<SourceKind, boolean>>({ hermes: false, local: false })

  const refreshQuota = useCallback(async (kind: SourceKind) => {
    if (quotaInFlight.current[kind]) return
    quotaInFlight.current[kind] = true
    try {
      const res = await fetchQuotas(kind)
      setSources((prev) => ({
        ...prev,
        [kind]: {
          ...prev[kind],
          loading: false,
          connected: res.ok,
          providers: res.ok ? res.payload!.providers : prev[kind].providers,
          error: res.ok ? undefined : res.error,
          updatedAt: res.ok ? Date.now() : prev[kind].updatedAt,
        },
      }))
    } finally {
      quotaInFlight.current[kind] = false
    }
  }, [])

  const refreshActivity = useCallback(async (kind: SourceKind) => {
    if (actInFlight.current[kind]) return
    actInFlight.current[kind] = true
    try {
      const act = kind === "hermes" ? await fetchHermesActivity() : await fetchLocalActivity()
      setActivity((prev) => ({ ...prev, [kind]: act }))
    } finally {
      actInFlight.current[kind] = false
    }
  }, [])

  // Initial: pets list + first fetch (quota + activity) for enabled sources.
  useEffect(() => {
    fetchPetsList().then((list) => {
      setPets(list)
      const fallback = list.find((p) => p.id === "nukey")?.id ?? list[0]?.id
      setSelected((prev) => {
        const next = { ...prev }
        for (const kind of KINDS) {
          // Correct a selection that isn't actually installed.
          if (fallback && (!next[kind] || !list.some((p) => p.id === next[kind]))) next[kind] = fallback
        }
        return next
      })
    })
    for (const kind of KINDS) {
      if (!settings.gatewayEnabled(kind)) continue
      refreshQuota(kind)
      if (settings.petEnabled(kind)) refreshActivity(kind)
    }
  }, [refreshQuota, refreshActivity])

  // Quota poll (60s) + activity poll (1s) for enabled sources.
  useEffect(() => {
    const q = setInterval(() => {
      for (const kind of KINDS) if (sources[kind].enabled) refreshQuota(kind)
    }, 60_000)
    const a = setInterval(() => {
      for (const kind of KINDS) if (sources[kind].enabled && petOn[kind]) refreshActivity(kind)
    }, 1_000)
    return () => {
      clearInterval(q)
      clearInterval(a)
    }
  }, [sources, petOn, refreshQuota, refreshActivity])

  // Load sprites for the pets currently shown.
  useEffect(() => {
    for (const kind of KINDS) {
      if (!sources[kind].enabled || !petOn[kind]) continue
      const id = selected[kind]
      if (!id || id in sprites) continue
      loadSprite(id).then((sheet) => setSprites((prev) => ({ ...prev, [id]: sheet })))
    }
  }, [sources, petOn, selected, sprites])

  // ── Handlers ──────────────────────────────────────────────────────────────

  const toggleSource = useCallback(
    (kind: SourceKind) => {
      const on = !sources[kind].enabled
      settings.setGatewayEnabled(kind, on)
      setSources((prev) => ({
        ...prev,
        [kind]: on
          ? { ...prev[kind], enabled: true, loading: prev[kind].providers.length === 0 }
          : { ...prev[kind], enabled: false, connected: false },
      }))
      if (on) {
        refreshQuota(kind)
        if (petOn[kind]) refreshActivity(kind)
      } else {
        setActivity((prev) => ({ ...prev, [kind]: { busy: false, sessions: [] } }))
      }
    },
    [sources, petOn, refreshQuota, refreshActivity],
  )

  const refreshSource = useCallback(
    async (kind: SourceKind) => {
      setRefreshing((p) => ({ ...p, [kind]: true }))
      await refreshQuota(kind)
      setRefreshing((p) => ({ ...p, [kind]: false }))
    },
    [refreshQuota],
  )

  const toggleProvider = useCallback((key: string) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }, [])

  const toggleDot = useCallback((kind: SourceKind, slug: string) => {
    settings.setDotHidden(kind, slug, !settings.dotHidden(kind, slug))
    setHiddenTick((t) => t + 1)
  }, [])

  const togglePet = useCallback(
    (kind: SourceKind) => {
      const on = !petOn[kind]
      settings.setPetEnabled(kind, on)
      setPetOn((p) => ({ ...p, [kind]: on }))
      if (on && sources[kind].enabled) refreshActivity(kind)
    },
    [petOn, sources, refreshActivity],
  )

  const cyclePet = useCallback(
    (kind: SourceKind) => {
      if (pets.length < 2) return
      const cur = selected[kind]
      const idx = Math.max(0, pets.findIndex((p) => p.id === cur))
      const next = pets[(idx + 1) % pets.length]!.id
      settings.setSelectedPet(kind, next)
      setSelected((s) => ({ ...s, [kind]: next }))
    },
    [pets, selected],
  )

  const openHermes = useCallback(() => {
    Bun.spawn(["/usr/bin/open", "-a", "Hermes"], { stdout: "ignore", stderr: "ignore" })
  }, [])

  const checkUpdates = useCallback(() => {
    const repo = settings.sourceRepo()
    if (!repo) return
    Bun.spawn(["/bin/bash", "-lc", `nohup bash "${repo}/update.sh" >/tmp/provider-quotas-update.log 2>&1 &`], {
      stdout: "ignore",
      stderr: "ignore",
    })
  }, [])

  const close = useCallback(() => process.exit(0), [])

  // ── Derived ─────────────────────────────────────────────────────────────

  const enabledKinds = KINDS.filter((k) => sources[k].enabled)
  const connectedCount = enabledKinds.filter((k) => sources[k].connected).length
  const summary =
    enabledKinds.length === 0
      ? "No sources enabled"
      : connectedCount === enabledKinds.length
        ? enabledKinds.length === 1
          ? "Connected"
          : "All sources connected"
        : `${connectedCount} of ${enabledKinds.length} connected`
  const summaryOk = enabledKinds.length > 0 && connectedCount === enabledKinds.length
  const latest = enabledKinds.map((k) => sources[k].updatedAt).filter((v): v is number => v != null)
  const updated = latest.length ? `Updated ${relativeAge(Math.max(...latest) / 1000)}` : "Not updated yet"

  const tiles = useMemo<PetTileData[]>(() => {
    void hiddenTick
    const out: PetTileData[] = []
    for (const kind of KINDS) {
      if (!sources[kind].enabled || !petOn[kind]) continue
      const id = selected[kind]
      const sheet = id ? sprites[id] ?? null : null
      const act = activity[kind]
      const sessions = []
      for (const s of act.sessions) {
        const fams = s.families.filter((f) => !settings.dotHidden(kind, f))
        if (s.families.length > 0 && fams.length === 0) continue
        sessions.push({ ...s, families: fams })
      }
      out.push({ kind, displayName: kind, sheet, sessions, busy: act.busy })
    }
    return out
  }, [sources, petOn, selected, sprites, activity, hiddenTick])

  return (
    <div
      testId="app-root"
      style={{
        display: "flex",
        flexDirection: "column",
        width: "100%",
        height: "100%",
        backgroundColor: C.panel,
      }}
    >
      <Header summary={summary} ok={summaryOk} updated={updated} />
      <SourcesRow
        hermesOn={sources.hermes.enabled}
        localOn={sources.local.enabled}
        hermesColor={sources.hermes.connected ? HERMES.green : HERMES.red}
        localColor={sources.local.connected ? HERMES.green : HERMES.red}
        onToggle={toggleSource}
      />

      <div style={{ flexGrow: 1, overflowY: "scroll" }}>
        {enabledKinds.length === 0 && <MessageRow text="Enable Hermes or Local above" />}
        {enabledKinds.map((kind) => {
          const src = sources[kind]
          return (
            <div key={kind}>
              <SourceHeader
                kind={kind}
                connected={src.connected}
                refreshing={refreshing[kind]}
                petOn={petOn[kind]}
                hasPets={pets.length > 0}
                multiplePets={pets.length > 1}
                onRefresh={() => refreshSource(kind)}
                onTogglePet={() => togglePet(kind)}
                onCyclePet={() => cyclePet(kind)}
                onLogin={openHermes}
                onSetup={openHermes}
              />
              {src.loading && src.providers.length === 0 ? (
                <MessageRow text={`Activating ${kind === "hermes" ? "Hermes" : "Local"}…`} />
              ) : src.connected || src.providers.length > 0 ? (
                src.providers.map((p) => {
                  const key = `${kind}:${p.provider}`
                  return (
                    <ProviderRow
                      key={key}
                      kind={kind}
                      provider={p}
                      connected={src.connected}
                      expanded={expanded.has(key)}
                      dotHidden={settings.dotHidden(kind, p.provider)}
                      onToggleExpand={() => toggleProvider(key)}
                      onToggleDot={() => toggleDot(kind, p.provider)}
                    />
                  )
                })
              ) : (
                <MessageRow text={src.error || "Disconnected"} color={HERMES.orange} />
              )}
            </div>
          )
        })}
      </div>

      <AnimatedPets tiles={tiles} scale={scale} />
      <ActionBar onCheckUpdates={checkUpdates} onClose={close} />
    </div>
  )
}

const isEntryPoint =
  typeof Bun !== "undefined" ? Bun.isStandaloneExecutable || Bun.main === import.meta.path : false

if (isEntryPoint) {
  render(<App />, {
    title: "Provider Quotas",
    appName: "Provider Quotas",
    width: WIDTH,
    height: 620,
    minWidth: WIDTH,
    minHeight: 420,
    titlebarTransparent: true,
    windowBackground: "blurred",
    trafficLightX: 14,
    trafficLightY: 16,
    focus: typeof process === "undefined" || process.env.GPUIX_BACKGROUND !== "1",
  })
}

export { App }
