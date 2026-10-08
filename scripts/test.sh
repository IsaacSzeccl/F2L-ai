#!/usr/bin/env bash
# Runs the Swift tests (Tests/CoachCoreTests). Extra arguments go to `swift test`, e.g. --filter Placement.
#
#   F2L_LIVE_DEEPSEEK=1 scripts/test.sh   also asks DeepSeek a real follow-up question with your key.
#
# With only the Command Line Tools (Xcode's licence not yet accepted), SwiftPM doesn't load Swift Testing's
# macros by itself, so the plugin is passed explicitly.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/toolchain.sh"

DEVELOPER="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
PLUGIN="$DEVELOPER/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
EXTRA=()
if [[ "$DEVELOPER" == *CommandLineTools* && -f "$PLUGIN" ]]; then
  EXTRA=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi
swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
