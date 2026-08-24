#!/bin/bash
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
target="$HOME/.hermes/desktop-plugins/provider-quota"

mkdir -p "$target"
install -m 644 "$service_home/desktop/plugin.js" "$target/plugin.js"
