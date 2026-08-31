// Headless screenshot harness (see the scaffold's screenshot.ts).
//   bun screenshot.ts [out.png]
import { mkdirSync } from "node:fs"
import path from "node:path"
import { launch } from "@gpuix/react/automation"

const out = process.argv[2] ?? "screenshots/app.png"
mkdirSync(path.dirname(out), { recursive: true })

const app = await launch({
  command: "bun",
  args: ["src/app.tsx"],
  env: { GPUIX_BACKGROUND: "1" },
})
await app.getByTestId("app-root").waitFor({ timeoutMs: 60_000 })
// Let the helper scripts + sprite decode finish, then advance a few animation
// frames so busy pulses/halo are visible.
await Bun.sleep(4000)
await app.clock.pause()
await app.screenshot({ path: out })
await app.close()
console.log(`[screenshot] wrote ${out}`)
