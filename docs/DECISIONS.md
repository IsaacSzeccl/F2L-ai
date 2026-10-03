# Design decisions 

These decisions were settled in the design review of the v1 PRD (Oct 2026). Where this file and the PRD disagree, **this file wins**.

| # | Decision | Instead of (PRD v1) | Why |
|---|---|---|---|
| 1 | **A general AI-tools coach.** The learner asks anything about using ChatGPT, Gemini, Copilot and so on, and the coach answers by voice **and circles where to click**. | 3 scripted, levelled modules for one persona | A general coach gives a stronger demo; modules can come later. Mrs. Chan stays a pitch persona only. |
| 2 | **Native macOS app**, Swift + SwiftUI, with a fresh codebase that borrows [Coucou](https://github.com/louis-cfm/coucou)'s *design language* (a bar at the top or in the notch that expands on hover, with a small character). | Browser app with a mirrored view | Only a native overlay can draw on the learner's real window. Coucou's name, Mochi character, sounds and icon are not licensed for reuse, so Beacon uses its own orb character. |
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
