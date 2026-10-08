#!/usr/bin/env bash
# Double-click to open Pip on a Mac. Builds F2L.app the first time, and again whenever the code changes.
# Windows equivalent: "Open F2L Companion.bat".  Add --install-shortcut to put "F2L Companion" on the Desktop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/F2L.app"
cd "$ROOT"

# Sign with F2L's private certificate when scripts/setup-signing.sh has made one, so macOS keeps F2L's permissions.
if [[ -z "${SIGN_IDENTITY:-}" && -f "$HOME/Library/Application Support/F2L/Signing/F2L-signing.keychain-db" ]]; then
  export SIGN_IDENTITY="F2L Local Signing"
fi

# Rebuild only for real changes (Finder's .DS_Store files don't count): a rebuild can make macOS ask for permissions again.
if [[ ! -x "$APP/Contents/MacOS/F2L" ]] || [[ -n "$(find Sources App Package.swift Windows/F2L.Windows/Assets -newer "$APP/Contents/MacOS/F2L" -type f ! -name .DS_Store -print -quit)" ]]; then
  echo "Building F2L (first run or code changed)…"
  "$ROOT/scripts/build-app.sh"
fi

if [[ "${1:-}" == "--install-shortcut" ]]; then
  ln -sfn "$APP" "$HOME/Desktop/F2L Companion.app"
  echo "Added 'F2L Companion' to your Desktop."
fi

open "$APP"
echo "Pip is open. You can close this window."
