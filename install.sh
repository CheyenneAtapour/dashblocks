#!/bin/bash
# Builds Dashblocks from this repo into ~/Applications/Dashblocks.app and opens it.
#   ./install.sh           build, install and open
#   ./install.sh --login   also open it at login (a LaunchAgent)
# Safe to run again after changing the source; your blocks are kept.
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
app="$HOME/Applications/Dashblocks.app"
label="com.$USER.dashblocks"
plist="$HOME/Library/LaunchAgents/$label.plist"

command -v swiftc >/dev/null || { echo "Needs swiftc (the Xcode command line tools)." >&2; exit 1; }

echo "Building $app"
mkdir -p "$app/Contents/MacOS"
cp "$repo/support/Info.plist" "$app/Contents/Info.plist"
swiftc -O "$repo/Dashblocks.swift" -o "$app/Contents/MacOS/Dashblocks"
codesign --force -s - "$app"

# Restart it if it is running, so the new build takes over.
pkill -x Dashblocks 2>/dev/null && sleep 0.5 || true

if [ "${1:-}" = "--login" ]; then
  echo "Opening it at login ($plist)"
  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$app</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
fi

open "$app"
echo "Installed. Double-click the widget, or right-click it, to edit your blocks."
