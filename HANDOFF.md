# F2L AI handoff

Last updated 9 October 2026. **Current checkout:** branch `f2l-secure-update` at `79b1011` (pushed), plus about 35 uncommitted changes: the first-time setup, Pip emotes, the round redesign, the debugging fixes and the cleanup. Commit them before switching branches. Development history is retained locally on `f2l-optimize`. The publication branch is `f2l-secure-update`, a reviewed snapshot based on remote `main`; the old local signing-password commits are excluded. GitHub CLI is authenticated as collaborator `SoloSolo615`, with credentials stored in the Mac keychain. See SECURITY.md for credential protections.

## 1. Goal

F2L AI is a desktop teaching companion: **Pip**, a painted lantern character, sits on top of whatever app the learner is using (mainly Excel) and teaches the next step. The owner (Charles) wants:

- Mac and Windows to behave identically, with Pip's artwork and style unchanged.
- Questions typed (or dictated) in a bar at the bottom centre of the screen; Pip's answer appearing word by word in a card beside Pip. Input and output in two different places.
- Tasks taught as short lessons, one step at a time, starting immediately (no "Let's start").
- Pip silent (words only, no voice), no emojis anywhere, no quiz.
- **The place each step is about circled accurately on screen**, in any app. Pip itself stays in its corner; only the circle moves.
- An opening animation on every launch: "F2L AI · A teaching companion", then Pip settles in its corner and asks "How can I help you?".
- **Personalised for each user:** a simple, round first-time setup, focused on work, where the user types their role and what they want help with at work and picks their AI usage level, then recommends related tools and drafts a workflow; Pip keeps the role and goal to tailor later help. Pip's own emotes, never system emoji. Original project art only.

## 2. Current state

Working on the Mac (built and checked on the owner's Mac): opening animation; first-time setup (Your work / Your AI / Your plan) and a personal greeting; bottom-centre input bar (draggable, with "Put input back at the bottom"); word-by-word reply card with Pip emotes; lessons with **Done / Show me again / I'm stuck**; Excel selection read exactly (multi-range); Excel selection steps tick themselves; new chats start empty; dictation keeps typed text; five switchable AI providers.

Resource use (measured with `F2L --soak`): 0.2–0.6% CPU and 28–37 MB while Pip rests, teaches or circles; no memory growth over 50 replies; 0.1–0.2 s and about 110 MB when a step reads the screen.

**Not solved: accurate pointing.** The owner's tests (Excel "Fill", Zoom "Unmute") still circled the wrong place or nothing. What `~/Library/Application Support/F2L/pointing.log` showed, and what was fixed:

| Test | Cause found in the log | Fixed? |
|---|---|---|
| Excel "Fill" (icon) | Accessibility off, so no control names; Fill has no visible text; nothing drawn | Now draws the AI's spot dashed and shows an **Open Settings** tip |
| Excel "Fill" | A stray OCR'd "2" near the AI's spot was circled | Screen words now match by name only |
| Zoom "Unmute" | F2L captured Zoom's small "Start Zoom AI" popup, not the meeting window | Now captures the app's main window |
| All | Accessibility permission still **off** for F2L | Owner must enable it (see next steps) |

Verification: `scripts/test.sh` runs 101 Swift tests (all pass), including parity checks that compare prompts and patterns with the C# sources. `F2L --render <dir>` renders every view (including the three setup steps, the personal greeting and Settings) and runs a real Apple Vision OCR self-test on a drawn Excel-like window (passes). `F2L --soak 10` measures CPU and memory (passes). `scripts/check-secrets.sh --all` finds no keys. **Windows has not been compiled** (no .NET SDK on this Mac); every Windows change is written to mirror the Mac but is untested.

**First-time setup (latest feature):** done on the Mac and mirrored on Windows (uncompiled). See README › "First-time setup and personalisation". Three steps: **Your work** (name optional, "What do you do at work?", "What would you like help with at work?", all typed; the kind of help is inferred by `LearnerProfile.inferFocus`), **Your AI** (three round cards for AI level, optional tools) and **Your plan**. Round design: numbered circles, pill fields and buttons, round cards. The welcome window opens once after the opening animation (or from **My learning & profile…**); the plan is made by the chosen AI from text only and restricted to `ToolCatalog`, or locally with **Plan without AI**. The plan step starts with **What do you want to learn?** (idea chips from `LearnerProfile.learningIdeas`, up to 6, plus typed topics; saved in `learning` and sent with the background). Pip then greets by name and offers those topics as buttons plus **Change what I learn**; nothing starts until one is picked. Reopened later, topic changes save immediately and the companion reloads the profile.

**Circling without being asked (9 Oct):** when the AI returns a step or reply with no target, `CoachAnswer.placesForSteps` / `placeForReply` (`Sources/CoachCore/NamedPlace.swift`, `Windows/F2L.Windows/NamedPlace.cs`) borrow the reply's target or extract the named control from the text, and `point(at:)` finds it by name (OCR, Accessibility, Excel). Owner's case: "how to change it to japan" gave a step with no target, so nothing was circled until asked.

**Menu and Settings (9 Oct):** the ··· menu is rebuilt each time it opens (New chat, My learning & profile, AI ▸ with Key added / No key yet, Share my screen, Pip size, Move Pip, Hide the input bar, Settings, Quit; Clear the highlight and Put the input bar back only when relevant). Settings (`SettingsWindow.swift` / `SettingsWindow.cs`, now code, no XAML) holds provider + key entry (`LocalSettings.setKey` / `CredentialStore.SetKey`, file mode 600 on Mac), Reduce animation, Pip walks to what it's teaching, Mac permission status with Allow… and Reset permissions, Show the settings file and Save pointing diagnostics.

**Repeated permission prompts (9 Oct):** cause was ad-hoc signed builds (agent test builds used `build-app.sh` without `SIGN_IDENTITY`, and the launcher then skipped rebuilding). `build-app.sh` now signs with *F2L Local Signing* whenever the signing keychain exists, and the launcher rebuilds an ad-hoc app. `build/F2L.app` is now signed with it. The owner may need to allow F2L once more for this signature (Settings › Reset permissions if macOS still asks). Not yet tried by the owner with a real key.

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
- `ScreenCapture.swift`: window capture (main-window choice). `Overlays.swift`: circle overlay, walking Pip. `main.swift`: launch, `--render`, `--soak`, `--export-emotes`. `SoakCheck.swift`: the resource check.
- `PersonalizeWindow.swift`: first-time setup. `Providers.swift` (CoachCore): the five AI providers.

Windows app (`Windows/F2L.Windows`, mirrors the above): `MainWindow.xaml(.cs)`, `MainWindow.Guidance.cs`, `ReplyBubbleWindow.cs`, `InputBarWindow.cs`, `IntroWindow.cs`, `TargetSnap.cs` (incl. UI Automation), `ScreenText.cs` (Windows OCR), `Lesson.cs`, `PointingLog.cs`, `CoachClient.cs`, `Providers.cs`, `GuideOverlayWindow.xaml(.cs)`, `PersonalizeWindow.cs`, `LearnerProfile.cs`, `PipEmotes.cs`. Test harness: `Windows/F2L.Windows.Tests/Program.cs`. Target framework is now `net10.0-windows10.0.19041.0` (needed for OCR); the launcher `.bat` and the shortcut script point at the new output folder.

Personalisation: `Sources/CoachCore/LearnerProfile.swift` (profile, `StarterPlan` prompt/parse/local draft, `ToolCatalog`, `ProfileStore` → `profile.json`), `Sources/F2L/PersonalizeWindow.swift` (the three-step window), `PipEmote` in `Sources/F2L/Pip.swift` (emotes; `F2L --export-emotes`), greeting in `Companion.swift` (`greet()`); Windows `LearnerProfile.cs`, `PersonalizeWindow.cs`, `PipEmotes.cs`. Art: `Assets/Pip/welcome-journey.png`, `Assets/Pip/Emotes/*.png` (listed in `docs/asset-manifest.json`, described in `Assets/Pip/ARTWORK.md`).

Tests: `Tests/CoachCoreTests/*` (Swift). Docs: `README.md`, `CHANGELOG.md`, `Windows/README.md`.

## 4. Changes made (this round)

- Multi-range Excel selection read from Excel (Mac AppleScript, Windows COM) and sent with the question.
- New chats start empty; old `conversation.json` left untouched.
- The chat panel was replaced by the bottom input bar and the reply card. The input bar is now draggable.
- Lessons: step-by-step card, auto-tick from the real Excel selection, "I'm stuck" re-asks from that step, starts at step 1.
- Opening animation every launch; Pip waving pose; Pip stays put by default ("Pip walks to what it’s teaching" in Settings re-enables walking).
- Voice output and ElevenLabs removed (dictation kept). All emojis removed, and stripped from replies.
- Pointing pipeline (`point(at:)`): Excel confirmation (Windows), then a fresh screenshot read with OCR (cell headings, control names), then Accessibility / UI Automation names, then the AI's spot drawn dashed. Each decision is logged; "Save pointing diagnostics" writes a snapshot.
- Circles instead of rectangles; the card and input bar avoid the circled spot.

### AI providers (added after the handoff was first written)

- `Sources/CoachCore/Providers.swift` / `Windows/F2L.Windows/Providers.cs`: the five providers (names, endpoints, default models, key and model setting names, user-facing messages). `CoachClient` (both apps) builds the request per provider; `LocalSettings` / `CredentialStore` read `"Provider"`, keys and `<Name>Model`.
- Only DeepSeek has been used for real; the other four are built from their documented APIs and untested with live keys. Model defaults (`gpt-5-mini`, `gemini-2.5-flash`, `claude-opus-5-5`, `glm-4.5v`) can be changed in the settings file if a provider reports 404.
- Keys stay out of Git: `.gitignore` plus `scripts/check-secrets.sh` (installed as `.git/hooks/pre-commit` on the owner's Mac; run `scripts/check-secrets.sh --install` on any new clone).

### First-time setup and personalisation

- Started by a ChatGPT session (profile model, setup window on both apps, starter-plan request, welcome art), finished here. After the owner's review it was simplified to typed, work-focused questions (role chips and focus chips removed) and redesigned round. Added: Pip emotes (6, painted from Pip's poses) on greetings, Thinking, notices, ticked steps, finished lessons and the setup window; personal greeting with the plan's first task; README / CHANGELOG / SECURITY / asset inventory and manifest updated.
- Privacy rules kept: the name is never sent; no screenshot with the plan request; background is labelled as user data, not instructions; tools only from the catalogue; `profile.json` mode 600.

### Debugging pass (9 October)

- `F2L --soak [seconds]` (`Sources/F2L/SoakCheck.swift`) measures CPU and memory per phase; idle Pip is 0.2–0.6% CPU, 28–37 MB, no growth. Ten review findings fixed (see CHANGELOG, 9 October). Don't time Vision under `timeout(1)`: the first read stalls about 30 s there only.

## 5. Failed attempts (don't repeat)

- **Trusting the AI's screenshot coordinates.** DeepSeek's boxes are often far off. Drawing them as if exact was the original "circles literally wrong" bug.
- **Drawing nothing when unconfirmed.** The owner then saw no help at all ("doesn't point nor circle").
- **Excel cell geometry on Mac from AppleScript + the AXLayoutArea frame** (`ExcelGeometry`): it needs the AI's box to choose between 72/96 dpi and header layouts, so it is unreliable. Kept only as a last resort behind OCR headings.
- **Matching OCR words by position.** A stray number got circled. OCR words are now matched by name only.
- **Capturing the frontmost window of the app.** It picked a popup (Zoom). Now the frontmost window at least half the size of the biggest.
- **End-of-lesson quiz, "Let's start" page, voice replies, emojis:** all removed at the owner's request.
- Agents cannot run `graft init` or change signing/keychain setup (blocked by permissions). The owner runs those.

## 6. Specific next steps

1. **Owner:** if macOS keeps asking even though F2L is switched on, choose **Settings › Reset permissions** (clears stale entries from older builds), then enable F2L under System Settings › Privacy & Security › **Accessibility**, reopen F2L with `Open F2L Companion.command`, and retry the Excel "Fill" and Zoom "Unmute" questions. Icon-only buttons need this.
2. If a circle is still wrong: use **Save pointing diagnostics** (in Settings) while it is on screen. Then read `~/Library/Application Support/F2L/diagnostics/<time>/report.json` and `window.jpg`, plus `pointing.log`, and fix from those facts.
3. Check from the diagnostics whether Excel for Mac exposes ribbon controls (names like "Fill Color") through Accessibility. If not, consider asking the AI a second, focused question with a crop of the area around its guess, to find icon-only buttons.
4. Run the Windows harness on a PC (`dotnet run --project Windows/F2L.Windows.Tests`) and fix compile errors. Nothing on Windows has been compiled since these changes.
5. Review `f2l-secure-update` and complete Windows validation before merging the snapshot into `main`.
6. Before later pushes, run the secret checks documented in SECURITY.md. Only DeepSeek has been tested live; verify other providers locally before relying on them.
7. **Commit** the uncommitted work on `f2l-secure-update` (run `scripts/check-secrets.sh` first; the pre-commit hook also runs it), then push when the owner agrees.
8. **Owner:** try the welcome window end to end (Pip's ··· › My learning & profile…) with a real key, pick learning topics,, and check the plan and the greeting feel right. Ideas not yet built: more emotes (sleepy, oops), a plan "progress" view, and editing the tool catalogue.
9. Optional: `npx @nanonets/graft init --agents claude --no-global` (owner) to wire graft into Claude Code; its map is already built in `graft/`.

## 7. Future improvements: pointing accuracy on cheap AIs (planned 9 Oct, not started)

Waiting on keys: the owner has no Gemini or Z.ai (GLM) key yet. Claude and ChatGPT are out of scope to keep costs low. Full plan and sources: the "F2L AI: Plan to Win the Future Work Track" doc (https://claude.ai/code/artifact/aea62e43-52c4-450c-9611-a08ebf2e6e90).

Why circles miss today: DeepSeek (`deepseek-flash`) accepts images but caps each at 1,024 tokens, so small icons shrink to a few pixels. Its docs don't mention pointing or boxes, so its box is a guess. Gemini and GLM vision models are trained to return boxes.

Cheap vision options (USD per 1M tokens in / out, checked 9 Oct 2026; prices change):

| AI | Price | Pointing |
| --- | --- | --- |
| GLM-4.6V-Flash | Free | Boxes as [x1,y1,x2,y2] on 0-1000, wrapped in `<\|begin_of_box\|>`…`<\|end_of_box\|>` |
| GLM-4.6V-FlashX | $0.04 / $0.40 | Same |
| Gemini 2.5 Flash-Lite | $0.10 / $0.40 (free tier exists) | `box_2d` as [ymin,xmin,ymax,xmax] on 0-1000 |
| GLM-4.6V | $0.30 / $0.90 | Same as GLM above, stronger |

Sources: https://docs.z.ai/guides/overview/pricing, https://ai.google.dev/gemini-api/docs/pricing, https://ai.google.dev/gemini-api/docs/image-understanding, https://api-docs.deepseek.com/guides/vision/, https://github.com/zai-org/GLM-V

Build order once a key exists (S ≈ half a day, M ≈ 1-2 days; Mac and Windows together):
1. **Pointing AI (S):** ask Gemini or GLM "where is <label>?" in its own box format. Quick win: change GLM's default model from `glm-4.5v` to `glm-4.6v` (half the price) in `Providers.swift` / `Providers.cs`.
2. **Zoom-in second look (S):** after the first guess, send a full-resolution crop around it and ask again. Small icons like Excel's Fill need this.
3. **Split the work (S):** DeepSeek writes the lesson (text); the vision AI is called only for locations.
4. **Pointing test bench (M):** score each AI on saved screenshots, using Accessibility control frames as ground truth. Gives a hit rate per AI for choosing and for the pitch.
5. **Click to continue in any app (M):** tick a step when the learner clicks inside the circle (needs a click monitor while a lesson runs).
6. **"Not there?" fix (S):** one click on the right spot corrects the circle; remember confirmed places per app locally.
7. **Livelier visuals (M):** circle draws itself, the rest of the screen dims, Pip turns to point, a small Pip celebration at the end of a lesson.

Parked (owner found them less useful): skill passport, team playbooks, reply language, offline mode.
