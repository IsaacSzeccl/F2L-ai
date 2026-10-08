#!/usr/bin/env bash
# Python 3 is required. Findings contain paths/rules only, never credential values.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/check_secrets.py" "$@"
