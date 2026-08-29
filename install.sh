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

mkdir -p "$plugin_target/dashboard"
install -m 644 "$service_home/plugin.yaml" "$plugin_target/plugin.yaml"
install -m 644 "$service_home/dashboard/manifest.json" "$plugin_target/dashboard/manifest.json"
install -m 644 "$service_home/dashboard/plugin_api.py" "$plugin_target/dashboard/plugin_api.py"
rm -rf "$plugin_target/dashboard/__pycache__" 2>/dev/null || true
hermes plugins enable provider-quota >/dev/null 2>&1 || true

echo "Installed + enabled plugin: provider-quota (quotas + activity)."
echo "Restart the gateway dashboard to load the routes."
