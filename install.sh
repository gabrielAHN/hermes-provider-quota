#!/bin/bash
# Install the provider-quota dashboard plugin on your Hermes gateway. The
# gateway then serves /api/plugins/provider-quota/quotas, which the Hermes
# Desktop app (and the menu-bar via the Desktop's session) reads.
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
plugin_target="$HOME/.hermes/plugins/provider-quota"
target="$plugin_target/dashboard"

mkdir -p "$target"
install -m 644 "$service_home/plugin.yaml" "$plugin_target/plugin.yaml"
install -m 644 "$service_home/dashboard/manifest.json" "$target/manifest.json"
install -m 644 "$service_home/dashboard/plugin_api.py" "$target/plugin_api.py"
hermes plugins enable provider-quota >/dev/null
