# F2L change log

This log records the local implementation and design work through 8 October 2026. Entries describe the working checkout; they are not release tags or a claim that changes have been committed or pushed. Earlier work is grouped by milestone where individual edit times were not recorded. Git history remains the record of previously committed changes.

## 8 October 2026 — Credential protection and GitHub publication

- Reviewed the Mac/Windows companion changes and prepared a clean publication snapshot, excluding local signing-password history.
- Replaced the shared signing-keychain password with a random per-machine password stored outside the repository with owner-only permissions. The existing local signing identity is preserved.
- Expanded ignore rules and added redacted credential checks for staged files, working files and reachable history, plus pre-commit/pre-push hooks and GitHub Actions.
- API clients refuse redirects and show safe status messages instead of raw provider errors that might echo credentials. Windows builds and publishes no longer copy local settings.
- Validation: 81 offline Swift tests; dedicated scanner regressions. Windows execution still needs a Windows machine.

## 8 October 2026 — Opening, quiet replies and interactive lessons

- **Excel selections:** Pip reads every selected area from Excel itself (Mac: AppleScript, one-time Automation permission; Windows: Excel COM), so A1:A4 plus D1:D4 is no longer reported as D1:D4 only. The addresses go with the question and show live on Pip's card.
- **New chats start empty:** each launch and **New chat** start a fresh session file; old conversations are not restored and `conversation.json` is left untouched.
- **Layout:** replies appear word by word in a card beside Pip; questions go in a single bar at the bottom centre (text, microphone, Send). The chat panel, header, Read reply, Follow reply, screen-status and hint lines are gone.
- **Lessons:** multi-step answers open with **Let's start**, then one step at a time with **Done**, **Show me again** and **I'm stuck** (which asks Pip for help from that step). Selection steps tick themselves when Excel shows them done and say what is missing (for example a range dropped because Command/Ctrl wasn't held). Pip waves when a step is ticked. (A short end-of-lesson quiz was tried and removed at the owner's request.)
- **Opening:** every launch shows "F2L AI · Your personal AI companion" at the centre, Pip appears waving and walks slowly to its corner, then says "How can I help you?". A click skips it; Reduce animation shortens it.
- **Pip goes to the place:** the model can give a target for every step (cell, tab, button or icon, in any app, Excel ribbon included); showing a step sends Pip there and outlines it (green when Excel confirms a cell, dashed amber from the screenshot otherwise), and step hints stay while the step is shown. Previously Excel replies never moved Pip on Mac, and Excel ribbon hints were suppressed on both apps.
- **Accurate circles:** hints are now circles that pass just outside the target. A rough place from the screenshot is snapped to the real control the app reports by name or position (Mac Accessibility, Windows UI Automation), in any app. On Mac, Excel cells are placed from Excel's own cell positions, zoom and scroll (AppleScript) plus the grid's Accessibility frame, using the model's box only to choose between 72/96 dpi and header layouts; frozen or split panes fall back to the estimate. Not yet checked against live Excel.
- **Pointing fixes after the owner's test:** circles were wrong because F2L never asked for Accessibility, so the model's rough screenshot coordinates were drawn unchecked. F2L now asks once, snaps to a named control wherever it is, and no longer draws the model's position by itself when the app can be read (it only draws it, dashed, when Accessibility is denied). Every decision is logged to `pointing.log` (no pictures); **Save pointing diagnostics** in Pip's menu writes a snapshot (window picture, Accessibility controls, Excel grid and cell numbers) for debugging. Pip, its card and the input bar stay clear of the circle; the input bar can be dragged anywhere (**Put input back at the bottom** resets it). Dictation now adds to typed text instead of replacing it, and keeps the shown words if the recogniser ends empty.
- **Finding places by reading the screen:** each time a step is shown, F2L pictures the taught window again and reads its words on the computer (Apple Vision on Mac, Windows OCR on Windows; nothing is sent). Buttons and tabs are circled where their names appear; Excel cells where the column letter and row number meet, tolerating misread or missing headings. The render check now draws an Excel-like window and confirms D3 and the Insert tab are found where they were drawn. Windows now targets `net10.0-windows10.0.19041.0` for the OCR API (launcher paths updated; not compiled here).
- **After the owner's Fill test (from pointing.log):** Accessibility was off and Fill is an icon with no visible name, so nothing could be confirmed and nothing was drawn. Pip now goes to the model's spot straight away (dashed) and replaces it with a checked place when one is found; when Accessibility is off, the card says so with an **Open Settings** button. Steps clicked through before reading finished are logged as superseded.
- **After the owner's Zoom test:** F2L had pictured Zoom's small "Start Zoom AI" card instead of the meeting window, so both the AI and the pointing looked at the wrong window; it now takes the app's main window (the frontmost one at least half the size of its biggest). Words read off the screen are matched by name only (a stray "2" was circled as Fill). Pip now stays in its corner and only the circle moves ("Pip follows teaching targets" turns walking back on), and lessons start straight at step 1 with their summary above the steps.
- **Repeated permission prompts:** the background Excel selection check could re-trigger macOS's "control Microsoft Excel" prompt, and F2L asked for Accessibility on every launch. Now only a question you just sent may ask about Excel (checked first with `AEDeterminePermissionToAutomateTarget`), Accessibility is only requested from the card's button, and **Fix permissions…** in Pip's menu clears F2L's stale Accessibility/Automation entries (`tccutil reset`) so a fresh grant sticks.
- **Switchable AI providers:** DeepSeek, ChatGPT (OpenAI), Gemini, Claude and GLM, chosen with **AI provider** in Pip's menu or `"Provider"` in `local.settings.json`, each with its own key and optional model override; read fresh for every question. DeepSeek, ChatGPT, Gemini and GLM use the OpenAI chat format (Gemini and GLM through their OpenAI-compatible endpoints); Claude uses the Messages API (`claude-opus-5-5`, low effort, server-side refusal fallback). `DeepSeekClient` is now `CoachClient` on both apps. Keys: `**/local.settings.json`, `.env*` and keychains are Git-ignored, and `scripts/check-secrets.sh` (pre-commit hook) blocks commits containing keys. The owner's keys were checked: only in ignored files, never committed.
- **Voice off:** replies are no longer spoken and ElevenLabs is never called; the spoken-output code was removed. Dictation stays.
- Validation on the owner's Mac: Mac app builds; 68 Swift tests pass (including step checks, step targets and prompt parity with C#); render check passed, including the opening and a ticked step. **The Windows changes were not compiled: there is no .NET SDK on this Mac.** Run the Windows harness on a PC.

## 8 October 2026 — Mac and Windows parity, tests and setup docs

- Shared rules now match exactly on both apps: placement uses WPF's edge-inclusive rectangles, cell references right after Chinese text ("圈出A1") are found, `conversation.json` has the same five fields from either app, and keys are looked up in the same order (environment, `local.settings.json`, keychain / Credential Manager).
- Mac: teaching Pip fades when another app's text caret comes near (needs F2L under Accessibility; polled off the main thread). The conversation turn mirrors Windows: cell requests locate the window without a picture, model rectangles are never drawn over Excel, a target covered by another window isn't outlined, and hints clear when another app comes to the front. Excel for Mac doesn't expose cell positions to Accessibility, so Mac names the requested cell without drawing an outline.
- Settings on both apps show the key file in use, with **Show file** creating an empty one. Reopening F2L on Windows brings the conversation up (single instance), as on Mac.
- Mac conversation rows cache their measurements and text layout.
- `scripts/setup-signing.sh` creates a private signing certificate so macOS keeps F2L's permissions across rebuilds (the owner runs it once).
- README, SETUP, TEAM_SETUP and SPIKE rewritten for the current companion; DECISIONS and the Windows README updated.
- Validation on the owner's Mac: Mac app builds; 62 Swift tests pass, including checks that compare prompts, messages, patterns, placement and pose timings with the C# sources; render check passed; a live DeepSeek follow-up question returned real answers three times. **The Windows changes (settings window, single instance, settings lookup, launcher) were not compiled: there is no .NET SDK on this Mac.** Run the Windows harness on a PC.

## 8 October 2026 — Asset archive and change records

- Consolidated the changes below, including the known validation limits, and updated the current product decisions.
- Kept both original character concept sheets, both production sprite atlases and their exact generation prompts in the repository. Confirmed all four generated PNGs match the original image-generation outputs byte for byte.
- Archived the original layout exploration HTML and both controlled WPF UI previews under `docs/`. The preview copies survive cleanup of the ignored `Windows/artifacts/` directory.
- Added the [asset inventory](docs/ASSET_INVENTORY.md), a [SHA-256 manifest](docs/asset-manifest.json), and a repeatable [asset verification script](scripts/verify-assets.ps1). The inventory includes font attribution and the bundled licence.
- Added Git attributes that preserve asset bytes across Windows/macOS checkouts, including the archived prompt and licence text covered by the checksums.
- Linked the records from the project and Windows READMEs. This milestone changes documentation and asset storage only; the application checks below were completed during the implementation milestone.
- Archive verification passed for all 13 files (7,968,316 bytes), with no unlisted assets. Checked 44 local documentation links, asset Git attributes, asset inclusion, the local-settings exclusion and whitespace. No application rebuild was needed for this documentation/archive change.

## 8 October 2026 — Painted Pip, direct replies and target following

### Teaching and character

- Replies lead with the useful action or answer. Default guidance is one step in 1–3 short sentences, usually no more than 55 words; requested detail can be longer. Removed common standalone praise, introductions and closing invitations while preserving instructions and formulas.
- Expression selection follows question type and interaction state. Short questions are no longer treated as confusion simply because they are short.
- Replaced the shape-drawn Windows character with the original amber lantern Pip in generated, transparent, painted 2D artwork: 16 expression poses and 16 direction/side/walking poses.
- Added timed blink, speech, listening and thinking animations, directional gestures and travel poses. Reduced animation uses still images and skips animated travel. Windows animation preferences supply the initial choice.
- Preserved the source atlas pixels and alpha. Runtime cropping isolates each figure and aligns its feet; frame-selection exceptions are documented in [ARTWORK.md](Windows/F2L.Windows/Assets/Pip/ARTWORK.md).

### Guidance

- Pip moves beside a teaching target and points towards it. Placement avoids the protected target, conversation panel and screen edges; if there is no safe slot, Pip remains at its resting place.
- The teaching character passes clicks through and temporarily yields to a nearby pointer or visible caret. Travel avoids visibly crossing the target or conversation panel. Only one Pip is visible at a time.
- Verified Excel targets are resolved again approximately every 400 ms, following window movement and worksheet scrolling. Guidance clears when the cell, sheet or source application becomes unavailable or changes.
- Added target-following and reduced-animation controls to the companion menu, also accessible from the conversation header while Pip is away. These choices currently last for the running session.

### Validation recorded during implementation

- Windows build passed with zero warnings and errors; 150 regression checks passed. Coverage includes all 32 transparent poses, actual animation timing, reduced motion, placement at several simulated scales and negative display origins, pointer/caret avoidance, conversation lifecycle, Enter handling, target geometry and reply cleanup.
- A separate live desktop Excel test used its own blank workbook: A1/B1 at 80%, 100% and 150% zoom, frozen panes, offscreen rejection and cell geometry after moving the window passed. The test harness can read its test window while Codex retains foreground focus; production keeps its foreground-app guard.
- One live text-only DeepSeek request returned: “Select cell A6, then type =SUM(A1:A5) and press Enter.” This check did not send a screenshot or workbook contents.
- Rendered the actual WPF interface with synthetic sample messages, archived as [the textured UI preview](docs/previews/pip-ui-textured.png), and reopened the Windows application.
- Live microphone recognition and ElevenLabs playback were not re-tested in this milestone. macOS parity, live mixed-monitor testing, general Windows UI Automation targeting, password-field detection, full accessibility testing and installer packaging remain pending. Other-app screenshot hints are approximate and cannot verify task completion.

Primary files: `TeachingReply.cs`, `QuestionIntent.cs`, `PipSprites.cs`, `PipView.xaml` / `.cs`, `CompanionPlacement.cs`, `TeachingCompanionWindow.cs`, `MainWindow.Guidance.cs`, `NativeDesktop.cs`, `ConversationView.xaml` / `.cs`, and `Assets/Pip/` under `Windows/F2L.Windows/`; regression and Excel checks under `Windows/F2L.Windows.Tests/`.

## 7–8 October 2026 — App selection and Enter-to-send fixes

- Remembered the last external application with foreground events and a lightweight identity tracker, excluding F2L, shell, minimised and unavailable windows. Tracking does not capture background screenshots.
- Pinned the selected window and process before bringing it forward and capturing its visible client area. Reject captures from changed or unavailable sources.
- Allowed general questions to proceed without an image when capture is unavailable, with an explanatory status. Direct cell-pointing requests do not invent coordinates when screen context is missing.
- Handled Enter before the multiline composer consumes it. Shift+Enter inserts a newline; IME confirmation and repeated Enter are guarded.
- At this checkpoint, the Windows build and 73 regression checks passed and the application was reopened. The later 150-check run includes these regressions.

Primary files: `ForegroundAppTracker.cs`, `ScreenCaptureService.cs`, `ComposerKeys.cs`, `ConversationView.xaml.cs`, `MainWindow.xaml.cs` and `NativeDesktop.cs` under `Windows/F2L.Windows/`.

## 7 October 2026 — Conversation, voice and accurate Excel guidance

- Reworked the Windows interface into a compact conversation panel with a separate fixed composer, retained selectable messages, expand/minimise controls and Read/Copy actions. Bundled Inter Regular, Medium and SemiBold with the SIL Open Font License.
- Kept conversation state and active replies intact when Pip is clicked, reopened or minimised. Improved send/stop/cancellation handling so stale responses cannot replace a newer conversation or leave the composer disabled.
- Saved up to 500 messages and the unsent draft locally, with backup recovery; interrupted requests restore as stopped. Conversation storage contains text, not screenshots, audio or keys.
- Followed reply progress during speech and used a reading pace while muted. Manual scrolling or selecting text pauses following; Follow reply and Latest restore it.
- Changed voice input to tap Speak / Finish, accumulated recognised phrases and left an editable transcript before sending. Preferred an installed Windows speech recogniser matching the display language.
- Added ElevenLabs timestamped speech and Windows speech-progress fallback. Isolated each playback's cancellation and temporary audio resources so stopping one reply cannot stop a later reply.
- Replaced guessed desktop Excel cell circles with read-only native Excel geometry, per-pane/zoom resolution and three-point cell identity checks. A1 cannot be satisfied by B1. Merged cells use the merged area; offscreen or unverified cells receive an explanation.
- Added source-window/process identity checks and physical-pixel placement with PerMonitorV2 awareness. Removed the minimum outline expansion that could overlap an adjacent cell.
- Distinguished solid green verified cell outlines from dashed amber approximate screen hints. Approximate hints expire and clear when the source window changes.
- At this checkpoint, 52 regression checks and the initial blank-workbook Excel integration checks passed. Later checks extend this coverage.

Primary files: `ConversationSession.cs`, `ConversationView.xaml` / `.cs`, `VoiceServices.cs`, `CellReference.cs`, `ExcelTargetResolver.cs`, `TargetGeometry.cs`, `GuideOverlayWindow.xaml` / `.cs`, `NativeDesktop.cs`, `App.xaml`, `app.manifest` and `Assets/Fonts/` under `Windows/F2L.Windows/`.

## 7 October 2026 — F2L identity, platform direction and Windows foundation

- Renamed the product from Beacon to F2L in display names, package products, bundle metadata, scripts and setup documentation. Historical source directory names remain where renaming was unnecessary.
- Set macOS and Windows as the intended release platforms. The present native Windows companion and original macOS prototype have different feature coverage; release parity is not yet established.
- Recorded the floating-companion concept, separate question/reply areas, context-driven emotions, two-way voice, uncluttered guidance and future expansion from AI tools to other desktop tasks in the [design plan](docs/COMPANION_DESIGN_PLAN.md) and [compatibility plan](docs/COMPATIBILITY_PLAN.md).
- Created Pip, Mori and Tiko concept studies, then the F2L-labelled revision. Preserved the original sheet and generation prompts. Selected the amber lantern Pip for the Windows implementation.
- Added the native .NET 10 WPF Windows application: floating draggable/resizable Pip, companion controls, conversation flow, screen guidance, Windows voice input/output and optional ElevenLabs speech.
- Added DeepSeek configuration in a local Git-ignored file with no API-key entry form. The current configured coach model is `deepseek-flash`; active-app screenshots are supplied when screen sharing is enabled, without requiring an attachment.
- Added Windows setup instructions and a sample configuration; excluded local settings, build output and temporary artifacts from Git.
- Created/repaired the owner's **F2L Companion** desktop shortcut to point to this OneDrive checkout's Debug executable. The installed shortcut is outside the repository; its target is `Windows/F2L.Windows/bin/Debug/net10.0-windows/F2L.Windows.exe` relative to this checkout. A build is required before using that target on another machine.

Primary areas: `Windows/`, `App/Info.plist`, `Package.swift`, product strings under `Sources/`, `.gitignore`, `scripts/`, `README.md`, `SETUP.md`, `docs/TEAM_SETUP.md` and `docs/SPIKE.md`.

## Existing macOS review fixes included in this checkout

- Cancelled in-flight work on pause and invalidated stale captures/pointers after screen-sharing or source changes.
- Cancelled/reset background summaries so outdated context cannot leak into a later question.
- Prevented screenshot-region pointing without an available screenshot and added the corresponding core regression coverage.
- Recorded the review against commit `5626501` in [LOCAL_REVIEW.md](docs/LOCAL_REVIEW.md). These Swift changes were reviewed locally but not built or tested on this Windows host; the document retains its original review date and limitations.

Primary files: `Sources/Beacon/CoachSession.swift`, `Sources/Beacon/ScreenCapturer.swift`, `Sources/CoachCore/Pointer.swift`, `Sources/CoachCore/PromptBuilder.swift` and `Tests/CoachCoreTests/CoachCoreTests.swift`.

## Keeping this record current

Add new behaviour, fixes, assets and validation results to this log when they change. Record exact artwork prompts with the artwork, update the asset manifest when intentionally changing an asset, and run `scripts/verify-assets.ps1` before sharing the project. Never add API keys, user conversations or captured working screens to the asset archive.
