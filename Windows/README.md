# F2L on Windows

Pip is a floating desktop companion. Tap Pip to open a compact conversation panel; drag Pip or the panel header to move it. Minimise the panel to return to just the character. Opening or minimising it keeps the conversation and any pending reply.

## Run

Install the .NET 10 SDK, then double-click **Open F2L Companion.bat** in the repository root. It builds F2L when the code has changed and opens Pip; run it once with `--install-shortcut` to add an **F2L Companion** shortcut to the Desktop. Opening F2L again while Pip is running brings the conversation up, as on a Mac. To run without the launcher:

```powershell
dotnet run --project Windows/F2L.Windows/F2L.Windows.csproj
```

See the [project change log](../CHANGELOG.md) for the implementation record and the [asset inventory](../docs/ASSET_INVENTORY.md) for stored artwork, prompts, fonts and archived UI previews.

## Conversation and voice

- Type at the bottom and press **Enter**. **Shift + Enter** inserts a new line.
- Previous questions and replies remain above the input. Text can be selected; each completed reply has **Read** and **Copy**.
- **Follow reply** follows speech progress, or advances at a reading pace when muted. Scrolling or selecting text pauses following. Resume with **Follow reply**, or jump down with **Latest**.
- The top-right diagonal arrow expands the panel. The cross minimises it.
- **Speak** starts dictation; **Finish** leaves the recognised words in the input for review before sending. The installed Windows recogniser is selected by the display language when possible.
- Pip is silent for now: replies appear word by word in a card beside Pip, and tasks become step-by-step lessons (Done / Show me again / I'm stuck, Excel steps that tick themselves). Questions go in a bar at the bottom centre. Each launch opens with the F2L AI animation.
- The latest 500 messages and unsent draft are saved at `%LOCALAPPDATA%\F2L\conversation.json`, with a backup. They survive restart. Screenshots, audio and keys are not stored in the conversation file.
- Pip's menu controls character size, screen sharing, highlights, settings and quitting.

The UI bundles [Inter 4.1](https://github.com/rsms/inter/releases/tag/v4.1) under the SIL Open Font License in `F2L.Windows/Assets/Fonts/LICENSE.txt`.

## Painted Pip and direct teaching

Pip now uses the original amber lantern design as generated, transparent 2D painted textures. Two bundled atlases contain 32 poses for expressions, blinking, speaking, listening, thoughtful concentration, directional pointing, side views and walking. The old shape-drawn character has been replaced. [Artwork and exact generation prompts](F2L.Windows/Assets/Pip/ARTWORK.md) describe the sources and frame choices.

Replies start with the action or answer. The default is one useful step in 1–3 short sentences; the coach omits praise, preambles and invitations to ask more. Requested explanations can still be longer. A final cleanup removes common standalone filler without cutting formulas or essential warnings.

With **Pip walks to what it’s teaching** turned on in Settings, Pip moves from its resting place to a safe slot beside the marker and uses a pointing pose facing the target. Its teaching window passes clicks through. It disappears briefly when your pointer or a visible text caret approaches, and avoids crossing the target or conversation panel during travel. If no slot fits, Pip stays at its resting place. The conversation stays accessible; minimising it brings Pip back.

Use the **···** menu in the panel header or beside resting Pip to disable target following or enable **Reduce animation**. Reduced motion holds still frames and skips travel animation. The initial setting respects Windows animation preferences. These controls currently apply to the running session.

## Screen guidance

With **Share my screen with Pip** on, F2L remembers the last external app you used, so clicking Pip or typing in its panel keeps that app selected. Submitting a question pins that window, briefly hides Pip, brings the selected app forward and captures its visible client area. General questions and that image go to DeepSeek. Screen images are not written to disk. Window tracking remembers identity only; it does not capture images in the background.

If the window closes, is minimised, or changes during capture, a general question is still sent without an image, and the panel explains that screen context was unavailable. A direct cell-pointing request gives a screen-context explanation instead of inventing a position. Enter is handled before the multiline text box consumes it; Shift+Enter inserts a newline, and Enter used to confirm IME typing does not send.

**Desktop Excel cells:** a direct request such as “circle A1” uses a local, read-only Excel lookup. It obtains the visible cell's position for the current pane and zoom, then asks Excel which cell occupies three points inside that rectangle. A suggested B1 cannot satisfy a request for A1. F2L does not select, edit, scroll or save the workbook. A green outline means the cell was verified. Offscreen, hidden, ambiguous or unavailable cells receive an explanation instead of a guessed outline. Merged cells use their merged area. Single-cell addresses refer to the active sheet.

F2L moves its panel away from the target when space permits. Verified Excel highlights and Pip's position are rechecked approximately every 400 ms; cell positions are resolved again after scrolling or moving the Excel window. The highlight and following companion clear when the cell becomes unavailable, the sheet changes, or a different app becomes active. Approximate screenshot regions still clear when the source window moves rather than pretending to track changing page contents.

**Other apps:** model-proposed screenshot regions have a dashed amber outline and remain approximate. They expire after 20 seconds or when the source window changes. These regions cannot verify a click or completed task. Browser Excel, named-sheet references and ranges do not have exact cell support yet; screenshot guesses are not used to circle cells.

## Local configuration

Keys go in a `local.settings.json` file: `DeepSeekApiKey` and optional `ElevenLabsApiKey`. F2L reads the environment variables first, then the first file found of `%APPDATA%\F2L\local.settings.json`, the repository root, the older `Windows/F2L.Windows/` copy and the file next to the executable, then Credential Manager (`F2L/DEEPSEEK_API_KEY`). This is the same order as the Mac app. **Settings › Show file** shows the file in use and creates an empty one if needed. No key-entry form is added to the companion. The configured coach model is `deepseek-flash`. ElevenLabs uses timestamped speech to follow the spoken text, with Windows speech progress events on fallback.

## Verification

```powershell
dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj -- Windows/artifacts/pip-conversation.png
# Optional: creates and discards its own blank desktop Excel workbook
dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj -- --excel-smoke
```

The regular harness uses a fake provider and does not access the microphone or capture a screen. It checks conversation recovery, cancellation, history, scrolling, font loading, cell matching, physical overlay geometry, foreground-app memory, real composer Enter events and capture-failure recovery, then optionally renders the actual WPF controls with sample text.

Validated on 8 October 2026: 150 regression checks, including all 32 transparent sprite poses, actual animation-frame changes, reduced motion, safe placement at screen edges and several scales, pointer/caret avoidance, target movement and direct-answer cleanup. A separate Excel integration run verified A1/B1 at 80%, 100% and 150% zoom, offscreen rejection, frozen panes and cell geometry after window movement. One live text-only DeepSeek request produced a concise SUM instruction. The Excel integration harness reads a test window even when Codex retains foreground focus; production retains its foreground-app guard.

## Remaining limits

The Mac companion (`Sources/F2L`) now mirrors this implementation; see the [project README](../README.md). Mixed-monitor live verification, browser cell geometry, password-field detection, full accessibility testing and installer packaging remain work. Approximate screenshot hints can become stale when contents change without moving the window. Nearby-task protection is based on target, panel, pointer and caret geometry; F2L does not understand every meaningful area of an application. Voice quality depends on the installed recogniser, microphone and provider; live microphone recognition and ElevenLabs playback were not re-tested in this update.
