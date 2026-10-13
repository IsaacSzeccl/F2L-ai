#!/usr/bin/env bash
# Sourced by the other scripts. If Xcode is selected but its licence hasn't been accepted, Swift
# commands fail; fall back to the Command Line Tools, which can build F2L (it uses AppKit only).
if ! xcrun --find swift >/dev/null 2>&1 || ! xcrun swift --version >/dev/null 2>&1; then
  if [[ -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    echo "ℹ️  Using the Command Line Tools (Xcode isn't usable yet; 'sudo xcodebuild -license accept' fixes that)." >&2
  else
    echo "❌ No Swift toolchain found. Install Xcode or run: xcode-select --install" >&2
    exit 1
  fi
fi
