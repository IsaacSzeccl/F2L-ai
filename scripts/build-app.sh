#!/usr/bin/env bash
# Builds build/Beacon.app from the Swift package and signs it.
#
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/build-app.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed. That works, but macOS treats every rebuild as a
# new app and asks for Screen Recording / Accessibility again. See SETUP.md, step 2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Beacon.app"

cd "$ROOT"
swift build -c "$CONFIG" --product Beacon
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Beacon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Beacon"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none \
  --entitlements "$ROOT/App/Beacon.entitlements" \
  --sign "$IDENTITY" "$APP"

if [[ "$IDENTITY" == "-" ]]; then
  echo "⚠️  Ad-hoc signed. Permissions will be asked again after each rebuild (set SIGN_IDENTITY to fix)."
fi
echo "Built $APP"
