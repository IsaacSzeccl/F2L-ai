#!/usr/bin/env bash
# Builds build/F2L.app from the Swift package and signs it.
#
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/build-app.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed. That works, but macOS treats every rebuild as a
# new app and asks for Screen Recording again. See SETUP.md, step 2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/F2L.app"
ASSETS="$ROOT/Windows/F2L.Windows/Assets"

cd "$ROOT"
source "$ROOT/scripts/toolchain.sh"
swift build -c "$CONFIG" --product F2L
BIN="$(swift build -c "$CONFIG" --show-bin-path)/F2L"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Assets/Pip" "$APP/Contents/Resources/Assets/Fonts"
cp "$BIN" "$APP/Contents/MacOS/F2L"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
# Pip's artwork and fonts are shared with the Windows app; there is one copy in the repository.
cp "$ASSETS/Pip/"*.png "$ASSETS/Pip/frames.json" "$APP/Contents/Resources/Assets/Pip/"
cp "$ASSETS/Fonts/"*.ttf "$ASSETS/Fonts/LICENSE.txt" "$APP/Contents/Resources/Assets/Fonts/"

IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none \
  --entitlements "$ROOT/App/F2L.entitlements" \
  --sign "$IDENTITY" "$APP"

if [[ "$IDENTITY" == "-" ]]; then
  echo "⚠️  Ad-hoc signed. macOS may ask for Screen Recording again after each rebuild (set SIGN_IDENTITY to fix)."
fi
echo "Built $APP"
