#!/usr/bin/env bash
# Builds and launches F2L, then follows its logs (Ctrl-C stops following; F2L keeps running).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/build-app.sh"
pkill -x F2L 2>/dev/null || true
open "$ROOT/build/F2L.app"
echo "F2L is running. Following logs…"
log stream --style compact --predicate 'subsystem == "ai.f2l.companion"'
