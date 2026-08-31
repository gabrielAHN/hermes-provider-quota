// Icon set (Lucide) replacing the Swift app's SF Symbols. Bun embeds each SVG
// string into the binary; <svg source> is tinted by style.color.

import chevronDown from "../assets/icons/chevron-down.svg" with { type: "text" }
import chevronRight from "../assets/icons/chevron-right.svg" with { type: "text" }
import refreshCw from "../assets/icons/refresh-cw.svg" with { type: "text" }
import rotateCw from "../assets/icons/rotate-cw.svg" with { type: "text" }
import eye from "../assets/icons/eye.svg" with { type: "text" }
import eyeOff from "../assets/icons/eye-off.svg" with { type: "text" }
import logIn from "../assets/icons/log-in.svg" with { type: "text" }
import logOut from "../assets/icons/log-out.svg" with { type: "text" }
import settings from "../assets/icons/settings.svg" with { type: "text" }
import pawPrint from "../assets/icons/paw-print.svg" with { type: "text" }
import gauge from "../assets/icons/gauge.svg" with { type: "text" }
import network from "../assets/icons/network.svg" with { type: "text" }
import xIcon from "../assets/icons/x.svg" with { type: "text" }
import gitBranch from "../assets/icons/git-branch.svg" with { type: "text" }
import terminal from "../assets/icons/terminal.svg" with { type: "text" }
import sparkles from "../assets/icons/sparkles.svg" with { type: "text" }
import code from "../assets/icons/code.svg" with { type: "text" }

export const ICONS = {
  chevronDown,
  chevronRight,
  refreshCw,
  rotateCw,
  eye,
  eyeOff,
  logIn,
  logOut,
  settings,
  pawPrint,
  gauge,
  network,
  x: xIcon,
  gitBranch,
  terminal,
  sparkles,
  code,
} as const

export type IconName = keyof typeof ICONS

export function Icon({ name, size = 15, color }: { name: IconName; size?: number; color: string }) {
  return <svg source={ICONS[name]} style={{ width: size, height: size, flexShrink: 0, color }} />
}
