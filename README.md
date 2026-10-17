# F2L AI: a desktop companion that teaches you where to click

*(codename: solo-level · Hack4SDG 2026, Track 4 — Future Work & Enterprises)*

F2L AI helps people set up and learn AI tools and everyday work apps (ChatGPT, Gemini, Grok, Tencent WorkBuddy, Notion, Google Workspace, Microsoft 365, Excel and more) on their own computer. Ask about any tool, even one that isn't open yet: Pip starts from where you are (open the browser, go to the official site, sign in) and teaches the first useful steps. It puts **Pip**, a small painted lantern character, on top of the app you're learning. Each launch opens with a short animation: "F2L AI" appears in the middle of the screen, then Pip walks to its corner, waves and asks how it can help. Ask a question in the bar at the bottom centre, and Pip's answer appears word by word in a card beside the character. Tasks become short lessons: one step at a time, with **Done**, **Show me again** and **I'm stuck**, and steps that tick themselves when F2L sees them happen (a click on the circled place, typing in the box, the right app or website coming to the front, or Excel showing the selection). When the answer is about something on screen, F2L circles it: solid green when the place was confirmed, dashed amber for an approximate hint. You stay in control; Pip never clicks for you.

The Mac and Windows apps are two native implementations of the same companion: same artwork, layout, wording, menus, saved conversation format and teaching rules.

**New teammate?** Start with [docs/guides/TEAM_SETUP.md](docs/guides/TEAM_SETUP.md). Owner's checklist: [SETUP.md](SETUP.md). Decisions: [docs/reference/DECISIONS.md](docs/reference/DECISIONS.md). Changes and validation: [CHANGELOG.md](CHANGELOG.md). Artwork, prompts and font licences: [docs/reference/ASSET_INVENTORY.md](docs/reference/ASSET_INVENTORY.md).

## Open Pip

| | Mac | Windows |
|---|---|---|
| One-click launcher | Double-click **Open F2L Companion.command** | Double-click **Open F2L Companion.bat** |
| Desktop shortcut | `"./Open F2L Companion.command" --install-shortcut` | `"Open F2L Companion.bat" --install-shortcut` |
| Needs | macOS 15+, Xcode or the Command Line Tools | Windows 10/11, the .NET 10 SDK |

The launcher builds F2L the first time and whenever the code has changed, then opens Pip. The shortcut it adds is called **F2L Companion**; opening it again while Pip is running brings the input bar up. Before the first question, add a key for your AI provider (see [AI providers and keys](#ai-providers-and-keys)).

## Using Pip

The opening introduces **F2L AI — A teaching companion** with the original book-and-doorway emblem, a painted dusk landscape, bouncing letters, a word-by-word subtitle and Pip waving beside the name. Pip then walks down to its resting position with a short sparkle trail. Click anywhere to skip; **Reduce animation** uses a brief, still introduction.

F2L also has its own Mac/Windows app icon, three setup illustrations, three experience badges and a Settings compass. [View the ten-asset collection](docs/previews/f2l-brand-board.png) and [the original generation prompts and usage map](Windows/F2L.Windows/Assets/Brand/ARTWORK.md). Both apps use the same artwork.

- **Pip feels alive:** while resting, Pip blinks and every 12 seconds or so plays one of four short painted moves (a wink, a little dance, a yawn and stretch, peekaboo), in a different order each time. It goes back to resting as soon as a reply or lesson closes. Anything active (listening, thinking, pointing, a task in progress) takes priority, and Reduce animation keeps Pip still.
- **Click Pip** to show the input bar; **drag Pip** to move the character and its reply bubble. The input stays at the bottom centre. **Hide the input bar** in Pip’s menu minimises the controls without discarding the current session.
- **Type** and press **Enter** to send; **Shift + Enter** adds a line. **◉** starts dictation and **■** puts the words in the box for you to check before sending. Click anywhere on the opening to skip it.
- Replies appear **word by word** beside Pip (click the text to show it all). A short answer offers **Got it** and **Explain more**.
- A task becomes a lesson that starts straight at step 1, with what it achieves shown above. **Done** moves on, **Show me again** replays the step, **I'm stuck** asks Pip for help from where you are. In Excel, a selection step ticks itself when Excel shows it done, and Pip says what is still missing (for example if you forgot to hold Command/Ctrl). Pip waves when a step is done.
- Pip is silent for now: replies are shown, not spoken. **Reduce animation** shows complete phrases immediately and shortens the opening.
- Each launch starts empty. **New chat** clears the visible reply, draft, active task and model history. Previous saved files remain on disk.
- **···** beside Pip: New chat, My learning & profile, which AI to use (each marked *Key added* or *No key yet*), Share my screen with Pip, Pip size, Move Pip to the other side, Hide the input bar, Settings and Quit. **Clear the highlight** and **Put the input bar back** appear only when there is something to clear or put back.
- **Settings** holds the real settings: pick your AI and paste or remove its key, Reduce animation, Pip walks to what it’s teaching, and (Mac) what macOS allows F2L to do, with **Allow…** buttons and **Reset permissions** for when macOS keeps asking.
- **Excel selections:** with sharing enabled, Pip reads all selected areas (including Command/Ctrl-click selections), sends those addresses with your question, and displays a live selection line above the steps. On Mac, accept the first **F2L → Microsoft Excel** Automation request. If denied, enable it in **System Settings → Privacy & Security → Automation**; typed questions still work without selection access. Windows uses Excel COM. Neither reader edits the workbook.
- **"Circle A1"** (or 圈出A1) in desktop Excel: on Windows, F2L asks Excel where that cell is, checks it, and draws a green outline. It never selects, edits or scrolls your workbook, and if the cell isn't fully visible Pip says so instead of guessing. On Mac, Excel doesn't report cell positions, so a direct "circle A1" only names the cell.
- **Steps that finish themselves:** "Open your browser" ticks when a browser comes to the front, "Open Excel" when Excel does, and "Go to chatgpt.com" when that page is open in the browser (Pip checks the app in front and its window title). **Done** is always there for anything Pip can't check.
- **Click to continue:** clicking the circled place ticks a click step and moves on; a step that says to hold a key ("hold Shift and click A4") only ticks when that key is held; a typing step ("type your email in the box") ticks once the box has new text and you pause. Pip checks only the mouse button, the held keys and the length and a fingerprint of the focused box's text, never what you type.
- **Circling the place:** every reply and every lesson step can point at where it happens (a cell, tab, button or icon in any app), and F2L circles it. Pip stays in its corner (**Pip walks to what it’s teaching** in Settings makes it walk over). F2L reads the screen itself (on your computer, nothing is sent) to find the place: a button or tab where its name appears, a cell where its column letter and row number meet. It also uses what the app reports: the real button, tab or menu found by name through Accessibility (Mac) or UI Automation (Windows), a cell Excel confirms (Windows) or one measured from Excel's own row and column sizes (Mac). Green means the app reported the place; dashed amber means it is the model's estimate. Moving to the next step moves the circle. F2L looks at the app's main window, not a small popup in front of it.

## First-time setup and personalisation

The first time Pip opens, after the opening animation, a three-step welcome window asks about you. It is optional ("Not now"), takes about a minute, and can be reopened any time from **My learning & profile…** in Pip's ··· menu.

1. **Your work:** three questions you answer in your own words: what Pip should call you (optional), what you do at work, and what you'd like help with at work. Pip works out the kind of help from your answer, so there is nothing to pick.
2. **Your AI:** how you use AI today (*Just getting started*, *Tried a few things*, *Part of my routine*, each a round card with Pip's emote) and, optionally, tools you already use at work.
3. **Your plan:** a small toolkit of 2–3 recommended tools, each with one concrete use for your work, a 3–4 step workflow to try (always including a human review step), and **What do you want to learn?**: Pip's ideas for your kind of work as round chips to tick (up to 6), plus a box to add your own. **Make my plan** asks your AI provider, using text only (no screenshot) and only tools from F2L's built-in catalogue, so it never invents tools or links. **Plan without AI** makes a starter plan on your computer.

The window is round like Pip: numbered circles for the steps, pill-shaped fields and buttons, and round cards.

Afterwards Pip is personal: it greets you by name and asks what you'd like to learn today, offering the topics you ticked as buttons (plus **Change what I learn**). Nothing starts until you pick one. Changing your topics later in **My learning & profile…** saves straight away, so Pip's next answer already knows. Pip adds your role, goal, AI experience and topics to each question so examples and the amount of detail suit you (turn this off with *Use this to personalise Pip's help*). Pip never guesses ability from occupation. The profile is saved only on your computer (`profile.json`, readable only by you), and **Forget my profile** removes it.

Pip's cards never use system emoji. Pip has its own emotes, painted from its poses: hello, happy, cheer, thinking, curious and focused.

## The AI tools library

Pip carries a library of 68 AI tools and work apps (`Windows/F2L.Windows/Assets/Knowledge/ai-tools.json`, read by both apps): AI assistants (ChatGPT, Claude, Gemini, Copilot, Grok, DeepSeek, Perplexity, Doubao, Tencent Yuanbao, Tencent WorkBuddy and more), workspace apps (Notion, Google Workspace, Microsoft 365 Copilot, Gemini Notebook), automation (n8n, Zapier, Make, Power Automate), agent builders (custom GPTs and Gems, Copilot Studio, Coze, Dify), design, video and audio (Canva, Midjourney, CapCut, ElevenLabs), coding and app builders (GitHub Copilot, Cursor, Lovable), research and learning tools, and business tools. Each entry has what it is for, the official site, where it runs, how to get started, its key features and which kinds of work it suits.

- **Teaching:** when a question names a tool ("how do I use n8n?"), Pip sends that tool's notes with the question, so steps start from the official site and real features instead of guesses. The AI is told the notes are reference data and that the screen wins when an interface has changed.
- **Recommending:** when you ask which tool to use, Pip sends the library's tools that fit your kind of work and the tools you already use, and the AI recommends from those with the reason and official site. The starter plan in the welcome also picks from the whole library.
- **Keeping it current:** edit the JSON (and its `checked` date); both apps pick it up on the next build. Interfaces change, so keep entries to stable facts.

## AI providers and keys

F2L can teach with **DeepSeek, ChatGPT (OpenAI), Gemini, Claude or GLM**. Each needs its own API key; choose which one to use and paste its key in **Settings** (or **AI** in Pip's ··· menu), or set `"Provider"` and the key in `local.settings.json` yourself. The next question uses the new provider; no rebuild is needed.

```json
{
  "Provider": "deepseek",
  "DeepSeekApiKey": "", "DeepSeekModel": "",
  "OpenAIApiKey": "",   "OpenAIModel": "",
  "GeminiApiKey": "",   "GeminiModel": "",
  "ClaudeApiKey": "",   "ClaudeModel": "",
  "GLMApiKey": "",      "GLMModel": ""
}
```

| Provider | `"Provider"` | Default model (override with `<Name>Model`) | Key variable |
|---|---|---|---|
| DeepSeek | `deepseek` | `deepseek-flash` | `DEEPSEEK_API_KEY` |
| ChatGPT | `openai` | `gpt-5-mini` | `OPENAI_API_KEY` |
| Gemini | `gemini` | `gemini-2.5-flash` | `GEMINI_API_KEY` |
| Claude | `claude` | `claude-opus-5-5` | `ANTHROPIC_API_KEY` |
| GLM (Zhipu) | `glm` | `glm-4.6v` | `GLM_API_KEY` |

Pick a model that accepts images (all defaults do). Both apps look in the same places, in this order, and use the first value they find:

1. environment variables (`F2L_PROVIDER`, the key variables above, `F2L_MODEL_<PROVIDER>`);
2. the first `local.settings.json` that exists of: your per-user file (Mac `~/Library/Application Support/F2L/`, Windows `%APPDATA%\F2L\`), the F2L folder's root, the older `Windows/F2L.Windows/` copy, or the file next to the app;
3. the Mac login keychain (service `F2L`, account = the key variable) or Windows Credential Manager (`F2L/<key variable>`).

**Settings** saves keys into that same private file (readable only by you, ignored by Git); **Show the settings file** reveals it.

**Keeping keys off GitHub:** private settings, `.env` files, signing material, logs and diagnostic exports are Git-ignored. With Python 3 installed, run `scripts/check-secrets.sh --install` to check staged files before commits and outgoing history before pushes. Run `scripts/check-secrets.sh --all` for the index and publishable working files, and `scripts/check-secrets.sh --history --ref HEAD` for the current branch's history. GitHub Actions repeats these checks. Findings never print key values. Keep keys in local settings, environment variables, or the OS credential store; never in code or docs. See [SECURITY.md](SECURITY.md) for scope and limitations.

## Privacy

- With **Share my screen with Pip** on, sending a question takes one picture of the app you were last using (never the whole screen, never in the background) and sends it with your question to the AI provider you chose. During a lesson, each step after the first takes a new picture of the app when the step appears (after you finish the one before, or press Show me again), so the circle matches what is on screen now; this needs the same sharing switch and goes to the same provider. Pictures are not saved. Turn sharing off from Pip's menu at any time.
- "Circle A1" requests don't call the AI; they're answered on your computer by asking Excel.
- The latest 500 messages and draft of each session are saved separately: Mac `~/Library/Application Support/F2L/sessions/<id>.json`, Windows `%LOCALAPPDATA%\F2L\sessions\<id>.json`. The legacy `conversation.json` is left untouched. Sessions are not automatically restored.
- After an Excel question, the selection line refreshes while the input is open and sharing is enabled. These background reads stay local; only the selection at question time accompanies a model request.
- Your profile (name, role, goal, AI experience, focus and tools) is saved only in `profile.json` in F2L's folder (Mac `~/Library/Application Support/F2L/`, Windows `%LOCALAPPDATA%\F2L\`). Your name is never sent; role, goal, experience, focus and tools go to the AI provider with your questions only while personalisation is on, and with **Make my plan**. **Forget my profile** deletes it locally; it cannot recall what was already sent.
- Nothing is sent to ElevenLabs: spoken replies are off. Dictation uses the computer's own speech recognition.

## How it fits together

```
 question ──► "circle A1"? ──yes──► ask desktop Excel where A1 is ──► green circle
     │ no
     ▼
 picture of the app in front (if sharing is on) + names read on screen (Accessibility / UI Automation + on-device OCR)
 + notes for any AI tool the question names (tools library) + your background (if personalisation is on)
     ▼
 AI provider ──► JSON reply: words, steps, a place per step
     ▼
 card shows the words one by one; a lesson goes one step at a time
     │
     ├─► each step's place: Excel cell → checked with Excel · named control → found by name on screen ·
     │   otherwise a zoomed second look by the AI → green when the app confirms it, dashed amber when approximate
     └─► each step finishes by itself when F2L sees it happen: a click on the circle (with any keys it says to hold),
         typing in the box, or the app or website it asks for coming to the front; Done always works
```

Shared rules live once per platform and are tested against each other: `Sources/CoachCore` (Swift) and their C# twins in `Windows/F2L.Windows`. The Swift tests also read the C# sources to check that prompts, messages, patterns and timings haven't drifted apart.

## Project layout

```
Open F2L Companion.command/.bat   One-click launchers (Mac / Windows)
Package.swift                     Swift package: CoachCore, the F2L Mac app, CoachCoreTests
App/                              Info.plist and entitlements for F2L.app
Sources/CoachCore/                Shared, tested rules (each has a C# twin of the same name in Windows/F2L.Windows):
  CoachClient, Providers,           the AI request for 5 providers, the teaching prompt and reply style,
  TeachingReply, LocalSettings      keys and settings lookup
  Conversation                      the saved conversation file
  LearnerProfile                    the welcome: profile, starter plan, learning topics
  AIToolLibrary                     the 68-tool library Pip teaches and recommends from
  NamedPlace, TargetSnap,           finding a step's place: by name, on screen, Excel cells,
  ScreenText, CellReference,        a zoomed second look
  ZoomLocate
  ClickWatch, StepGoal, Lesson      steps that finish by themselves (click, held keys, typing, app or site, Excel)
  CompanionPlacement                where Pip, the card and the input bar sit; Pip's poses and idle animations
Sources/F2L/                      The Mac app (AppKit):
  Companion.swift                   state, layout, input bar, a question's round trip, dictation, saving
  CompanionPointing.swift           circling places on screen
  CompanionLesson.swift             watching a step happen
  CompanionMenu.swift               the ··· menu, Settings, the profile window
  ReplyBubble, Pip, Intro,          the card, Pip's sprites, the opening, the windows
  PersonalizeWindow, SettingsWindow
  BrandArtwork.swift                F2L's painted artwork, decoded once at the size it is shown
  Accessibility, ScreenCapture,     reading the screen: controls, window pictures, words, Excel's selection
  ScreenReading, ExcelSelectionReader
Tests/CoachCoreTests/             Swift tests (scripts/test.sh), including Mac/Windows parity checks
Windows/F2L.Windows/              The Windows app (WPF); MainWindow is split the same way (.Pointing, .Lesson, .Menu,
                                  .Guidance). Assets/ is shared by both apps: Pip/ (48 poses in three atlases, emotes),
                                  Brand/ (emblem, launch backdrop, app icon master, .icns, .ico, ARTWORK.md),
                                  Illustrations/ (setup scenes, experience badges, Settings compass), Fonts/, Knowledge/
Windows/F2L.Windows.Tests/        Windows regression harness
scripts/                          build-app.sh, run.sh, test.sh, setup-signing.sh, check-secrets.sh,
                                  tools/pip_frames.py (atlas rectangles), tools/preview_pip.swift (animation GIFs),
                                  tools/package_brand_icons.py (.icns/.ico), tools/preview_brand.swift (brand board)
docs/                             guides/, plans/, reference/, reports/ (see docs/README.md), plus asset roots companion-concepts/ and previews/
```

## Build and test

**Mac**

```bash
scripts/test.sh                 # Swift tests; works before Xcode's licence is accepted
scripts/build-app.sh            # builds and signs build/F2L.app
scripts/run.sh                  # builds, opens F2L and follows its log
build/F2L.app/Contents/MacOS/F2L --render build/render   # draws every view to PNGs and checks screen reading, no network
build/F2L.app/Contents/MacOS/F2L --soak 10              # CPU and memory per phase (idle, lesson, circle, 50 replies, screen reading)
build/F2L.app/Contents/MacOS/F2L --export-emotes         # rewrites Windows/F2L.Windows/Assets/Pip/Emotes from Pip's poses
F2L_LIVE_DEEPSEEK=1 scripts/test.sh --filter LiveDeepSeek    # one real question to DeepSeek with your key
```

F2L must run as `build/F2L.app` (macOS grants microphone and screen permissions to app bundles). Run `scripts/setup-signing.sh` once (see [SETUP.md](SETUP.md)); every build then signs with that certificate automatically, so macOS remembers those permissions across rebuilds. The launcher also rebuilds an app that lost the signature.

**Windows** (from the repository root)

```powershell
dotnet run --project Windows/F2L.Windows/F2L.Windows.csproj
dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj
```

See [Windows/README.md](Windows/README.md) for the Windows harness options, including the optional live Excel check.

## Demo
<p align="center" width="100%">
  <video src="https://github.com/user-attachments/assets/68abd1bb-9583-4bb2-8660-0b57e2eba7a5" width="80%" controls></video>
</p>

