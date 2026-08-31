// The pet tile: a frame-animated spritesheet (CSS-sprite clip) with a status
// halo and, below it, one rounded pill capsule per live session holding a round
// dot per model family.

import { FRAME_W, FRAME_H, rowForStatus, type SpriteSheet } from "./sprite.ts"
import { HERMES, providerHex } from "./theme.ts"
import type { SessionMark } from "./data.ts"

export interface PetTileData {
  kind: "hermes" | "local"
  displayName: string
  sheet: SpriteSheet | null
  sessions: SessionMark[]
  busy: boolean
}

function haloColor(status: string): string {
  switch (status) {
    case "error":
    case "failed":
      return HERMES.red
    case "waiting":
      return HERMES.orange
    case "completed":
      return HERMES.green
    default:
      return HERMES.blue
  }
}

// The dot groups (capsules) for a tile — one group per session, one dot per model
// family, total dots capped at 7 (matching the Swift pet).
function dotGroups(sessions: SessionMark[]): { colors: string[]; busy: boolean }[] {
  const groups: { colors: string[]; busy: boolean }[] = []
  let total = 0
  for (const s of sessions) {
    const colors = (s.families.length ? s.families : ["hermes"]).map((f) =>
      f === "hermes" ? HERMES.blue : providerHex(f),
    )
    if (groups.length && total + colors.length > 7) break
    groups.push({ colors, busy: s.busy })
    total += colors.length
    if (total >= 7) break
  }
  return groups
}

export function Pet({ tile, phase, scale }: { tile: PetTileData; phase: number; scale: number }) {
  const s = scale
  const petH = 58 * s
  const petW = petH * (FRAME_W / FRAME_H)
  const status = tile.busy ? "working" : "idle"

  // Sprite frame → clip offset.
  const sheet = tile.sheet
  let imgW = petW
  let imgH = petH
  let left = 0
  let top = 0
  if (sheet && sheet.width > 0) {
    const f = petW / FRAME_W
    imgW = sheet.width * f
    imgH = sheet.height * f
    const row = rowForStatus(sheet, status, 0)
    const perRow = sheet.framesPerRow[row] ?? 1
    const col = Math.floor(phase / 2) % perRow
    left = -(col * FRAME_W * f)
    top = -(row * FRAME_H * f)
  }

  // Halo pulse.
  const haloPulse = ((Math.sin(phase * (Math.PI / 6)) + 1) * 0.035)
  const haloAlpha = (tile.busy ? 0.17 : 0.09) + haloPulse
  const halo = haloColor(status)

  // Dot metrics — round dots inside a fully-rounded pill.
  const dotSize = 6 * s
  const innerGap = 1.5 * s
  const capPadX = 3 * s
  const capH = dotSize + 6 * s
  const groups = dotGroups(tile.sessions)

  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3 * s }}>
      {/* Pet + halo */}
      <div style={{ position: "relative", width: petW, height: petH }}>
        <div
          style={{
            position: "absolute",
            left: petW * 0.04,
            top: petH * 0.1,
            width: petW * 0.92,
            height: petH * 0.86,
            borderRadius: petH,
            backgroundColor: withAlpha(halo, haloAlpha),
          }}
        />
        {sheet ? (
          <div style={{ position: "relative", width: petW, height: petH, overflow: "hidden" }}>
            <img
              src={sheet.pngPath}
              objectFit="fill"
              style={{ position: "absolute", left, top, width: imgW, height: imgH }}
            />
          </div>
        ) : (
          <div style={{ width: petW, height: petH }} />
        )}
      </div>

      {/* Per-session dot capsules */}
      {groups.length > 0 && (
        <div style={{ display: "flex", flexDirection: "row", alignItems: "center", gap: 9 * s }}>
          {groups.map((group, gi) => {
            const highlight = group.busy && gi === phase % Math.max(groups.length, 1)
            const pulse = group.busy ? (Math.sin(phase * (Math.PI / 4) + gi) + 1) * 0.5 * s : 0
            const size = dotSize + (highlight ? 1 * s : 0) + pulse
            const alpha = group.busy ? 1 : 0.55
            return (
              <div
                key={gi}
                style={{
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: innerGap,
                  height: capH,
                  paddingLeft: capPadX,
                  paddingRight: capPadX,
                  borderRadius: capH / 2, // fully-rounded pill ends
                  backgroundColor: "#00000066",
                  borderWidth: 0.75,
                  borderColor: "#FFFFFF59",
                }}
              >
                {group.colors.map((color, ci) => (
                  <div
                    key={ci}
                    style={{
                      width: size,
                      height: size, // equal ⇒ a true circle, not an oval
                      borderRadius: size / 2,
                      backgroundColor: withAlpha(color, alpha),
                      borderWidth: 0.75,
                      borderColor: "#FFFFFFD9",
                    }}
                  />
                ))}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

export function PetsStrip({ tiles, phase, scale }: { tiles: PetTileData[]; phase: number; scale: number }) {
  if (tiles.length === 0) return null
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "row",
        justifyContent: "center",
        alignItems: "flex-end",
        gap: 16,
        paddingTop: 10,
        paddingBottom: 12,
      }}
    >
      {tiles.map((tile) => (
        <Pet key={tile.kind} tile={tile} phase={phase} scale={scale} />
      ))}
    </div>
  )
}

// Append an alpha byte (0..1) to a #RRGGBB colour.
function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha)) * 255)
    .toString(16)
    .padStart(2, "0")
  const base = hex.length >= 7 ? hex.slice(0, 7) : hex
  return `${base}${a}`
}
