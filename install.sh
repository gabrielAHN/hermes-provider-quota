#!/bin/bash
# Install the single Hermes gateway plugin this menu-bar app reads. It serves
# BOTH endpoints:
#   - /api/plugins/provider-quota/quotas    (per-provider quota)
#   - /api/plugins/provider-quota/activity  (live sessions, per provider)
# The gateway serves these; the Hermes Desktop app — and the menu-bar via the
# Desktop's gateway session — read them. Run this ON THE GATEWAY HOST (where
# `hermes` and ~/.hermes live). For a REMOTE gateway, run it there, not on the
# client Mac that only runs the menu-bar.
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
plugin_target="$HOME/.hermes/plugins/provider-quota"

if ! command -v hermes >/dev/null 2>&1 || [ ! -d "$HOME/.hermes" ]; then
    echo "Run this on the GATEWAY host (where the 'hermes' CLI and ~/.hermes live)." >&2
    echo "On a client Mac, skip it — install-menubar.sh runs it for you when a local gateway is present." >&2
    exit 1
fi

mkdir -p "$plugin_target/dashboard"
install -m 644 "$service_home/plugin.yaml" "$plugin_target/plugin.yaml"
install -m 644 "$service_home/dashboard/manifest.json" "$plugin_target/dashboard/manifest.json"
install -m 644 "$service_home/dashboard/plugin_api.py" "$plugin_target/dashboard/plugin_api.py"
rm -rf "$plugin_target/dashboard/__pycache__" 2>/dev/null || true
hermes plugins enable provider-quota >/dev/null 2>&1 || true
echo "Installed + enabled plugin: provider-quota (quotas + activity)."

# Restart the dashboard so the new routes load — auto-detect, best-effort, so a
# fresh install is a single command with no manual restart step.
restarted=""
dash_label=$(launchctl list 2>/dev/null | awk 'tolower($3) ~ /hermes.*dashboard/ {print $3; exit}')
if [ -n "${dash_label:-}" ]; then
    launchctl kickstart -k "gui/$(id -u)/$dash_label" >/dev/null 2>&1 && restarted="launchctl:$dash_label"
fi
if [ -z "$restarted" ] && hermes dashboard restart >/dev/null 2>&1; then
    restarted="hermes dashboard restart"
fi
if [ -n "$restarted" ]; then
    echo "Restarted the dashboard ($restarted) — the routes are live."
else
    echo "→ Restart the gateway dashboard to load the routes (couldn't auto-detect it)."
fi
