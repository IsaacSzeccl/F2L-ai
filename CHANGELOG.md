# F2L change log

This log records the local implementation and design work through 8 October 2026. Entries describe the working checkout; they are not release tags or a claim that changes have been committed or pushed. Earlier work is grouped by milestone where individual edit times were not recorded. Git history remains the record of previously committed changes.

## 16 October 2026 — Pip proposes the right tool (the demo story)

- "I'm an accountant… teach me a way to read my invoices automatically" names no tool. With Excel in front it picked a weak Copilot recipe; with nothing fitting it had none. Now, when the question names no tool and another tool's recipe fits the task clearly better (more of its tags), Pip proposes that tool and why, then teaches it from where the learner is (`RecipeLibrary.suggest`, `suggestionNote`; both apps). A getting-started question ("teach me to use Gemini") picks the recipe that fits the learner's profile (`fitting`). The invoice lesson says to recommend a Skill first.

## 16 October 2026 — Answers in the learner's language; "the demo" finds the demo lesson

- An English question about a Chinese Gemini came back all in Chinese, and "Let's try the demo" or "create the skill" found no lesson (Chrome's tab title "Google Gemini" didn't count as Gemini), so Pip pointed at an old chat and invented a "save as notebook" step. Now each question says which language the learner wrote in (`TeachingReply.language(of:)`, both apps) and Pip answers in it, naming controls with their on-screen names in brackets ("Click Customize (自訂)"); "Google Gemini" in a window title means Gemini; the invoice lesson is tagged "demo".

## 16 October 2026 — Rehearsed the invoice demo step by step

- `F2L --rehearse ask|step` runs the companion's real pointing on the screen as it is and saves a picture of each step's circle with a report (nothing is clicked). Walking Gemini (Traditional Chinese) and Excel through the demo found and fixed: a tab title ("Google Gemini") taken for "Customize Gemini" (shorter names must now cover most of the label; browser tabs and bookmarks are left out of page lessons); Customize is the round icon, not the four-squares one; text-box steps circled the field's label, now the box; Gemini's prompt box and + button were too deep in the page for the control walk (depth 18 → 32, text areas included); a fragment of a long Chinese label matched; "Gemini's table" circled the Gemini logo; a step the AI says isn't ready is no longer circled from a guess; steps with two clicks were split (Create › Create manually, + › Upload files, A1 › paste).
- Excel cells: Apple's text reader misses Excel's single-letter column headings, so "A1" circled the Name Box. Cells are now found from the gridlines (`ExcelGrid`), and an Excel label like A1 counts as a cell even without "cell". A1 and G7 circle correctly in the dark sheet.
- AI requests may take 90 seconds (was 45): one long demo answer timed out.

## 16 October 2026 — Gemini Skills and the invoice demo

- Gemini now calls saved instructions **Skills** (技能, under Customize Gemini), not Gems. `gemini-create-gem` / `gemini-use-gem` became `gemini-create-skill` / `gemini-use-skill`, and `gemini-invoice-review-skill` teaches the whole demo flow in 16 steps: save an Invoice Review skill, use it with @, upload the invoices, send the extraction prompt, check every row, copy the tab-separated rows, paste at A1 in Excel and add the totals. The three are marked verified from the team's recordings (Traditional Chinese interface).
- Lessons can have up to 20 steps (was 12) and replies up to 1,400 tokens (was 650), so a whole recipe fits. On a step, Copy copies just the words to paste or type.
- `F2L --ask <question.txt> <reply.txt>` (opened with `open -n`) prints the recipes chosen and the reply, for rehearsing a demo. The demo question now picks the invoice recipe and returns all 16 steps in about 5 seconds.
- Also today: reading Chinese and Japanese on screen, matching names by meaning, skipping steps already done, a timing record per question, and the permission and copy fixes above.

## 16 October 2026 — macOS stops asking for permissions on every launch

- **Problem:** F2L asked for its permissions each time it opened, even after they were granted. F2L's private signing keychain was made with the old built-in password; when the password moved to `keychain-password` (8 Oct) the two no longer matched, so the keychain stopped unlocking after a restart. `build-app.sh` then signed ad-hoc without saying so, and the launcher, seeing an ad-hoc app, rebuilt it on every double-click. Each ad-hoc build is a new app to macOS, so every grant was lost.
- **Fix:** `scripts/setup-signing.sh` now moves a keychain it can't unlock aside and makes a new certificate; `build-app.sh` warns when it has to sign ad-hoc; the launcher only re-signs when the certificate actually unlocks, so it can never rebuild on every launch. On the owner's Mac the certificate was renewed and `build/F2L.app` is signed by *F2L Local Signing*, with the same code requirement across rebuilds. Settings › Reset permissions now also clears Screen Recording.
- The owner grants Screen Recording and Accessibility once more for the new certificate.

## 14 October 2026 — Every lesson step looks at the screen again

- **Problem:** a how-to answer plans all its steps from the one screenshot sent with the question, so steps 2, 3, ... were circled from a screen that had since changed (a menu opened, a page loaded, another app came to the front) and the circles were wrong or invented.
- **Fix (Mac):** each time a step after the first is shown, F2L pictures the app as it is now and asks the AI where this step happens (`StepGuide`, `CompanionStepGuide.swift`). The reply gives the place and, when the screen isn't ready, a short note ("The Insert tab isn't open yet. Click Insert first."). The picture is dropped after the reply. Without a key, with sharing off, or on any failure, the step falls back to the first plan, as before. A step the AI can't see is found by name only, never drawn from the old guess.
- 4 new Swift tests (164). **Windows not ported or compiled**: `MainWindow.Lesson.cs` / `ZoomLocate.cs` need the same per-step request.

## 13 October 2026 — Knowledge-base recipes and docs reorganisation

- 25 drafted Gemini and Copilot recipes, Copilot disambiguation by front app, recipe-aware prompt and screen check, a 30-case offline evaluation (tool resolved 16/30 → 30/30), and a build fix so recipes ship in the Mac bundle. Swift tests 127 → 160. Windows C# not compiled.
- Docs moved into `guides/`, `plans/`, `reference/`, `reports/`. See `docs/guides/MERGE_GUIDE.md` and `docs/reports/13102026-knowledge-base-recipes-and-docs-reorg.md`.

## 11 October 2026 — Review of the brand and animation work

- **Planned well and integrated cleanly:** one coordinated palette across the ten pictures, decorative images hidden from screen readers with the native text kept, every file listed with its hash (37 assets, all match), and the same pictures in the same places on Mac and Windows.
- **Memory:** every picture was decoded and kept at full size (1254 px squares, about 6 MB each), and the opening's backdrop was redrawn by the processor 60 times a second. Squares are now decoded at most 512 px wide (sharp up to 256 points), the backdrop and Pip's glow are layers composited by the graphics card, and the backdrop is freed after the opening. Measured with `F2L --soak`: the opening went from 316 MB to about 180 MB at its peak, and memory after it from 70 MB to about 56 MB. The opening still uses about 17% of one core for its six seconds, the same as before the artwork.
- **Packaging:** the 1.5 MB app-icon master is no longer copied into the Mac app or packed into the Windows app; the `.icns` and `.ico` carry the icon.
- The soak check now measures the opening too. A parity test keeps the two apps' artwork loading identical. README's opening paragraph and file layout updated.
- Notes for later: at 16 px the icon is mostly its dark plate (fine from 32 px up); a simpler small-size variant would read better in Finder lists and the Windows taskbar. The `.icns` has no 1x 16 and 32 px images (macOS scales the 2x ones).
- Mac: 127 Swift tests, render, soak and secret checks pass. Windows updated, not compiled.

## 11 October 2026 — Original F2L brand and application artwork

- Added ten original images using built-in image generation: a book-and-doorway emblem, desktop icon, painted dusk entry backdrop, three setup illustrations, three experience badges and a Settings compass. The full prompt set and usage map live in `Assets/Brand/ARTWORK.md`; the visual catalog is `docs/previews/f2l-brand-board.png`.
- Integrated the shared artwork into Mac and Windows entry, setup and Settings screens. Native titles and labels remain accessible; entry artwork follows the existing fade and Reduced Motion behavior. Existing Pip art remains available.
- Packaged native `.icns` and `.ico` icons from the original PNG; configured both app builds to include the branding. Added reproducible icon packaging and visual catalog scripts, asset hashes and load checks in the Mac render check.
- Validation: Mac production build and native render check passed (including the animated entry preview and all three setup screens); all 37 cataloged assets pass byte-size/hash/inventory checks, transparent masters retain alpha, and both icon containers decode. Windows implementation updated, not compiled on this Mac.

## 11 October 2026 — Playful Pip and a clearer code layout

- **Playful idle animations (added by the owner):** a third atlas, `playful.png`, with 16 painted poses (wink, dance, yawn and stretch, peekaboo). While resting, Pip plays one 2.2-second move every 12 seconds or so, in a varied order; anything active takes priority and Reduce animation keeps Pip still. Checked: the new poses match the others in scale and baseline, the asset manifest lists them, and the timing is identical on Mac and Windows (new parity test).
- **Fixed so the moves actually appear:** after a lesson or a how-to answer, Pip kept its "working" pose, which blocks the idle moves. Pip now returns to its resting face whenever the reply card closes (`ReplyBubble.onDismiss`, `ReplyBubbleWindow.Dismissed`).
- **Code layout:** the 1,170-line Mac companion is split by job into `Companion.swift`, `CompanionPointing.swift`, `CompanionLesson.swift` and `CompanionMenu.swift`; the Windows MainWindow the same way (`MainWindow.Pointing.cs`, `.Lesson.cs`, `.Menu.cs`). Unused helpers removed; README's "How it fits together" and "Project layout" and the handoff's goal, active files and next steps brought up to date.
- Mac: 126 Swift tests, render, soak and secret checks pass. Windows mirrored, not compiled.

## 11 October 2026 — Review: faster screen reading, a zoomed second look

- **Zoomed second look:** when F2L can't confirm a place from the screen's words or the app's controls (an icon-only button, or a step in an app the learner switched to), it crops the window around the AI's first guess (or takes the whole window) and asks the same AI where the control is in that crop. Live test with DeepSeek on 22-point icons: off by 11–12 points zoomed, against 35–44 points (a neighbouring icon) across the whole window. One short extra request (about 80 output tokens), only when needed. A real control under the zoomed box makes it exact. `ZoomLocate` on both apps.
- **Faster, lighter screen reading:** the Accessibility walk asks each element for everything in one request and skips containers outside the window (content scrolled away, other windows): same names found, 2–3x faster (Finder 0.14 → 0.05 s, Chrome 0.08 → 0.04 s). Electron apps (Notion, Slack, VS Code) are asked to build their accessibility tree. Windows asks UI Automation for names, places and visibility in one cached search.
- **Before each question,** the screen's text and the app's controls are read in parallel, with the control walk capped at 0.6 s (Windows 0.8 s), so asking stays quick in big apps.
- **Fixed:** typing into Pip's own question box could tick a "type…" step in the lesson.
- GLM's default model is now `glm-4.6v` (half the price of `glm-4.5v`).
- The tool library is now found from the app or the working folder, so the build machine's path is no longer compiled into the app.
- Mac: 125 Swift tests, render, soak (worst 0.8% CPU) and secret checks pass. Windows mirrored, not compiled.

## 11 October 2026 — Steps that finish by opening an app or a site

- **"Open your browser" and "Go to chatgpt.com" now move on by themselves.** `StepGoal` (both apps) reads what a step asks for: any browser in front, a named app in front ("Open Excel"), or a site open in the browser (its window title or the tool's name from the library, e.g. "ChatGPT", "Google Gemini"). Twice a second Pip checks the app in front and its window title (Mac: CGWindowList; Windows: the foreground window) and ticks the step when it becomes true. If it was already true when the step appeared, Pip says "You're already there. Press Done to go on." While Pip itself is in front, the app the learner was using counts.
- **Later steps circle in the new app:** after switching to the browser, a step's place is looked for in the browser's window by name (the AI's position belonged to the earlier screenshot).
- **Done stays as the safe fallback** for any step Pip can't check.
- Live check ("how do I use ChatGPT"): open Safari or Chrome (ticks on the browser), go to chatgpt.com (ticks on the ChatGPT page), click Log in (ticks on the click), type your question (ticks on typing).
- Mac: 117 Swift tests, render, soak (worst 0.7% CPU) and secret checks pass. Windows mirrored, not compiled.

## 11 October 2026 — AI tools library, held keys and typing

- **AI tools library:** 68 AI tools and work apps in one shared file (`Assets/Knowledge/ai-tools.json`, embedded on Windows, copied into the Mac app): summary, official site, platforms, access, how to get started, key features and which kinds of work each suits. A question that names a tool now carries that tool's notes, so Pip teaches from checked facts (live check: "how do I use n8n to save Gmail attachments into Google Drive" gave a 12-step n8n walkthrough starting at n8n.io); "which AI tool should I use…" carries the tools that fit the learner. The starter plan picks from the whole library, and the welcome offers its 19 most common tools as "Tools you already use". Everyday-word names (Make, Gamma, Bolt, Motion, Runway, Consensus, Elicit) only match by their fuller names (make.com, Gamma app). Details checked 11 October 2026 (e.g. NotebookLM is now Gemini Notebook; WorkBuddy is Tencent's desktop AI agent).
- **Held keys:** a step that says to hold Shift, Command/Ctrl or Option/Alt while clicking ticks only when those keys are held, and otherwise says which key to hold.
- **Typing steps:** a step that says to type, enter or paste ticks once the focused box has new text and the learner pauses for 1.5 s. Only the text's length and a hash are compared, never kept or sent (Accessibility on Mac, UI Automation on Windows).
- The render and soak checks now put their windows below the desktop picture instead of fading them, so their numbers stay real (worst 1.0% CPU).
- Mac: 114 Swift tests, render, soak and secret checks pass. Windows mirrored, not compiled.

## 11 October 2026 — Click to continue, sharper pointing and warmer steps

- **Clicking the circled place moves the lesson on, in any app.** While a place is circled, F2L checks the mouse button 20 times a second (nothing is recorded). A press inside the circle ticks a click step ("That's it!", Pip cheers) and goes to the next one; for steps that also need typing or dragging it says what is left; a plain answer is marked done. Presses on Pip's own windows don't count. New `ClickWatch` on both apps.
- **Better pointing without a new AI:** each question now carries the names F2L can read in the shared window (Accessibility or UI Automation control names, then on-device OCR), up to 80, so the AI labels places with names that really exist and F2L can find them exactly (`ScreenNames`).
- **Warmer, more detailed steps:** the teaching style now asks for a patient colleague's tone and, per step, what to do, where it is on screen and what you should see next, one click per step where possible.
- The render and soak checks now keep their windows invisible and click-through, so running a check never shows the sample "Click A1, then hold Shift and click A4" lesson on the learner's screen.
- Mac: 108 Swift tests, render, soak (worst 0.8% CPU with the click watch running) and secret checks pass; live DeepSeek check gave a 7-step Notion setup. Windows mirrored, not compiled.

## 11 October 2026 — Teaching any AI tool, not just Excel

- **Pip teaches the tool you ask about even when it isn't open.** Asking "teach me Tencent WorkBuddy" with Terminal in front used to get "I can't teach this from this screen". The teaching prompt now describes F2L as a coach for AI tools and work apps (ChatGPT, Gemini, Claude, Grok, DeepSeek, Copilot, Tencent WorkBuddy, Notion, Google Workspace, Microsoft 365, Canva, Zoom, Excel), starts from where the learner is (browser, official site, sign-in, first feature), never refuses because another app is in front, and says so plainly instead of inventing menus when it doesn't know a tool.
- Each question now tells the AI which app the screenshot shows ("The screenshot shows Terminal.").
- Learning ideas in the welcome lean towards AI tools (setting up ChatGPT, Gemini or Grok; Notion; Google Workspace; custom GPTs) instead of mostly Excel.
- Mac: 102 Swift tests pass. Windows mirrored, not compiled.

## 9 October 2026 — Circling without being asked

- **Pip circles the place even when the AI leaves its position out.** A step without its own place borrows the reply's place when it names it (or is the only step); otherwise F2L takes the name the instruction points at ("Click the Japan tile" → Japan, "Open the Insert tab" → Insert, "click A4" → A4) and finds it on screen itself through screen text, Accessibility or Excel. Keys ("Command+C") and descriptions with nothing to click are left alone. New `NamedPlace` on both apps, with matching tests.
- The teaching prompt now also asks for a place whenever the reply tells the learner to act on something visible.
- Mac: 101 Swift tests, render and secret checks pass. Windows mirrored, not compiled.

## 9 October 2026 — Choosing what to learn, a clearer menu and real Settings

- **Pip no longer offers to start a task by itself.** The plan step of the welcome now begins with *What do you want to learn?*: ideas for your kind of work as round chips (up to 6) and a box for your own. Pip's greeting offers those topics as buttons plus *Change what I learn*; nothing starts until you pick one.
- **My learning & profile…** in the ··· menu reopens that page any time. Topic changes save straight away and Pip uses them on the next question (they are sent with your background).
- **The ··· menu was simplified** and is rebuilt each time it opens: the AI list says *Key added* or *No key yet*, and *Clear the highlight* and *Put the input bar back* only appear when there is something to do. Reduce animation, Pip walks to what it's teaching, permissions and pointing diagnostics moved to Settings.
- **Settings is now real settings:** pick your AI and paste or remove its key (saved in the private, Git-ignored settings file), two Pip switches, and on Mac what macOS allows F2L to do, with Allow… buttons and Reset permissions. Error messages now point to Settings instead of the settings file.
- **macOS kept asking for permission** because test builds were signed ad-hoc. Every build now signs with the F2L Local Signing certificate when it exists, and the launcher rebuilds an app that lost it.
- Mac: 96 Swift tests, the render check (now including Settings), the soak check and the secret scan pass. Windows mirrored, still not compiled here.

## 9 October 2026 — Debugging and resource check

- **Resource use measured** with the new `F2L --soak` check (no network, microphone or keyboard focus): resting Pip with a greeting 0.2% CPU and about 28 MB; a lesson step 0.2%; a circle with the walking Pip 0.6% and 36 MB; 50 more replies added no memory. Reading a window picture for a step takes 0.1–0.2 s and brings memory to about 110 MB while Apple Vision's text model is loaded. (Under the `timeout` command the first read waited about 30 s; launched normally it is 0.2 s.)
- **Fixed from a full review of the uncommitted work:** starter-plan replies with the closing fence on the last line, or prose instead of JSON, are handled like teaching replies (and show the same message on both apps); an empty duplicate tool can no longer hide a good one on Mac; the offline plan keeps capitals ("KPI dashboard", "I need…", "IT support") instead of lowercasing; DeepSeek's reply length is an explicit setting instead of a comparison of prompt text; the profile is read once (and after setup) instead of from disk on every question; `--export-emotes` refuses to write accent-only images and finds the artwork folder itself. Windows: emotes and the welcome art use resource paths that work from any host, setup uses the injected AI client (and names its provider), and quitting while setup is open no longer reopens closed windows or marks setup as done.
- 97 Swift tests, the render check and the soak check pass. Windows is still not compiled here.
- **Cleanup:** removed code left over from the old chat panel and role chips (message author, time and status labels and their change events; the mood label per question type; the fixed role list; four unused colours) and the unused Windows key writer, on both apps where it existed. Deleted junk files (`.Rhistory`, `.DS_Store`, Python cache, old test logs and render folders) and the stale Windows `bin`/`obj` build folders from the old target. 95 Swift tests (two that only checked the removed labels are gone), the render, soak and secret checks pass.

## 8 October 2026 — First-time setup, personal starter plans and Pip emotes

- **Welcome window (first launch, then "Your profile & starter plan…"):** three steps, *Your world* (name, role, goal), *Your pace* (AI experience, focus, tools already used, a personalisation switch) and *Your path* (2–3 recommended tools, a 3–4 step workflow with a human review step, and a first task). Optional and skippable; Forget my profile removes it. Built by a ChatGPT session and finished here.
- **Starter plans:** Build my plan sends only role, goal, experience, focus and existing tools (no name, no screenshot) to the chosen provider with a dedicated prompt; replies are validated and limited to F2L's built-in tool catalogue (Excel, Notion, Canva, Gemini Notebook, Zapier, GitHub Copilot), so tools and links can't be invented. Keep it local makes a draft without AI.
- **Personal help:** questions carry the background as user-supplied data while personalisation is on; Pip greets by name and offers the plan's first task in the greeting card ("Try my first task").
- **Pip emotes instead of emoji:** six emotes (hello, happy, cheer, thinking, curious, focused) painted from Pip's own poses with drawn accents (`PipEmote`, exported to `Assets/Pip/Emotes` for Windows by `F2L --export-emotes`), shown on greetings, Thinking, notices, ticked steps, finished lessons and the setup window. New art `welcome-journey.png` illustrates the setup window. Asset manifest, inventory and ARTWORK.md updated (frames.json also listed now).
- **Simpler, rounder, work-first (after the owner's review):** the role quick-picks and the focus chips are gone; the user types what they do at work and what they'd like help with at work, and the kind of help is inferred from that text (`inferFocus`). Steps are now *Your work / Your AI / Your plan* with numbered circles, pill fields and buttons, round experience cards with Pip emotes, and Pip's illustration in a circle.
- Validation on the owner's Mac: build, Swift tests and the render check (including the three setup steps) pass. Windows mirrors everything but is not compiled here.

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
- Added the [asset inventory](docs/reference/ASSET_INVENTORY.md), a [SHA-256 manifest](docs/asset-manifest.json), and a repeatable [asset verification script](scripts/verify-assets.ps1). The inventory includes font attribution and the bundled licence.
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
- Recorded the floating-companion concept, separate question/reply areas, context-driven emotions, two-way voice, uncluttered guidance and future expansion from AI tools to other desktop tasks in the [design plan](docs/plans/COMPANION_DESIGN_PLAN.md) and [compatibility plan](docs/plans/COMPATIBILITY_PLAN.md).
- Created Pip, Mori and Tiko concept studies, then the F2L-labelled revision. Preserved the original sheet and generation prompts. Selected the amber lantern Pip for the Windows implementation.
- Added the native .NET 10 WPF Windows application: floating draggable/resizable Pip, companion controls, conversation flow, screen guidance, Windows voice input/output and optional ElevenLabs speech.
- Added DeepSeek configuration in a local Git-ignored file with no API-key entry form. The current configured coach model is `deepseek-flash`; active-app screenshots are supplied when screen sharing is enabled, without requiring an attachment.
- Added Windows setup instructions and a sample configuration; excluded local settings, build output and temporary artifacts from Git.
- Created/repaired the owner's **F2L Companion** desktop shortcut to point to this OneDrive checkout's Debug executable. The installed shortcut is outside the repository; its target is `Windows/F2L.Windows/bin/Debug/net10.0-windows/F2L.Windows.exe` relative to this checkout. A build is required before using that target on another machine.

Primary areas: `Windows/`, `App/Info.plist`, `Package.swift`, product strings under `Sources/`, `.gitignore`, `scripts/`, `README.md`, `SETUP.md`, `docs/guides/TEAM_SETUP.md` and `docs/reports/SPIKE.md`.

## Existing macOS review fixes included in this checkout

- Cancelled in-flight work on pause and invalidated stale captures/pointers after screen-sharing or source changes.
- Cancelled/reset background summaries so outdated context cannot leak into a later question.
- Prevented screenshot-region pointing without an available screenshot and added the corresponding core regression coverage.
- Recorded the review against commit `5626501` in [LOCAL_REVIEW.md](docs/reports/LOCAL_REVIEW.md). These Swift changes were reviewed locally but not built or tested on this Windows host; the document retains its original review date and limitations.

Primary files: `Sources/Beacon/CoachSession.swift`, `Sources/Beacon/ScreenCapturer.swift`, `Sources/CoachCore/Pointer.swift`, `Sources/CoachCore/PromptBuilder.swift` and `Tests/CoachCoreTests/CoachCoreTests.swift`.

## Keeping this record current

Add new behaviour, fixes, assets and validation results to this log when they change. Record exact artwork prompts with the artwork, update the asset manifest when intentionally changing an asset, and run `scripts/verify-assets.ps1` before sharing the project. Never add API keys, user conversations or captured working screens to the asset archive.
