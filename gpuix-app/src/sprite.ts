// Spritesheet pipeline: resolve a pet's sheet → convert .webp to .png (sips) →
// decode (fast-png) → alpha-scan per-row frame counts. Cached per pet id.
//
// Frames are a fixed 192x208 grid (agent/pet FRAME_W/H). Rows encode states and
// can be ragged (fewer frames on some rows), so we detect left-packed non-empty
// columns per row exactly like the Swift detectFramesPerRow.

import { decode } from "fast-png"
import { existsSync, mkdirSync, readFileSync, statSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"
import { spritesheetPath } from "./data.ts"

export const FRAME_W = 192
export const FRAME_H = 208

// Canonical Hermes/petdex state rows.
export const ROW = {
  idle: 0,
  runRight: 1,
  runLeft: 2,
  wave: 3,
  jump: 4,
  fail: 5,
  wait: 6,
  run: 7,
  review: 8,
} as const

export interface SpriteSheet {
  pngPath: string
  width: number
  height: number
  cols: number
  rows: number
  framesPerRow: number[]
}

const CACHE_DIR = join(homedir(), "Library", "Application Support", "ProviderQuotas", "sprites")
const cache = new Map<string, SpriteSheet | null>()
const pending = new Map<string, Promise<SpriteSheet | null>>()

async function toPng(srcPath: string, id: string): Promise<string | null> {
  if (srcPath.endsWith(".png")) return srcPath
  mkdirSync(CACHE_DIR, { recursive: true })
  const out = join(CACHE_DIR, `${id}.png`)
  // Reuse the cached PNG unless the source is newer.
  try {
    if (existsSync(out) && statSync(out).mtimeMs >= statSync(srcPath).mtimeMs) return out
  } catch {
    // fall through and (re)convert
  }
  const proc = Bun.spawn(["/usr/bin/sips", "-s", "format", "png", srcPath, "--out", out], {
    stdout: "ignore",
    stderr: "ignore",
  })
  const code = await proc.exited
  return code === 0 && existsSync(out) ? out : null
}

// Left-packed non-empty columns per row, sampling every 4px, alpha > 16.
function detectFramesPerRow(
  data: ArrayLike<number>,
  width: number,
  channels: number,
  cols: number,
  rows: number,
): number[] {
  if (channels < 4) return new Array(rows).fill(cols) // no alpha ⇒ assume full rows
  const alphaAt = (x: number, y: number): number => data[(y * width + x) * channels + 3] as number
  const result: number[] = []
  for (let r = 0; r < rows; r++) {
    let used = 0
    for (let c = 0; c < cols; c++) {
      const x0 = c * FRAME_W
      const y0 = r * FRAME_H
      let any = false
      for (let dy = 0; dy < FRAME_H && !any; dy += 4) {
        for (let dx = 0; dx < FRAME_W; dx += 4) {
          if (alphaAt(x0 + dx, y0 + dy) > 16) {
            any = true
            break
          }
        }
      }
      if (!any) break // left-packed: stop at the first empty column
      used++
    }
    result.push(Math.max(1, used))
  }
  return result
}

async function build(id: string): Promise<SpriteSheet | null> {
  const src = await spritesheetPath(id)
  if (!src) return null
  const pngPath = await toPng(src, id)
  if (!pngPath) return null
  let sheet: SpriteSheet
  try {
    const img = decode(readFileSync(pngPath))
    const width = img.width
    const height = img.height
    const cols = Math.max(1, Math.floor(width / FRAME_W))
    const rows = Math.max(1, Math.floor(height / FRAME_H))
    const framesPerRow = detectFramesPerRow(img.data, width, img.channels, cols, rows)
    sheet = { pngPath, width, height, cols, rows, framesPerRow }
  } catch {
    // Decode failed — fall back to the raw grid so the pet still animates.
    sheet = { pngPath, width: 0, height: 0, cols: 1, rows: 1, framesPerRow: [1] }
  }
  return sheet
}

export function loadSprite(id: string): Promise<SpriteSheet | null> {
  if (cache.has(id)) return Promise.resolve(cache.get(id)!)
  const inflight = pending.get(id)
  if (inflight) return inflight
  const p = build(id).then((sheet) => {
    cache.set(id, sheet)
    pending.delete(id)
    return sheet
  })
  pending.set(id, p)
  return p
}

// Map a session/pet status to a sprite row, clamped to what the sheet has.
export function rowForStatus(sheet: SpriteSheet, status: string, sinceCompletedMs: number): number {
  let row: number = ROW.idle
  switch (status) {
    case "working":
      row = ROW.run
      break
    case "waiting":
      row = ROW.wait
      break
    case "error":
    case "failed":
      row = ROW.fail
      break
    case "completed":
      row = sinceCompletedMs < 1800 ? ROW.jump : ROW.idle
      break
    default:
      row = ROW.idle
  }
  return Math.min(row, sheet.rows - 1)
}
