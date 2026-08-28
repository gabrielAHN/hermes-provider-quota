#!/bin/bash
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
app_target="$HOME/Applications/Provider Quotas.app"
binary_target="$app_target/Contents/MacOS/ProviderQuotaMenuBar"
plist_target="$HOME/Library/LaunchAgents/io.github.gabrielahn.provider-quotas.plist"
launch_target="gui/$(id -u)"
label="io.github.gabrielahn.provider-quotas"

mkdir -p "$app_target/Contents/MacOS" "$HOME/Library/LaunchAgents" "$HOME/.hermes/logs" "$HOME/.local/bin"
# Data sources: the Hermes Desktop app's gateway API (desktop-quotas.sh), and a
# gateway-agnostic fallback that queries each provider's usage API directly from
# local credentials (local-quotas.sh) — so quotas show under Goose, or with no
# gateway running, not just Hermes.
install -m 755 "$service_home/desktop-quotas.sh" "$HOME/.local/bin/hermes-desktop-quotas"
install -m 755 "$service_home/local-quotas.sh" "$HOME/.local/bin/hermes-local-quotas"

# Curated pets: fetch Boba / Capy / Scoop from the petdex catalog (the same
# source Hermes uses) into ~/.hermes/pets so the menu offers them. Nukey and the
# Lulu capybaras are hidden in the app. Best-effort — never block the install.
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
xcrun swiftc -O -parse-as-library -framework AppKit "$service_home/menubar/ProviderQuotaMenuBar.swift" -o "$binary_target"
install -m 644 "$service_home/menubar/Info.plist" "$app_target/Contents/Info.plist"
codesign --force --sign - "$app_target" >/dev/null

plutil -create xml1 "$plist_target"
plutil -insert Label -string "$label" "$plist_target"
plutil -insert ProgramArguments -array "$plist_target"
plutil -insert ProgramArguments.0 -string "$binary_target" "$plist_target"
plutil -insert RunAtLoad -bool true "$plist_target"
plutil -insert ProcessType -string Interactive "$plist_target"
plutil -insert StandardOutPath -string "$HOME/.hermes/logs/provider-quotas.log" "$plist_target"
plutil -insert StandardErrorPath -string "$HOME/.hermes/logs/provider-quotas-error.log" "$plist_target"

if launchctl print "$launch_target/$label" >/dev/null 2>&1; then
    launchctl bootout "$launch_target/$label"
    for attempt in $(seq 1 40); do
        if ! launchctl print "$launch_target/$label" >/dev/null 2>&1; then
            break
        fi
        sleep 0.25
    done
fi
launchctl bootstrap "$launch_target" "$plist_target"
