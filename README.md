# Quota Viewer 👀

A macOS **menu-bar app** + **Hermes gateway plugin** that shows live account
quota for your Hermes providers — **OpenRouter**, **Claude**, and **Codex** —
with usage bars, reset times, and animated activity pets.

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
enabled the menu says so; when a source is disconnected its providers still list
as **Disconnected**. Hermes has a gateway session, so it gets **Login** /
**Logout** buttons; Local providers authenticate via their own CLIs
(`claude login`, etc.).

![pet states](docs/pets.png)

## How it works

- **`dashboard/`** — the gateway plugin, serving `/api/plugins/provider-quota/quotas`
  (and `/pets`). It reads each provider's usage from the credentials already in
  the gateway session, so it stays linked to the gateway it's installed in. The
  provider set is **configurable per gateway** so anyone can reuse it — see below.
- **`menubar/`** — the macOS menu-bar app. Every 60s it runs `desktop-quotas.sh`,
  which resolves the gateway your Hermes **Desktop** is bound to and fetches the
  endpoint. Portable (system `python3` + `openssl`), no extra deps.
- **`local-quotas.sh`** — the **Local** source. When Local is enabled it reads
  each provider's usage API directly from the credentials on this Mac: Claude
  from `~/.claude/.credentials.json` or the login Keychain, Codex from `~/.codex`
  (or a Goose `chatgpt_codex` token), OpenRouter from `OPENROUTER_API_KEY`. A
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
./install.sh      # install + enable the plugin, then restart the dashboard
./verify.sh       # smoke-test the endpoint
```

On your Mac:

```bash
./install-menubar.sh
```

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

- Each provider shows a brief row with a **bar graph in the provider's own
  colour** (remaining quota); **click to expand** for per-window bars, reset
  times, and details.
- When an enabled source is disconnected, its providers still list, each marked
  **Disconnected**, so you always see what's configured and what's down.
  Disabling a source (its chip) removes all providers linked to it.
- Hermes-blue theme with glowing action buttons: Refresh · Open gateway · Pets ·
  Login/Logout · **Setup** (opens the Hermes Desktop gateway page) · Close.
- **Activity pets** — an animated companion per running agent: idle when
  dormant, running when working, plus waiting / error / celebrate, and a
  "not working" state whenever the active gateway is disconnected and a sign-in
  is needed. Toggle with the Pets chip; the "Pet:" row cycles through installed
  pets. Pet art is loaded from your local Hermes install and is not
  redistributed here.
- **Hermes and Local, together** — enable each source yourself (both off by
  default, nothing hardcoded); the app lists **all enabled sources at once**,
  grouped by source, so the same provider can appear once per source. No
  fallback. Local reads the providers authenticated on this Mac directly.

## Requirements

This is a **macOS** app (an AppKit menu-bar agent) — it does not run on iOS.

- **macOS 13 (Ventura) or later**.
- **Xcode command-line tools** (`xcode-select --install`) — `install-menubar.sh`
  compiles the app with `xcrun swiftc`.
- **A source** — either:
  - **Hermes Desktop** installed and signed in (the app reuses its session and
    stores no credentials of its own), with a **Hermes gateway** running the
    `provider-quota` plugin (`./install.sh` on the gateway host); **or**
  - **Local** — provider logins on this Mac: a Claude/Anthropic OAuth login
    (`claude login`), a ChatGPT/Codex login (`~/.codex`), and/or
    `OPENROUTER_API_KEY`.
- Provider credentials for whichever gateway you use (you only see quota for the
  providers that are actually signed in): an OpenRouter API key, a
  Claude/Anthropic OAuth login, and/or a ChatGPT/Codex login.
- `python3` and `openssl` — both preinstalled on macOS; the quota helper needs
  no extra Python packages.

## License

MIT — see [LICENSE](LICENSE).
