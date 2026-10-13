#!/usr/bin/env bash
# Clears F2L's macOS permission grants so you can rehearse the first-run flow from scratch.
set -euo pipefail
for service in ScreenCapture Microphone SpeechRecognition Accessibility AppleEvents; do
  tccutil reset "$service" ai.f2l.companion || true
done
echo "Permissions reset. Launch F2L to be asked again."
