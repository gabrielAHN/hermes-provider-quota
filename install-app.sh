#!/bin/bash
# Build + install the gpuix Provider Quotas window app into
# ~/Applications/Provider Quotas.app, plus the data helpers (and, on a gateway
# host, the dashboard plugin). Launch from Spotlight/Dock afterwards.
#
#   bash install-app.sh                # build + install
#   bash install-app.sh --login-item   # also auto-open at login
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
app_dir="$service_home/gpuix-app"
app_target="$HOME/Applications/Provider Quotas.app"
binary_name="provider-quotas"
binary_target="$app_target/Contents/MacOS/$binary_name"
label="io.github.gabrielahn.provider-quotas"
support_dir="$HOME/Library/Application Support/ProviderQuotas"

# --- Retire the old Swift menu-bar app (this rewrite fully replaces it) ------
launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
pkill -f ProviderQuotaMenuBar >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"   # recreated below only for --login-item
rm -rf "$app_target"                              # drop the stale bundle (old binary/Info.plist)

# --- Bun (the app's runtime/bundler) ---------------------------------------
if command -v bun >/dev/null 2>&1; then BUN="$(command -v bun)"
elif [ -x /opt/homebrew/bin/bun ]; then BUN=/opt/homebrew/bin/bun
elif [ -x "$HOME/.bun/bin/bun" ]; then BUN="$HOME/.bun/bin/bun"
else
    echo "Installing Bun…"
    curl -fsSL https://bun.sh/install | bash
    BUN="$HOME/.bun/bin/bun"
fi

# --- Record the source repo so in-app "Check for Updates" can git pull ------
mkdir -p "$support_dir"
/usr/bin/python3 - "$support_dir/settings.json" "$service_home" <<'PY' || true
import json, os, sys
path, repo = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = {}
data["sourceRepo"] = repo
json.dump(data, open(path, "w"), indent=2)
PY

# --- Gateway plugin (best-effort; local gateway only) ----------------------
if command -v hermes >/dev/null 2>&1 && [ -d "$HOME/.hermes/plugins" ]; then
    bash "$service_home/install.sh" || echo "  (gateway plugin install skipped)"
else
    echo "  (no local Hermes gateway — install the plugin on the gateway host: bash install.sh)"
fi

# --- Data helpers (unchanged; the app shells out to these) ------------------
mkdir -p "$HOME/.local/bin"
install -m 755 "$service_home/desktop-quotas.sh" "$HOME/.local/bin/hermes-desktop-quotas"
install -m 755 "$service_home/local-quotas.sh" "$HOME/.local/bin/hermes-local-quotas"

# --- Curated pets: Boba / Capy / Scoop from the petdex catalog --------------
python3 - <<'PY' || true
import urllib.request, os, json
pets = {
    "boba":  ("Boba",  "https://assets.petdex.dev/curated/boba/sprite-v2.webp"),
    "capy":  ("Capy",  "https://assets.petdex.dev/pets/capy-c8b8801eb785/sprite.webp"),
    "scoop": ("Scoop", "https://assets.petdex.dev/curated/scoop/spritesheet.webp"),
}
base = os.path.expanduser("~/.hermes/pets")
for slug, (name, url) in pets.items():
    directory = os.path.join(base, slug)
    sheet = os.path.join(directory, "spritesheet.webp")
    if os.path.exists(sheet) and os.path.getsize(sheet) > 1000:
        continue
    os.makedirs(directory, exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hermes-agent-petdex"})
        open(sheet, "wb").write(urllib.request.urlopen(req, timeout=30).read())
        json.dump({"id": slug, "displayName": name, "spritesheetPath": "spritesheet.webp"},
                  open(os.path.join(directory, "pet.json"), "w"), indent=2)
        print(f"  fetched pet: {slug}")
    except Exception as exc:
        print(f"  (skipped pet {slug}: {exc})")
PY

# --- Build the standalone binary -------------------------------------------
cd "$app_dir"
"$BUN" install
"$BUN" build --compile src/app.tsx --outfile "dist/$binary_name"

# --- Wrap in an .app bundle ------------------------------------------------
mkdir -p "$app_target/Contents/MacOS"
install -m 755 "$app_dir/dist/$binary_name" "$binary_target"
install -m 644 "$app_dir/Info.plist" "$app_target/Contents/Info.plist"
codesign --force --sign - "$app_target" >/dev/null 2>&1 || true

# --- Optional: auto-open at login ------------------------------------------
if [ "${1:-}" = "--login-item" ]; then
    plist="$HOME/Library/LaunchAgents/$label.plist"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.hermes/logs"
    plutil -create xml1 "$plist"
    plutil -insert Label -string "$label" "$plist"
    plutil -insert ProgramArguments -array "$plist"
    plutil -insert ProgramArguments.0 -string "$binary_target" "$plist"
    plutil -insert RunAtLoad -bool true "$plist"
    plutil -insert ProcessType -string Interactive "$plist"
    plutil -insert StandardOutPath -string "$HOME/.hermes/logs/provider-quotas.log" "$plist"
    plutil -insert StandardErrorPath -string "$HOME/.hermes/logs/provider-quotas-error.log" "$plist"
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "Login item installed — the window opens at login."
fi

echo "Installed → $app_target"
echo "Launch from Spotlight/Dock, or:  open -a 'Provider Quotas'"
