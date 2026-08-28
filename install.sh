#!/bin/bash
# Install BOTH Hermes gateway dashboard plugins this menu-bar app reads:
#   - provider-quota    → /api/plugins/provider-quota/quotas      (per-provider quota)
#   - session-activity  → /api/plugins/session-activity/activity  (live sessions)
# The gateway serves these endpoints; the Hermes Desktop app — and the menu-bar
# via the Desktop's gateway session — read them. Run this ON THE GATEWAY HOST
# (where `hermes` and ~/.hermes live). For a REMOTE gateway, run it there, not on
# the client Mac that only runs the menu-bar.
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"

install_plugin() {
    local name="$1" src="$2"
    local target="$HOME/.hermes/plugins/$name"
    mkdir -p "$target/dashboard"
    install -m 644 "$src/plugin.yaml" "$target/plugin.yaml"
    install -m 644 "$src/dashboard/manifest.json" "$target/dashboard/manifest.json"
    install -m 644 "$src/dashboard/plugin_api.py" "$target/dashboard/plugin_api.py"
    rm -rf "$target/dashboard/__pycache__" 2>/dev/null || true
    hermes plugins enable "$name" >/dev/null 2>&1 || true
    echo "  installed + enabled plugin: $name"
}

# provider-quota lives at the repo root; session-activity in its own subdir.
install_plugin provider-quota   "$service_home"
install_plugin session-activity "$service_home/session-activity"

echo "Done. Restart the gateway dashboard to load the routes (e.g. re-run"
echo "\`hermes dashboard\`, or kickstart its launch agent)."
