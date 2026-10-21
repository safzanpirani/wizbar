#!/usr/bin/env bash
# Builds build/WizBar.app. With --install, replaces ~/Applications/WizBar.app
# and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/WizBar"

APP=build/WizBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WizBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier dev.safzan.wizbar "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x WizBar 2>/dev/null && sleep 0.5 || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/WizBar.app"
  cp -R "$APP" "$HOME/Applications/WizBar.app"
  open "$HOME/Applications/WizBar.app"
  echo "installed ~/Applications/WizBar.app"
fi
