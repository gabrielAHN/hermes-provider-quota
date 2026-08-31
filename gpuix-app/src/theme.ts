// Colours, fonts, and the canonical provider identity map — one source of truth
// so a provider looks the SAME across sources (Local vs Hermes) and in the pet.
// Ported from the Swift app (ProviderQuotaMenuBar.swift) to keep parity.

export const FONT = "SF Pro Text"
export const MONO = "SF Mono"

// Hermes status palette (glow / halo / connection dots).
export const HERMES = {
  blue: "#0053fd",
  green: "#1f8a65",
  orange: "#db704b",
  red: "#cf2d56",
  yellow: "#c08532",
} as const

// Surface tokens for the blurred window (translucent whites over the backdrop).
export const C = {
  text: "#F5F6F8",
  secondary: "#F5F6F8B0",
  tertiary: "#F5F6F870",
  faint: "#F5F6F840",
  overlay: "#FFFFFF14",
  overlayStrong: "#FFFFFF24",
  border: "#FFFFFF1F",
  track: "#FFFFFF24",
  panel: "#0A10182E",
} as const

// Canonical provider slug — aliases collapse so colour/label/symbol derive from one key.
export function normalizedProvider(slug: string): string {
  switch (slug.toLowerCase()) {
    case "anthropic":
    case "claude":
    case "claude-sub":
      return "anthropic"
    case "openai-codex":
    case "codex":
    case "openai":
    case "chatgpt":
      return "openai-codex"
    case "openrouter":
      return "openrouter"
    case "opencode":
      return "opencode"
    case "copilot":
    case "copilot-acp":
    case "github-copilot":
      return "copilot"
    default:
      return slug.toLowerCase()
  }
}

// Brand colour per provider (distinct from the status palette above).
export function providerHex(slug: string): string {
  switch (normalizedProvider(slug)) {
    case "openrouter":
      return "#8e1afe" // purple
    case "opencode":
      return "#38bdf8" // sky
    case "anthropic":
      return "#d97757" // orange
    case "openai-codex":
      return "#10a37f" // green
    case "copilot":
      return "#6e7681" // grey
    default:
      return "#8e8e93"
  }
}

export function providerLabel(slug: string): string {
  switch (normalizedProvider(slug)) {
    case "openrouter":
      return "OpenRouter"
    case "opencode":
      return "opencode"
    case "anthropic":
      return "Claude"
    case "openai-codex":
      return "Codex"
    case "copilot":
      return "Copilot"
    default:
      return slug.charAt(0).toUpperCase() + slug.slice(1)
  }
}

// Icon name (see icons.ts) standing in for the Swift app's SF Symbol per provider.
export function providerIcon(slug: string): string {
  switch (normalizedProvider(slug)) {
    case "openrouter":
      return "gitBranch"
    case "opencode":
      return "terminal"
    case "anthropic":
      return "sparkles"
    default:
      return "code"
  }
}

// Resolve the provider FAMILY a model belongs to — must classify identically to
// desktop-quotas.sh:_dot_provider so the pet dots match the menu. OpenRouter
// serves "vendor/model" slugs, so ANY "/" means OpenRouter.
export function familyForModel(model: string | null | undefined): string {
  const m = (model || "").toLowerCase()
  if (m) {
    if (m.includes("/")) return "openrouter"
    if (m.startsWith("claude")) return "anthropic"
    if (m.startsWith("gpt") || m.includes("codex") || /^o[134]/.test(m)) return "openai-codex"
  }
  return ""
}

// Bar colour: brand colour, red only when the window/provider is exhausted.
export function barColor(slug: string, exhausted: boolean): string {
  return exhausted ? HERMES.red : providerHex(slug)
}
