# F2L AI handoff

Last updated 11 October 2026. **Current checkout:** branch `f2l-secure-update` at `d32925c` (the owner's commit of the setup, emotes and pointing work), plus uncommitted work from 11 October: the AI tools library, steps that finish by themselves, the zoomed second look, faster screen reading, the playful idle animations, the original brand artwork and the code split described below. Run `scripts/check-secrets.sh` and commit with `git add -A` (two Windows Settings XAML files were deleted). Development history is retained locally on `f2l-optimize`. GitHub CLI is authenticated as collaborator `SoloSolo615`, with credentials stored in the Mac keychain. See SECURITY.md for credential protections.

## 1. Goal

F2L AI is a desktop teaching companion: **Pip**, a painted lantern character, sits on top of whatever app the learner is using and teaches people to set up and use AI tools and work apps (ChatGPT, Gemini, Notion, Google Workspace, n8n, Excel and more), one step at a time. The owner (Charles) wants:

- Mac and Windows to behave identically, with Pip's artwork and style unchanged.
- Questions typed (or dictated) in a bar at the bottom centre of the screen; Pip's answer appearing word by word in a card beside Pip. Input and output in two different places.
- Tasks taught as short lessons, one step at a time, starting immediately (no "Let's start").
- Pip silent (words only, no voice), no emojis anywhere, no quiz.
- **The place each step is about circled accurately on screen**, in any app. Pip itself stays in its corner; only the circle moves.
- An opening animation on every launch: "F2L AI · A teaching companion", then Pip settles in its corner and asks "How can I help you?".
- **Its own visual identity beyond the mascot:** a book-and-doorway emblem, app icon, painted dusk launch backdrop, setup illustrations, experience badges and a Settings compass, in teal, sage, amber, ivory and dark plum (11 Oct).
- **Pip lively but never in the way:** resting blinks plus 16 painted playful poses (wink, dance, stretch, peekaboo) every 12 seconds or so; anything active takes priority.
- **Steps that finish by themselves** when F2L sees them happen, with Done as the fallback; cheap AI (DeepSeek by default, no Claude or ChatGPT costs).
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

Verification: `scripts/test.sh` runs 127 Swift tests (all pass), including parity checks that compare prompts and patterns with the C# sources. `F2L --render <dir>` renders every view (including the three setup steps, the personal greeting and Settings) and runs a real Apple Vision OCR self-test on a drawn Excel-like window (passes). `F2L --soak 10` measures CPU and memory (passes). `scripts/check-secrets.sh --all` finds no keys. **Windows has not been compiled** (no .NET SDK on this Mac); every Windows change is written to mirror the Mac but is untested.

**First-time setup (latest feature):** done on the Mac and mirrored on Windows (uncompiled). See README › "First-time setup and personalisation". Three steps: **Your work** (name optional, "What do you do at work?", "What would you like help with at work?", all typed; the kind of help is inferred by `LearnerProfile.inferFocus`), **Your AI** (three round cards for AI level, optional tools) and **Your plan**. Round design: numbered circles, pill fields and buttons, round cards. The welcome window opens once after the opening animation (or from **My learning & profile…**); the plan is made by the chosen AI from text only and restricted to `ToolCatalog`, or locally with **Plan without AI**. The plan step starts with **What do you want to learn?** (idea chips from `LearnerProfile.learningIdeas`, up to 6, plus typed topics; saved in `learning` and sent with the background). Pip then greets by name and offers those topics as buttons plus **Change what I learn**; nothing starts until one is picked. Reopened later, topic changes save immediately and the companion reloads the profile.

**Original brand artwork (11 Oct, reviewed):** ten generated pictures integrated into the opening, the three setup steps, the experience cards and Settings, plus the app icons. Review fixes: pictures decoded at the size shown instead of 1254 px, the launch backdrop and Pip's glow moved to layers and freed after the opening (peak 316 → about 180 MB), the icon master kept out of both apps. The opening still costs about 17% of one core for six seconds, as before. At 16 px the icon is mostly its dark plate; a simpler small-size variant is a nice-to-have.

**Playful idle animations and code layout (11 Oct):** the owner added `playful.png` (16 poses: wink, dance, yawn and stretch, peekaboo) with `PipPose.playfulFrame` / `PipView.PlayfulFrame`. Checked: same scale and baseline as the other atlases, timings identical on both apps (parity test), and Pip now returns to its resting face (`.quickFact`) whenever the card closes (`ReplyBubble.onDismiss` / `ReplyBubbleWindow.Dismissed`), otherwise a finished lesson left Pip in its working pose and the playful moves never started. The Mac companion and the Windows MainWindow were split by job into Pointing, Lesson and Menu files.

**Review and upgrades (11 Oct):** batched and pruned Accessibility walk (`DesktopAccessibility.walk`), Electron apps asked to build their tree (`AXManualAccessibility`), screen names read in parallel with a 0.6 s control budget, UI Automation cache requests on Windows, typing steps ignore Pip's own box, and `ZoomLocate` (`Sources/CoachCore/ZoomLocate.swift`, `Windows/F2L.Windows/ZoomLocate.cs`) for places the screen can't confirm.

**Steps that finish by opening an app or site (11 Oct):** `StepGoal` (`Sources/CoachCore/StepGoal.swift`, `Windows/F2L.Windows/StepGoal.cs`) + `checkGoal()` / `CheckGoal()` in the lesson poll tick browser, app and site steps from the front app's name and window title. `point(at:)` / `PointAt` look in the current app by name when the step's app differs from the original screenshot.

**AI tools library, held keys, typing (11 Oct):** `Windows/F2L.Windows/Assets/Knowledge/ai-tools.json` (68 tools) is read by `AIToolLibrary` (`Sources/CoachCore/AIToolLibrary.swift`, `Windows/F2L.Windows/AIToolLibrary.cs`, embedded as `ai-tools.json`). `ToolCatalog` is now built from it (`common` = welcome chips). `compose(..., library:)` / `ExcelContext.Compose(..., library)` add tool notes and recommendations. `ClickWatch.requiredKeys` / `isTypingStep` and `TypingWatch` (fingerprint only) tick held-key and typing steps. Library entries are stable facts from 11 Oct 2026; refresh them before a demo.

**Click to continue, screen names, warmer steps (11 Oct):** `ClickWatch` (`Sources/CoachCore/ClickWatch.swift`, `Windows/F2L.Windows/ClickWatch.cs`) polls the mouse button while a place is circled (Mac `NSEvent.pressedMouseButtons`, Windows `GetAsyncKeyState`); a press inside the circle calls `clickedTarget()` / `ClickedTarget()` on the reply card. `ScreenNames` sends up to 80 control and OCR names with each question. `TeachingReply.style` rewritten for detailed, warm steps. This covers items 5 and part of 1 in section 7.

**Any tool, not just Excel (11 Oct):** the teaching prompt (both apps, parity-tested) now frames F2L as a coach for AI tools and work apps, teaches a tool that isn't open from where the learner is, and never refuses because another app is in front; `compose(..., app:)` / `ExcelContext.Compose(..., app)` add "The screenshot shows <app>." Learning ideas lean to AI tools.

**Circling without being asked (9 Oct):** when the AI returns a step or reply with no target, `CoachAnswer.placesForSteps` / `placeForReply` (`Sources/CoachCore/NamedPlace.swift`, `Windows/F2L.Windows/NamedPlace.cs`) borrow the reply's target or extract the named control from the text, and `point(at:)` finds it by name (OCR, Accessibility, Excel). Owner's case: "how to change it to japan" gave a step with no target, so nothing was circled until asked.

**Menu and Settings (9 Oct):** the ··· menu is rebuilt each time it opens (New chat, My learning & profile, AI ▸ with Key added / No key yet, Share my screen, Pip size, Move Pip, Hide the input bar, Settings, Quit; Clear the highlight and Put the input bar back only when relevant). Settings (`SettingsWindow.swift` / `SettingsWindow.cs`, now code, no XAML) holds provider + key entry (`LocalSettings.setKey` / `CredentialStore.SetKey`, file mode 600 on Mac), Reduce animation, Pip walks to what it's teaching, Mac permission status with Allow… and Reset permissions, Show the settings file and Save pointing diagnostics.

**Repeated permission prompts (9 Oct):** cause was ad-hoc signed builds (agent test builds used `build-app.sh` without `SIGN_IDENTITY`, and the launcher then skipped rebuilding). `build-app.sh` now signs with *F2L Local Signing* whenever the signing keychain exists, and the launcher rebuilds an ad-hoc app. `build/F2L.app` is now signed with it. The owner may need to allow F2L once more for this signature (Settings › Reset permissions if macOS still asks). Not yet tried by the owner with a real key.

## 3. Active files

Shared rules (Swift, `Sources/CoachCore`, tested; every file has a C# twin of the same name in `Windows/F2L.Windows`, and `ParityTests` reads the C# to keep prompts, patterns and timings identical):
- `CoachClient.swift` (request per provider, teaching prompt, reply parsing, `compose` with app name, screen names and tool notes), `Providers.swift`, `TeachingReply.swift` (reply style), `LocalSettings.swift` (keys and settings).
- `AIToolLibrary.swift`: the 68-tool library (`Windows/F2L.Windows/Assets/Knowledge/ai-tools.json`), tool notes and recommendations. `LearnerProfile.swift`: profile, starter plan, learning topics, `ToolCatalog`, `ProfileStore`.
- Finding places: `NamedPlace.swift` (a step's place by name), `TargetSnap.swift` (matching labels to controls, the circle), `ScreenText.swift` (OCR words, Excel cells), `ZoomLocate.swift` (zoomed second look), `CellReference.swift`.
- Steps finishing by themselves: `ClickWatch.swift` (click, held keys, typing, `ScreenNames`), `StepGoal.swift` (app or site in front), `Lesson.swift` (`StepCheck` for Excel selections).
- `CompanionPlacement.swift`: where Pip, the card and the input bar sit, and `PipPose` (all poses, including `playfulFrame` for the idle animations). `Conversation.swift`, `ExcelContext.swift`, `ReplyPhrases.swift`, `QuestionIntent.swift`.

Mac app (`Sources/F2L`):
- `Companion.swift` (state, layout, input bar, a question's round trip, dictation, saving), `CompanionPointing.swift` (`point(at:)`: the pointing pipeline, highlights), `CompanionLesson.swift` (click, typing and goal watching), `CompanionMenu.swift` (··· menu, Settings, profile window, permissions).
- `ReplyBubble.swift` (card and lessons), `Pip.swift` (sprites from three atlases, `PipView`, `PipEmote`), `Intro.swift`, `PersonalizeWindow.swift`, `SettingsWindow.swift`, `Overlays.swift` (circle overlay, walking Pip), `Controls.swift`, `Theme.swift`, `Composer.swift`, `Voice.swift`.
- Reading the screen: `Accessibility.swift` (batched, pruned control walk; focused-box fingerprint), `ScreenCapture.swift` (window pictures, crops, window titles), `ScreenReading.swift` (Apple Vision OCR), `ExcelSelectionReader.swift`, `PointingDiagnostics.swift`.
- `BrandArtwork.swift`: the brand pictures, decoded once at the size shown (squares at most 512 px), the launch backdrop freed after the opening.
- `main.swift` (launch, `--render`, `--soak`, `--export-emotes`; checks keep their windows out of sight), `SoakCheck.swift` (now also measures the opening).

Windows app (`Windows/F2L.Windows`, mirrors the above): `MainWindow.xaml.cs` plus `MainWindow.Pointing.cs`, `MainWindow.Lesson.cs`, `MainWindow.Menu.cs`, `MainWindow.Guidance.cs`; `ReplyBubbleWindow.cs`, `InputBarWindow.cs`, `IntroWindow.cs`, `PipView.xaml.cs`, `PipSprites.cs`, `SettingsWindow.cs` (code, no XAML), `PersonalizeWindow.cs`, `BrandArtwork.cs`, `NativeDesktop.cs`, `ScreenCaptureService.cs`, `PointingLog.cs`, `GuideOverlayWindow.xaml(.cs)`. Test harness: `Windows/F2L.Windows.Tests/Program.cs`. Target framework `net10.0-windows10.0.19041.0` (needed for OCR). **Not compiled since 8 October.**

Art and data (`Windows/F2L.Windows/Assets`, used by both apps): `Pip/expressions.png`, `Pip/directions.png`, `Pip/playful.png` (16 idle poses, 11 Oct), `Pip/frames.json` (rectangles; regenerate with `python3 scripts/tools/pip_frames.py`), `Pip/Emotes/`, `Pip/welcome-journey.png`, `Fonts/`, `Knowledge/ai-tools.json`. `Brand/` (emblem `learning-doorway.png`, `launch-landscape.png`, `app-icon.png` master, `F2L.icns`, `F2L.ico`, `ARTWORK.md` with the generation prompts) and `Illustrations/` (setup scenes, experience badges, Settings compass); board at `docs/previews/f2l-brand-board.png`; repackage icons with `python3 scripts/tools/package_brand_icons.py`. Every file is listed with its hash in `docs/asset-manifest.json` (checked by `scripts/verify-assets.ps1`). `swift scripts/tools/preview_pip.swift` writes looping GIFs of the playful poses to `build/pip-previews/`.

Tests: `Tests/CoachCoreTests/*` (127 Swift tests). Docs: `README.md`, `CHANGELOG.md`, `SECURITY.md`, `SETUP.md`, `Windows/README.md`.

## 4. Changes made (8–11 October; details in CHANGELOG.md)

- Multi-range Excel selection read from Excel (Mac AppleScript, Windows COM) and sent with the question.
- New chats start empty; old `conversation.json` left untouched.
- The chat panel was replaced by the bottom input bar and the reply card. The input bar is now draggable.
- Lessons: step-by-step card, auto-tick from the real Excel selection, "I'm stuck" re-asks from that step, starts at step 1.
- Opening animation every launch; Pip waving pose; Pip stays put by default ("Pip walks to what it’s teaching" in Settings re-enables walking).
- Voice output and ElevenLabs removed (dictation kept). All emojis removed, and stripped from replies.
- Pointing pipeline (`point(at:)` in `CompanionPointing.swift`, `PointAt` in `MainWindow.Pointing.cs`): Excel confirmation (Windows), then a fresh screenshot read with OCR (cell headings, control names), then Accessibility / UI Automation names, then a zoomed second look by the AI, then the AI's spot drawn dashed. Each decision is logged; "Save pointing diagnostics" (Settings) writes a snapshot.
- Circles instead of rectangles; the card and input bar avoid the circled spot.

### AI providers (added after the handoff was first written)

- `Sources/CoachCore/Providers.swift` / `Windows/F2L.Windows/Providers.cs`: the five providers (names, endpoints, default models, key and model setting names, user-facing messages). `CoachClient` (both apps) builds the request per provider; `LocalSettings` / `CredentialStore` read `"Provider"`, keys and `<Name>Model`.
- Only DeepSeek has been used for real; the other four are built from their documented APIs and untested with live keys. Model defaults (`gpt-5-mini`, `gemini-2.5-flash`, `claude-opus-5-5`, `glm-4.6v`) can be changed in the settings file if a provider reports 404.
- Keys stay out of Git: `.gitignore` plus `scripts/check-secrets.sh` (installed as `.git/hooks/pre-commit` on the owner's Mac; run `scripts/check-secrets.sh --install` on any new clone).

### First-time setup and personalisation

- Started by a ChatGPT session (profile model, setup window on both apps, starter-plan request, welcome art), finished here. After the owner's review it was simplified to typed, work-focused questions (role chips and focus chips removed) and redesigned round. Added: Pip emotes (6, painted from Pip's poses) on greetings, Thinking, notices, ticked steps, finished lessons and the setup window; a personal greeting that offers the topics the learner chose to learn (nothing starts until they pick one); README / CHANGELOG / SECURITY / asset inventory and manifest updated.
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
3. Retry the Excel "Fill" question: the zoomed second look (11 Oct) should now land on icon-only buttons; check `pointing.log` for `model-zoom` or `zoom+accessibility`.
4. **Owner:** look at the opening on the smallest screen you'll demo on (the wordmark scales down below 850 × 560 points; the backdrop fills any shape), and at the icon in the Dock and Finder.
5. Run the Windows harness on a PC (`dotnet run --project Windows/F2L.Windows.Tests`) and fix compile errors. Nothing on Windows has been compiled since 8 October.
6. Review `f2l-secure-update` and complete Windows validation before merging the snapshot into `main`.
7. Before later pushes, run the secret checks documented in SECURITY.md. Only DeepSeek has been tested live; verify other providers locally before relying on them.
8. **Commit** the uncommitted work on `f2l-secure-update` (run `scripts/check-secrets.sh` first; the pre-commit hook also runs it), then push when the owner agrees.
9. **Owner:** try the welcome window end to end (Pip's ··· › My learning & profile…) with a real key, pick learning topics, and check the plan and the greeting feel right. Ideas not yet built: more emotes (sleepy, oops), a plan "progress" view, and editing the tool catalogue.
10. Optional: `npx @nanonets/graft init --agents claude --no-global` (owner) to wire graft into Claude Code; its map is already built in `graft/`.

## 7. Future improvements (review of 11 Oct; earlier plan of 9 Oct folded in)

Done since the 9 Oct plan: click to continue in any app, held keys and typing steps, steps that finish by opening an app or site, the AI tools library, and a **zoomed second look** with whatever AI is selected (DeepSeek works: on a live test with 22-pt icons it was off by 11–12 pt zoomed against 35–44 pt, the wrong icon, across the whole window). GLM's default is now `glm-4.6v` (half the price of 4.5v).

Measured on 11 Oct (Mac): idle and teaching 0.4–0.8% CPU; one batched Accessibility request per element is 2–3x faster than one attribute at a time with the same names found (Finder 0.14 s → 0.05 s, Chrome 0.08 s → 0.04 s); a window read by OCR 0.08–0.2 s; a zoomed look about 1.8 s and roughly 1.1k input tokens on DeepSeek, only when a place can't be confirmed. The playful animation's third atlas adds about 8 MB.

Next, in order of payoff (S ≈ half a day, M ≈ 1–2 days; Mac and Windows together):
1. **Compile and run Windows (M, needs a PC or the .NET SDK here):** nothing on Windows has been compiled since 8 Oct; the harness is `dotnet run --project Windows/F2L.Windows.Tests`. On this Mac, `dotnet build -p:EnableWindowsTargeting=true` would at least catch compile errors (the SDK download needs the owner's OK).
2. **A pointing AI just for zoomed looks (S, needs a Gemini or Z.ai key):** keep DeepSeek for lessons and send only `ZoomLocate` requests to a model trained to return boxes (GLM-4.6V-Flash is free; Gemini 2.5 Flash-Lite $0.10 / $0.40 per 1M tokens). Add "Pointing AI" to Settings; parse Gemini's `box_2d` [ymin,xmin,ymax,xmax] and GLM's `<|begin_of_box|>` format.
3. **Pointing test bench (M):** score each AI on saved screenshots with Accessibility frames as the answer, for a hit rate per AI and a number for the pitch.
4. **Stream replies (M):** show the first words while the AI is still writing (DeepSeek and the OpenAI format support streaming); today the card waits for the whole JSON reply, typically 2–5 s.
5. **"Not there?" fix (S):** one click on the right spot corrects the circle; remember confirmed places per app on this computer.
6. **Reuse the question's screen read for step 1 (S):** the names read before the question (OCR and controls) could serve the first step's pointing when the window hasn't changed, saving 0.1–0.6 s.
7. **Livelier visuals (M):** the circle draws itself, the rest of the screen dims, Pip turns to point, a small Pip celebration at the end of a lesson.
8. **Keep the library current (S, before every demo):** `Assets/Knowledge/ai-tools.json` was written on 11 Oct 2026; tools change their screens often. Update `checked` and the asset manifest hash.

Cheap vision options (USD per 1M tokens in / out, checked 9 Oct 2026; prices change): GLM-4.6V-Flash free; GLM-4.6V-FlashX $0.04 / $0.40; Gemini 2.5 Flash-Lite $0.10 / $0.40 (free tier); GLM-4.6V $0.30 / $0.90. Sources: https://docs.z.ai/guides/overview/pricing, https://ai.google.dev/gemini-api/docs/pricing, https://ai.google.dev/gemini-api/docs/image-understanding, https://api-docs.deepseek.com/guides/vision/, https://github.com/zai-org/GLM-V

Parked (owner found them less useful): skill passport, team playbooks, reply language, offline mode.
