# Beacon: a voice coach that points to where you click

*(codename: solo-level · Hack4SDG 2026, Track 4 — Future Work & Enterprises)*

Beacon is a native macOS companion for people learning to use AI tools such as ChatGPT, Gemini and Copilot.
You hold a key and ask a question out loud, and Beacon answers in a calm voice while it **draws a circle on the exact button or box in the real window**.
It points; you click.

**Setting up for the first time? Start with [SETUP.md](SETUP.md).** Design decisions are recorded in [docs/DECISIONS.md](docs/DECISIONS.md).

## Using it

| | |
|---|---|
| **Talk** | Hold the **right ⌥ Option** key (or press and hold the orb at the top of the screen) and speak; let go when you're done. |
| **Interrupt** | Press the key again while Beacon is talking. |
| **More controls** | Hover the bar at the top of the screen for Pause (stops all screen access), Clear circle, Start over, and **⋯** for Settings. |

## How it works

```
 hold ⌥ ──► Apple speech-to-text (on device) ──► transcript
                                                     │
 front window ──► Accessibility tree ──► ON-SCREEN CONTROLS (id | type | label)
              └─► ScreenCaptureKit (only if the words refer to the screen) ──► screenshot
                                                     │
                     LLM (z.ai GLM, streamed, tools: point_at / point_at_region / clear_pointer)
                         │ text, sentence by sentence           │ tool call
                         ▼                                      ▼
                ElevenLabs streaming TTS             overlay draws a ring on the AX frame
                (macOS voice if unavailable)         + TargetWatcher follows it, and nudges
                                                       when the learner types, sends or clicks
```

- **Exact pointing:** the model picks an *id* from the list of real controls, and the overlay draws on that control's Accessibility frame. An invented id is never drawn. If the control isn't in the list, the model can mark an approximate dashed "around here" region on the screenshot instead.
- **Proactive nudges:** after circling a text box, Beacon notices when you've typed and paused, or when you've sent it. After circling a button, it notices the click and moves you to the next step.
- **Privacy:** Beacon captures only the front window, takes no screenshot while a password box is focused, can be paused, and never writes the screen to disk. The start screen names every vendor and what it receives.

## Project layout

```
Package.swift
App/                      Info.plist + entitlements for the .app bundle
Sources/CoachCore/        Pure logic, unit-tested: prompts, tools, SSE decoding, z.ai/Anthropic clients,
                          geometry, sentence chunking, step tracking, spike scoring
Sources/Beacon/           The macOS app
  main.swift              App delegate, wiring
  CoachSession.swift      Orchestrator: push-to-talk → context → LLM → voice + circle
  AccessibilityReader     Reads controls from the front window (and enables Chrome's web AX tree)
  ScreenCapturer          Single-window JPEG capture via ScreenCaptureKit
  SpeechInput/Output      Apple STT; ElevenLabs PCM streaming with system-voice fallback
  Overlay / Island        Click-through annotation windows; the top-of-screen bar and orb
  TargetWatcher           Follows the circled control; emits typed/submitted/clicked events
  PushToTalk              Right-Option hold-to-talk
  Permissions / Windows   Onboarding (privacy + permissions) and Settings
  Support                 Keychain secrets, preferences, privacy copy, logging
Sources/BeaconSpike/      `beacon-spike` CLI for the week-1 model spike (docs/SPIKE.md)
Tests/CoachCoreTests/     31 tests
scripts/                  build-app.sh, run.sh, reset-permissions.sh
```

## Build, run, test

```bash
swift test                      # unit tests
./scripts/run.sh                # build build/Beacon.app, launch, follow logs
./scripts/build-app.sh          # build only (set SIGN_IDENTITY, see SETUP.md step 2)
swift run beacon-spike <dir>    # model spike
```

Beacon must run as `build/Beacon.app`; `swift run Beacon` won't work, because macOS requires an app bundle for microphone and screen permissions.
Requires macOS 15+ and Xcode 26 / Swift 6.
