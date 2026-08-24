# Quota Viewer 👀

A macOS **menu-bar app** + **Hermes gateway plugin** that shows live account
quota for your Hermes providers — **OpenRouter**, **Claude**, and **Codex** —
with usage bars, reset times, and animated activity pets.

It works with **any Hermes gateway**: the app piggybacks on the Hermes Desktop
app's own gateway URL + session, so it shows exactly what your Desktop can see
(local backend or remote gateway) — nothing is hardcoded.

![pet states](docs/pets.png)

## How it works

- **`dashboard/`** — the gateway plugin, serving `/api/plugins/provider-quota/quotas`
  (and `/pets`). It reads each provider's usage from the credentials already in
  the gateway session — nothing new to configure.
- **`menubar/`** — the macOS menu-bar app. Every 60s it runs `desktop-quotas.sh`,
  which resolves the gateway your Hermes **Desktop** is bound to and fetches the
  endpoint. Portable (system `python3` + `openssl`), no extra deps.
- **`desktop/`** — optional Hermes Desktop sidebar page.

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

## Features

- One dot per provider, coloured by its own status; expand a row for usage bars
  and per-window reset times.
- Hermes-blue theme with glowing action buttons: Refresh · Open Hermes · Pets ·
  Login · Logout · Close.
- **Activity pets** — an animated companion per running agent: idle when
  dormant, running when working, plus waiting / error / celebrate. Toggle with
  the Pets chip; the "Pet:" row cycles through installed pets. Pet art is loaded
  from your local Hermes install and is not redistributed here.

## Requirements

This is a **macOS** app (an AppKit menu-bar agent) — it does not run on iOS.

- **macOS 13 (Ventura) or later**.
- **Xcode command-line tools** (`xcode-select --install`) — `install-menubar.sh`
  compiles the app with `xcrun swiftc`.
- **Hermes Desktop** installed and signed in to your gateway — the menu-bar app
  reuses its session and stores no credentials of its own.
- A **Hermes gateway** (a local backend or a remote gateway) with the
  `provider-quota` plugin installed — run `./install.sh` on the gateway host.
- Provider credentials configured **on the gateway** (you only see quota for the
  providers it has): an OpenRouter API key, a Claude/Anthropic OAuth login,
  and/or a ChatGPT/Codex login.
- `python3` and `openssl` — both preinstalled on macOS; the quota helper needs
  no extra Python packages.

## License

MIT — see [LICENSE](LICENSE).
