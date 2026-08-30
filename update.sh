#!/bin/bash
# Pull the latest from the repo this app was installed from, then reinstall the
# menu-bar app (which also refreshes the gateway plugin when a local gateway is
# present). Invoked by the menu-bar's "Check for Updates" action. Safe to run by
# hand too.
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
cd "$service_home"

git fetch --quiet origin
target="${1:-$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)}"
if [ -z "$target" ]; then
    target="origin/main"
fi
git merge --ff-only "$target"

bash "$service_home/install-menubar.sh"
