#!/bin/bash
set -euo pipefail

service_home="$(cd "$(dirname "$0")" && pwd)"
app_target="$HOME/Applications/Provider Quotas.app"
binary_target="$app_target/Contents/MacOS/ProviderQuotaMenuBar"
plist_target="$HOME/Library/LaunchAgents/io.github.gabrielahn.provider-quotas.plist"
launch_target="gui/$(id -u)"
label="io.github.gabrielahn.provider-quotas"

mkdir -p "$app_target/Contents/MacOS" "$HOME/Library/LaunchAgents" "$HOME/.hermes/logs" "$HOME/.local/bin"
# Data source: the Hermes Desktop app's gateway API (see desktop-quotas.sh).
install -m 755 "$service_home/desktop-quotas.sh" "$HOME/.local/bin/hermes-desktop-quotas"
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
