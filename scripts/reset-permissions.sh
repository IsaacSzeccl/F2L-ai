#!/usr/bin/env bash
# Clears Beacon's macOS permission grants so you can rehearse the first-run flow from scratch.
set -euo pipefail
for service in ScreenCapture Accessibility Microphone SpeechRecognition; do
  tccutil reset "$service" app.beacon.coach || true
done
defaults delete app.beacon.coach onboardingAccepted 2>/dev/null || true
echo "Permissions reset. Launch Beacon to see onboarding again."
