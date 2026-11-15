#!/bin/bash
# Build Gemstok HQ (release) and install it in /Applications — like any other app.
# Run from the gemstok_hq folder:   ./tool/install.sh
set -e
cd "$(dirname "$0")/.."

echo "▶ Building…"
flutter build macos --release

APP="build/macos/Build/Products/Release/Gemstok HQ.app"
if [ ! -d "$APP" ]; then echo "✗ Build finished but $APP isn't there — send this to Claude."; exit 1; fi

echo "▶ Closing Gemstok HQ if it's open…"
osascript -e 'tell application id "com.gemstok.gemstokHq" to quit' 2>/dev/null || true
sleep 1

echo "▶ Installing to /Applications/Gemstok HQ.app…"
rsync -a --delete "$APP/" "/Applications/Gemstok HQ.app/"

echo "▶ Opening…"
open "/Applications/Gemstok HQ.app"
echo "✓ Done. Find it with ⌘ Space → \"Gemstok HQ\"."
