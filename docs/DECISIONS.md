# Design decisions 

These decisions were settled in the design review of the v1 PRD (Oct 2026). Where this file and the PRD disagree, **this file wins**.

## Current companion decisions — 8 October 2026

This section supersedes conflicting presentation and Windows implementation details in the historical sections below. See [CHANGELOG.md](../CHANGELOG.md) for the change and validation record.

- **F2L AI** (F2L) remains the product name; **Pip** is its amber lantern companion. The Mac and Windows apps are two native implementations of the same companion and must behave identically: same artwork, layout, wording, menus, conversation file and teaching rules. Shared rules exist once per platform (`Sources/CoachCore`, and the matching C# files) and the Swift tests compare them with the C# sources. Each platform reaches the desktop through its own APIs (Accessibility and ScreenCaptureKit on Mac; Win32, UI Automation and Excel automation on Windows).
- Teaching starts with the useful instruction or answer, normally one short step. Omit praise, filler and unnecessary follow-up questions. Expressions follow question type and active listening/thinking/speaking, not question length or difficulty labels.
- Use **generated painted 2D images** from the original Pip concept for the character. The current 32 poses and their generation prompts are stored in the project; shape-built character artwork is retained only in historical previews.
- Pip follows a teaching target when there is safe space, points towards it and yields to the user's pointer or caret. Guidance is click-through. Users can disable following or reduce animation, and still move/resize resting Pip.
- Dictation uses **Speak / Finish** with transcript review on both platforms; Enter sends and Shift+Enter adds a newline. Replies speak automatically unless muted. The microphone is explicitly started by the user. The push-to-talk descriptions below are historical.
- Desktop Excel cell guidance uses cell positions confirmed by Excel itself and follows source movement; a model's rectangle is never drawn over Excel. Other screenshot regions are approximate. General UI Automation targeting and reliable task-completion verification remain future work.
- Provider keys stay in a local ignored configuration file (or the keychain / Credential Manager), looked up in the same order on both platforms, with no key-entry form in the companion. A one-click launcher and optional Desktop shortcut open Pip on each platform. Screen sharing captures the selected application's visible client area on submission; foreground tracking stores window identity without background screenshots.
- Keep source artwork, prompts, font licences, reviewed previews and an asset checksum manifest inside the repository. Log behaviour changes and validation in the change log. [ASSET_INVENTORY.md](ASSET_INVENTORY.md) records locations and provenance.

## Product corrections — 7 October 2026

These explicit user decisions supersede conflicting product scope and presentation choices in the earlier table:

- The product name is **F2L**. Pip, Mori and Tiko are optional character concept names only.
- **macOS and Windows are both required platforms** for the planned release. The repository contains the Mac prototype and a runnable Windows floating companion; Windows pointing, task verification and release parity remain pending.
- The core experience is a **floating desktop companion**: a character, nearby speech bubble, on-demand question strip, and a pointer over the learner's real application. No permanent lesson sidebar, main chat window or automatic rearranging of other applications.
- Menu-bar/system-tray controls and temporary onboarding/settings windows are supporting utilities, not the main learning surface.
- Voice is two-way and explicit: push-to-talk questions, visible transcript/text, and spoken replies with stop/replay/mute controls; never an always-listening microphone. The companion's expression follows question type, not a learner-facing difficulty mode. The Windows preview now has push-to-talk and spoken replies; the Mac companion redesign and cross-platform verification remain future work.
- Follow `COMPANION_DESIGN_PLAN.md` and `COMPATIBILITY_PLAN.md` for the revised design and release gates. A runnable preview does not establish full product parity or completed learning validation.

| # | Decision | Instead of (PRD v1) | Why |
|---|---|---|---|
| 1 | **A general AI-tools coach.** The learner asks anything about using ChatGPT, Gemini, Copilot and so on, and the coach answers by voice **and circles where to click**. | 3 scripted, levelled modules for one persona | A general coach gives a stronger demo; modules can come later. Mrs. Chan stays a pitch persona only. |
| 2 | **Native macOS app**, Swift + SwiftUI, with a fresh codebase that borrows [Coucou](https://github.com/louis-cfm/coucou)'s *design language* (a bar at the top or in the notch that expands on hover, with a small character). | Browser app with a mirrored view | Only a native overlay can draw on the learner's real window. Coucou's name, Mochi character, sounds and icon are not licensed for reuse, so F2L uses its own orb character. |
| 3 | **Circle directly on the live window**, with a transparent, click-through overlay. | FR-4 mirrored view; FR-11 as a stretch goal | A mirror makes the learner look away from the app they're using. |
| 4 | **Coordinates come from macOS Accessibility**; the vision model reads context and is the fallback. | Vision LLM supplies pixel coordinates | Accessibility gives exact frames. The model picks an id from a list of real controls, so it **can't point at something that isn't there**. |
| 5 | **When Accessibility fails**, show a visibly different dashed "around here" marker, and the coach says it's approximate. | Coarse region highlight | A confident circle in the wrong place teaches a nervous learner to click the wrong thing. |
| 6 | **Chained pipeline:** Apple on-device STT → LLM (streamed) → ElevenLabs TTS (streamed per sentence), with the macOS voice as automatic fallback. | Realtime speech-to-speech API | User's choice. Streaming every stage keeps the target under 2.5 s to first word. |
| 7 | **Push-to-talk** by holding the right ⌥ Option key, or the orb. Pressing it again interrupts the coach. | Always-listening with barge-in | No echo problems; interrupting is trivial. |
| 8 | **Screen context per turn:** Accessibility controls every turn; a fresh screenshot only when the words refer to the screen; otherwise a cached one-line summary from a background vision loop that runs only when the window changes. | Separate realtime session context | Saves latency and cost on turns that don't need pixels. |
| 9 | **Proactive nudges only from Accessibility signals:** typed into the circled box and paused, sent it, or clicked the circled control. | Frame-diff vision | Cheap and reliable; doesn't talk over the learner at random moments. |
| 10 | **LLM: z.ai first**, behind one `LLMClient` protocol; Anthropic is implemented as a switch in Settings. | GPT-4o / Claude | User's choice; the week-1 spike picks the exact model ([SPIKE.md](SPIKE.md)). |
| 11 | **Privacy:** capture only the front window, never the full display; no screenshot while a password box is focused (checked right before each capture); a pause control; nothing written to disk (the spike snapshot tool is developer-mode only); the start screen names each vendor and what it receives, including the background window summaries and whether speech stays on-device. | "Processed live and not stored" | We can't promise vendors' retention, so we state what's sent and to whom. |
| 12 | **Keys in the macOS Keychain**, entered through Settings; the app runs only on team Macs for Oct 18 and Oct 24. | Not specified | Keys never go in the repo or the app binary. A hosted proxy is the "production" step for the pitch, not built now. |
| 13 | **English** demo. | English / Mandarin | Cantonese is a roadmap item, not a claim. |
| 14 | **Demo = scenes (a) + (c)** in one continuous take, with someone who has never used the app. (a): a blank ChatGPT page, "how do I start?", the coach circles the box and then Send. (c): "what's this?", and the coach explains and points. | 3-module unattended run | Pointing at the real window is the moment to show. |
| 15 | **Cut order if behind:** orb animations → Apple-voice fallback → proactive nudges. **Never cut:** the live circle and the take with an unrehearsed user. | Cut module 3 first | |

## Things the code relies on that were not verified live

These are listed in [SETUP.md](../SETUP.md), "What has and hasn't been verified": z.ai's base64 image format, z.ai and ElevenLabs data retention, and Chrome Accessibility coverage on each AI site.
