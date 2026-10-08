# F2L AI handoff

Last updated 8 October 2026. Development checkout: `f2l-optimize`. The GitHub publication uses `f2l-secure-update`, a reviewed snapshot based on remote `main`; the old local signing-password commits are excluded. See SECURITY.md for credential protections.

## 1. Goal

F2L AI is a desktop teaching companion: **Pip**, a painted lantern character, sits on top of whatever app the learner is using (mainly Excel) and teaches the next step. The owner (Charles) wants:

- Mac and Windows to behave identically, with Pip's artwork and style unchanged.
- Questions typed (or dictated) in a bar at the bottom centre of the screen; Pip's answer appearing word by word in a card beside Pip. Input and output in two different places.
- Tasks taught as short lessons, one step at a time, starting immediately (no "Let's start").
- Pip silent (words only, no voice), no emojis anywhere, no quiz.
- **The place each step is about circled accurately on screen**, in any app. Pip itself stays in its corner; only the circle moves.
- An opening animation on every launch: "F2L AI · A teaching companion", then Pip settles in its corner and asks "How can I help you?".

## 2. Current state

Working on the Mac (built and checked on the owner's Mac): opening animation; bottom-centre input bar (draggable, with "Put input back at the bottom"); word-by-word reply card; lessons with **Done / Show me again / I'm stuck**; Excel selection read exactly (multi-range); Excel selection steps tick themselves; new chats start empty; dictation keeps typed text.

**Not solved: accurate pointing.** The owner's tests (Excel "Fill", Zoom "Unmute") still circled the wrong place or nothing. What `~/Library/Application Support/F2L/pointing.log` showed, and what was fixed:

| Test | Cause found in the log | Fixed? |
|---|---|---|
| Excel "Fill" (icon) | Accessibility off, so no control names; Fill has no visible text; nothing drawn | Now draws the AI's spot dashed and shows an **Open Settings** tip |
| Excel "Fill" | A stray OCR'd "2" near the AI's spot was circled | Screen words now match by name only |
| Zoom "Unmute" | F2L captured Zoom's small "Start Zoom AI" popup, not the meeting window | Now captures the app's main window |
| All | Accessibility permission still **off** for F2L | Owner must enable it (see next steps) |

Verification: `scripts/test.sh` runs 81 Swift tests (all pass), including parity checks that compare prompts and patterns with the C# sources. `F2L --render <dir>` renders every view and runs a real Apple Vision OCR self-test on a drawn Excel-like window (passes). **Windows has not been compiled** (no .NET SDK on this Mac); every Windows change is written to mirror the Mac but is untested.

## 3. Active files

Shared logic (Swift, `Sources/CoachCore`, tested):
- `CoachClient.swift`: prompt (reply / steps with per-step targets / target), parsing, `CoachAnswer`.
- `TargetSnap.swift`: matching a label to real controls, the circle shape, Excel geometry from metrics.
- `ScreenText.swift`: OCR word groups, finding a cell from column letters and row numbers.
- `Lesson.swift`: `StepCheck` (does Excel's selection complete a step).
- `ExcelContext.swift`, `ReplyPhrases.swift`, `Conversation.swift` (per-session files), `CompanionPlacement.swift` (Pip poses incl. waving).

Mac app (`Sources/F2L`):
- `Companion.swift`: controller; `point(at:)` is the pointing pipeline.
- `ReplyBubble.swift`: the reply/lesson card. `Intro.swift`: opening animation.
- `ScreenReading.swift`: Apple Vision OCR plus its render self-test. `Accessibility.swift`: control lookup.
- `ExcelSelectionReader.swift`: AppleScript for selection and cell metrics. `PointingDiagnostics.swift`: pointing log and "Save pointing diagnostics".
- `ScreenCapture.swift`: window capture (main-window choice). `Overlays.swift`: circle overlay, walking Pip. `main.swift`: launch and render check.

Windows app (`Windows/F2L.Windows`, mirrors the above): `MainWindow.xaml(.cs)`, `MainWindow.Guidance.cs`, `ReplyBubbleWindow.cs`, `InputBarWindow.cs`, `IntroWindow.cs`, `TargetSnap.cs` (incl. UI Automation), `ScreenText.cs` (Windows OCR), `Lesson.cs`, `PointingLog.cs`, `CoachClient.cs`, `GuideOverlayWindow.xaml(.cs)`. Test harness: `Windows/F2L.Windows.Tests/Program.cs`. Target framework is now `net10.0-windows10.0.19041.0` (needed for OCR); the launcher `.bat` and the shortcut script point at the new output folder.

Tests: `Tests/CoachCoreTests/*` (Swift). Docs: `README.md`, `CHANGELOG.md`, `Windows/README.md`.

## 4. Changes made (this round)

- Multi-range Excel selection read from Excel (Mac AppleScript, Windows COM) and sent with the question.
- New chats start empty; old `conversation.json` left untouched.
- The chat panel was replaced by the bottom input bar and the reply card. The input bar is now draggable.
- Lessons: step-by-step card, auto-tick from the real Excel selection, "I'm stuck" re-asks from that step, starts at step 1.
- Opening animation every launch; Pip waving pose; Pip stays put by default ("Pip follows teaching targets" re-enables walking).
- Voice output and ElevenLabs removed (dictation kept). All emojis removed, and stripped from replies.
- Pointing pipeline (`point(at:)`): Excel confirmation (Windows), then a fresh screenshot read with OCR (cell headings, control names), then Accessibility / UI Automation names, then the AI's spot drawn dashed. Each decision is logged; "Save pointing diagnostics" writes a snapshot.
- Circles instead of rectangles; the card and input bar avoid the circled spot.

### AI providers (added after the handoff was first written)

- `Sources/CoachCore/Providers.swift` / `Windows/F2L.Windows/Providers.cs`: the five providers (names, endpoints, default models, key and model setting names, user-facing messages). `CoachClient` (both apps) builds the request per provider; `LocalSettings` / `CredentialStore` read `"Provider"`, keys and `<Name>Model`.
- Only DeepSeek has been used for real; the other four are built from their documented APIs and untested with live keys. Model defaults (`gpt-5-mini`, `gemini-2.5-flash`, `claude-opus-5-5`, `glm-4.5v`) can be changed in the settings file if a provider reports 404.
- Keys stay out of Git: `.gitignore` plus `scripts/check-secrets.sh` (installed as `.git/hooks/pre-commit` on the owner's Mac; run `scripts/check-secrets.sh --install` on any new clone).

## 5. Failed attempts (don't repeat)

- **Trusting the AI's screenshot coordinates.** DeepSeek's boxes are often far off. Drawing them as if exact was the original "circles literally wrong" bug.
- **Drawing nothing when unconfirmed.** The owner then saw no help at all ("doesn't point nor circle").
- **Excel cell geometry on Mac from AppleScript + the AXLayoutArea frame** (`ExcelGeometry`): it needs the AI's box to choose between 72/96 dpi and header layouts, so it is unreliable. Kept only as a last resort behind OCR headings.
- **Matching OCR words by position.** A stray number got circled. OCR words are now matched by name only.
- **Capturing the frontmost window of the app.** It picked a popup (Zoom). Now the frontmost window at least half the size of the biggest.
- **End-of-lesson quiz, "Let's start" page, voice replies, emojis:** all removed at the owner's request.
- Agents cannot run `graft init` or change signing/keychain setup (blocked by permissions). The owner runs those.

## 6. Specific next steps

1. **Owner:** if macOS keeps asking even though F2L is switched on, choose **Fix permissions…** in Pip's ··· menu (clears stale entries from older builds), then enable F2L under System Settings › Privacy & Security › **Accessibility**, reopen F2L with `Open F2L Companion.command`, and retry the Excel "Fill" and Zoom "Unmute" questions. Icon-only buttons need this.
2. If a circle is still wrong: use **Save pointing diagnostics** (Pip's ··· menu) while it is on screen. Then read `~/Library/Application Support/F2L/diagnostics/<time>/report.json` and `window.jpg`, plus `pointing.log`, and fix from those facts.
3. Check from the diagnostics whether Excel for Mac exposes ribbon controls (names like "Fill Color") through Accessibility. If not, consider asking the AI a second, focused question with a crop of the area around its guess, to find icon-only buttons.
4. Run the Windows harness on a PC (`dotnet run --project Windows/F2L.Windows.Tests`) and fix compile errors. Nothing on Windows has been compiled since these changes.
5. Review the published `f2l-secure-update` snapshot before merging it into `main`.
6. Before later pushes, run the secret checks documented in SECURITY.md. Only DeepSeek has been tested live; verify other providers locally before relying on them.
7. Optional: `npx @nanonets/graft init --agents claude --no-global` (owner) to wire graft into Claude Code; its map is already built in `graft/`.
