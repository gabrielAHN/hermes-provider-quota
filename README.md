# Quota Viewer 👀

A macOS **GPU-rendered desktop app** (built on [gpuix](https://github.com/remorses/gpuix)
— React bindings for Zed's GPUI) + **Hermes gateway plugin** that shows live
account quota for your providers — **OpenRouter**, **Claude**, and **Codex** —
with usage bars, reset times, and animated **per-session pets**. It renders
natively on the GPU in a frosted-glass window (no Electron, no web view), and
ships as a single self-contained binary.

> Previously a menu-bar app (Swift/AppKit). It was fully rewritten on gpuix; the
> app is now a standalone window, launched from the Dock/Spotlight, since gpuix
> renders windows rather than menu-bar items.

It works with **any Hermes gateway**: the app piggybacks on the Hermes Desktop
app's own gateway URL + session, so it shows exactly what your Desktop can see
(local backend or remote gateway) — nothing is hardcoded. It also has a
**Local** source that reads the providers authenticated directly on your Mac
(their own usage APIs), with no gateway at all.

The sources are **configured by you** — nothing is assumed or hardcoded. Both
**Hermes** and **Local** start **off**; the `Sources` row has an enable chip for
each, and you turn on the ones you want. The app uses **all enabled sources at
once**, with no fallback: enable both and each source's providers are listed
together under a small source header, so the same provider (e.g. Claude) can
appear once per source. Disabling a chip drops that source's providers. With none
enabled the window says so; when a source is disconnected its providers still list
as **Disconnected**. Hermes has a gateway session, so it gets **Login** /
**Logout** buttons; Local providers authenticate via their own CLIs
(`claude login`, etc.).

![pet states](docs/pets.png)

## How it works

- **`dashboard/`** — the **`provider-quota`** gateway plugin (one plugin, two
  endpoints):
  - `/api/plugins/provider-quota/quotas` — each provider's usage, read from the
    credentials already in the gateway session (stays linked to the gateway it's
    installed in; provider set **configurable per gateway** — see below). Also `/pets`.
  - `/api/plugins/provider-quota/activity` — the Hermes turns RUNNING right now
    (Desktop chats/bots and `tui_gateway` turns, which REST never marks
    `is_active`), each with its model so the pet colours it per provider. Reads
    only the gateway's own logs + active-sessions registry (no session DB /
    internals), so it needs no privileged capabilities and stays enabled.
- **`gpuix-app/`** — the macOS window app (Bun + TypeScript + `@gpuix/react`).
  Every 60s it shells out to `desktop-quotas.sh` (quotas) and every 1s to
  `--activity` (live sessions), plus a native scan of local `claude`/`codex`/
  `opencode` sessions for the Local pet. Pet spritesheets are decoded with
  `fast-png` and frame-animated via a CSS-sprite clip. Build with
  `bun run build` → one standalone binary; `install-app.sh` wraps it in
  `~/Applications/Provider Quotas.app`.
- **`local-quotas.sh`** — the **Local** source. When Local is enabled it reads
  each provider's usage API directly from the credentials on this Mac: Claude
  from `~/.claude/.credentials.json` or the login Keychain, Codex from `~/.codex`
  (or a Goose `chatgpt_codex` token), OpenRouter from `OPENROUTER_API_KEY`, and
  **opencode** from the OpenRouter key opencode itself authenticated with
  (`~/.local/share/opencode/auth.json`) — shown as its own row with the same
  credits data. A
  provider only appears if its credential exists locally. (Gemini/xAI have no
  simple usage API, so they're skipped.)
- **`desktop/`** — optional Hermes Desktop sidebar page.

The app fetches from **each enabled source** and lists them together, grouped by
source — it never falls back one to the other. A disconnected source's providers
still list (as **Disconnected**); when every enabled source is down the activity
pet shows a "not working" state (red halo + `!`).

## Install

On the machine running your Hermes gateway:

```bash
./install.sh      # install + enable the provider-quota plugin (quotas + activity),
                  # then restart the dashboard to load the routes
./verify.sh       # smoke-test the endpoint
```

On your Mac:

```bash
./install-app.sh              # installs Bun if needed, builds the gpuix binary,
                              # installs Provider Quotas.app + the data helpers;
                              # if a Hermes gateway is present locally it also
                              # runs install.sh for you
./install-app.sh --login-item # (optional) also auto-open the window at login
```

Then launch it from Spotlight/Dock (or `open -a "Provider Quotas"`). macOS may
block the unsigned binary the first time — right-click the app, choose **Open**.

For a **remote** gateway, run `install.sh` on the gateway host and
`install-app.sh` on your Mac.

## Configuring providers (per gateway)

The plugin reports on a configurable set of providers, so it's reusable in any
setup — it isn't tied to one person's provider list. Set the
`PROVIDER_QUOTA_PROVIDERS` env var on the gateway to a comma-separated list of
provider slugs (optionally `slug=Label`):

```bash
# just the two you use, with a custom label
PROVIDER_QUOTA_PROVIDERS="anthropic=Claude,openrouter"
```

- Unset → defaults to `openrouter,anthropic,openai-codex`.
- Slugs are whatever your gateway's `account_usage` supports; unknown slugs get a
  title-cased label.
- Every quota is read through the **host gateway's own credentials**
  (`account_usage`), and the response carries the gateway's `broker` host — so
  the plugin always stays linked to the gateway it runs in, whatever the set.

## Features

- The collapsed provider row shows the **current-session %** as a **bar in the
  provider's own colour** (not the weekly/total), plus a status dot; **click to
  expand** for per-window bars, reset times, and details. A provider that's
  **offline or out of quota** gets a **bold red ring** around its status dot. A
  provider that's connected but can't read its usage right now (e.g. a transient
  HTTP 429) is **not** flagged — it keeps its last-known quota (cached up to
  15 min) so a rate-limit blip doesn't read as an outage.
- Each row has an **eye toggle** that hides that provider family's dots from the
  **pet** (so you can keep the pet focused on the providers you care about).
- When an enabled source is disconnected, its providers still list, each marked
  **Disconnected**, so you always see what's configured and what's down.
  Disabling a source (its chip) removes all providers linked to it.
- Each source's own controls live **in its header row** as a tidy, evenly-spaced
  row of icon buttons, next to its name and connected/disconnected state — for
  Hermes, **Login/Logout** and **Setup** (opens the Hermes Desktop gateway page),
  plus a **Refresh** that re-checks that whole source (a spinner while it fetches).
  The bottom action bar has just **Close**. Switching a source on shows an
  **"Activating …" spinner** in its place until its first quotas land.
- **Per-source pets** — **one** animated companion **per source** (Hermes and
  Local), configured with two icon buttons **in the source header row**: a **paw**
  that toggles the pet on/off and a **switch** button (cycles to the next
  installed pet). Pet **size** (Small / Medium / Large) persists across launches
  (`petScale`). Under each pet is a row of session marks that appears **only while
  sessions are actually running** — nothing when the source is idle. Each
  **actively-running** session is a **rounded pill capsule** holding one **round
  dot per model** the session is using, so a multi-model turn reads as a little
  **cluster** of coloured dots grouped together; several sessions → several
  capsules (capped at 7 dots). When a session **finishes, its dots simply
  disappear** (no lingering checkmark). Each dot is coloured by its **model
  family** — a running **OpenRouter** model is **purple** (Claude orange, Codex
  green, Copilot grey) — resolved from one canonical map so a provider like
  **Codex looks the same across the Local and Hermes sources**. **Hermes** reads
  the gateway's live sessions from `--activity` (the plugin merges Desktop chats,
  `tui_gateway` turns, and the active-sessions registry — catching **bot
  conversations** that never hit the aggregate counters), keying "live" off
  `is_active` with short grace windows so a dot clears promptly when a turn ends.
  **Local** natively scans this Mac's `claude`/`codex`/`opencode` sessions
  (process list + transcript/rollout freshness + the opencode SQLite db). The
  picker offers **Nukey** (Hermes's default) plus **Boba, Capy and Scoop** and
  whatever else is installed — `install-app.sh` fetches those three from the
  [petdex](https://petdex.dev) catalog Hermes itself uses, while the **Lulu**
  capybaras and **cats** are hidden. Sheets are decoded with `fast-png` and the
  app measures each sheet's **per-row frame count** from its alpha, so pets with
  shorter rows (e.g. a 4-frame idle vs. Nukey's 8) loop cleanly instead of
  flickering through blank cells, playing each row at a **steady ~5 fps** via a
  CSS-sprite clip. Pet art is loaded from your local Hermes install / petdex and
  is not redistributed here.
- **Hermes and Local, together** — enable each source yourself (both off by
  default, nothing hardcoded); the app lists **all enabled sources at once**,
  grouped by source, so the same provider can appear once per source. No
  fallback. Local reads the providers authenticated on this Mac directly.

## Requirements

This is a **macOS** desktop app (a gpuix/GPUI window) — it does not run on iOS.

- **macOS 13 (Ventura) or later**.
- **[Bun](https://bun.sh)** — `install-app.sh` builds the app with
  `bun build --compile` (and installs Bun for you if it's missing).
- **A source** — either:
  - **Hermes Desktop** installed and signed in (the app reuses its session and
    stores no credentials of its own), with a **Hermes gateway** running the
    `provider-quota` plugin (`./install.sh` on the gateway host); **or**
  - **Local** — provider logins on this Mac: a Claude/Anthropic OAuth login
    (`claude login`), a ChatGPT/Codex login (`~/.codex`),
    `OPENROUTER_API_KEY`, and/or an `opencode auth login` (OpenRouter).
- Provider credentials for whichever gateway you use (you only see quota for the
  providers that are actually signed in): an OpenRouter API key, a
  Claude/Anthropic OAuth login, and/or a ChatGPT/Codex login.
- `python3` and `openssl` — both preinstalled on macOS; the quota helper needs
  no extra Python packages.

## License

MIT — see [LICENSE](LICENSE).
