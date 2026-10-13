#!/usr/bin/env bash
# Builds build/F2L.app from the Swift package and signs it.
#
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/build-app.sh
#
# Without SIGN_IDENTITY it uses F2L's private certificate (scripts/setup-signing.sh), or else signs ad-hoc. Ad-hoc
# works, but macOS treats every rebuild as a new app and asks for Screen Recording again. See SETUP.md, step 2.
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Assets/Pip" "$APP/Contents/Resources/Assets/Fonts" "$APP/Contents/Resources/Assets/Knowledge"
cp "$BIN" "$APP/Contents/MacOS/F2L"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
# Pip's artwork and fonts are shared with the Windows app; there is one copy in the repository.
cp "$ASSETS/Pip/"*.png "$ASSETS/Pip/frames.json" "$APP/Contents/Resources/Assets/Pip/"
cp "$ASSETS/Fonts/"*.ttf "$ASSETS/Fonts/LICENSE.txt" "$APP/Contents/Resources/Assets/Fonts/"
# The AI tools library Pip teaches and recommends from (shared with Windows).
cp "$ASSETS/Knowledge/ai-tools.json" "$APP/Contents/Resources/Assets/Knowledge/"
# Original brand masters and illustrations are shared by both desktop hosts.
mkdir -p "$APP/Contents/Resources/Assets/Brand" "$APP/Contents/Resources/Assets/Illustrations"
# app-icon.png is only the master for F2L.icns, so it stays out of the app.
cp "$ASSETS/Brand/learning-doorway.png" "$ASSETS/Brand/launch-landscape.png" "$APP/Contents/Resources/Assets/Brand/"
cp "$ASSETS/Illustrations/"*.png "$APP/Contents/Resources/Assets/Illustrations/"
cp "$ASSETS/Brand/F2L.icns" "$APP/Contents/Resources/F2L.icns"

# Every build (the launcher, run.sh or a check) uses F2L's private certificate once scripts/setup-signing.sh has made
# one. An ad-hoc build looks like a new app to macOS, which then asks for Screen Recording and Accessibility again
# even though they are switched on.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  source "$ROOT/scripts/local-signing.sh"
  if f2l_signing_ready >/dev/null 2>&1; then SIGN_IDENTITY="$F2L_SIGNING_NAME"; fi
fi
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none \
  --entitlements "$ROOT/App/F2L.entitlements" \
  --sign "$IDENTITY" "$APP"

if [[ "$IDENTITY" == "-" ]]; then
  echo "⚠️  Ad-hoc signed. macOS may ask for Screen Recording again after each rebuild (set SIGN_IDENTITY to fix)."
fi
echo "Built $APP"
