#!/usr/bin/env bash
# Builds and launches Beacon, then follows its logs (Ctrl-C stops following; Beacon keeps running).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/build-app.sh"
pkill -x Beacon 2>/dev/null || true
open "$ROOT/build/Beacon.app"
echo "Beacon is running. Following logs (latency lines show time-to-first-word)…"
log stream --style compact --predicate 'subsystem == "app.beacon.coach"'
