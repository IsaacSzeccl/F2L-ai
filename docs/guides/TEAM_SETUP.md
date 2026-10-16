# Team setup: get F2L AI running on your computer

About 20 minutes on either platform. If something goes wrong, see [Problems](#problems).

## What you need

| | Mac | Windows |
|---|---|---|
| System | macOS 15 or newer (Apple Silicon tested) | Windows 10 or 11 |
| Tools | Xcode, or just the Command Line Tools (`xcode-select --install`) | [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) |
| Key | Your own DeepSeek API key (ElevenLabs optional) | same |
| Nice to have | Desktop Microsoft Excel, to try cell outlines; headphones | same |

There's no server, account or database to set up. F2L runs on your computer and talks straight to DeepSeek (and ElevenLabs if you add a key).

## Step 1: Get the code

```bash
git clone <repo-url> F2L-ai
cd F2L-ai
```

## Step 2: Add your key

Create `local.settings.json` in the `F2L-ai` folder (it's Git-ignored):

```json
{ "DeepSeekApiKey": "sk-…", "ElevenLabsApiKey": "" }
```

Use your own key and never commit it. Other places F2L can read keys from are listed in the [README](../../README.md#keys).

## Step 3 (Mac only): sign once

```bash
scripts/setup-signing.sh
echo 'export SIGN_IDENTITY="F2L Local Signing"' >> ~/.zshrc && source ~/.zshrc
```

Without this, macOS forgets F2L's permissions every time it's rebuilt.

## Step 4: Open Pip

Double-click **Open F2L Companion.command** (Mac) or **Open F2L Companion.bat** (Windows). The first run builds F2L, which takes a minute. To add an **F2L Companion** shortcut to your Desktop, run the launcher once with `--install-shortcut`.

Pip appears in the bottom corner of the screen. Click Pip to open the conversation.

On a Mac, macOS asks for permissions the first time each feature is used (Screen Recording for screen questions, Microphone and Speech Recognition for dictation). Adding F2L under Accessibility is optional; it lets Pip fade when your text cursor comes near. After allowing Screen Recording, quit F2L from Pip's **···** menu and open it again.

## Step 5: Try it

1. Open any app, then click Pip and ask "What can I do on this screen?". Pip should answer out loud and mention what it sees.
2. On Windows, open desktop Excel and ask "circle B2". A solid green outline should sit on B2 and Pip should point at it. (On Mac, Pip names the cell but can't outline it yet.)
3. Click **Speak**, say a question, click **Finish**, check the words and press Enter.

## Useful commands

**Mac**

```bash
scripts/test.sh                    # Swift tests (all should pass)
scripts/run.sh                     # build, open F2L, follow its log
scripts/build-app.sh               # build only
scripts/reset-permissions.sh       # forget F2L's permissions to rehearse the first run
log stream --style compact --predicate 'subsystem == "ai.f2l.companion"'   # F2L's log
```

**Windows**

```powershell
dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj    # regression harness
dotnet run --project Windows/F2L.Windows/F2L.Windows.csproj               # run without the launcher
```

## Problems

| What you see | Fix |
|---|---|
| "DeepSeek isn't configured" | The key wasn't found. **··· › Settings…** shows which file F2L reads; **Show file** opens it. |
| "DeepSeek rejected the configured API key (401)" | Replace the key in that file. |
| "…no available balance (402)" | Top up the DeepSeek account. |
| Mac asks for permissions after every rebuild | Run `scripts/setup-signing.sh`, rebuild, grant once more. |
| Mac: Screen Recording is on but Pip can't see the app | Quit F2L from Pip's menu and open it again. |
| "circle A1" says it can't verify the cell | Make sure it's desktop Excel (not Excel in a browser), the cell is fully visible, and no Excel dialog or cell edit is open. On a Mac, cell outlines aren't available yet. |
| The voice sounds robotic | No ElevenLabs key, or it was rejected; the status line under the conversation says which. |
| Dictation hears nothing | Check the microphone permission and input device. On Windows, a speech recogniser for your display language must be installed. |
| Windows: "The .NET 10 SDK is needed" | Install it from the link above, then run the launcher again. |
| `swift test` fails on a Mac without Xcode's licence accepted | Use `scripts/test.sh`, which works with the Command Line Tools. |

## What goes where

| Area | Mac | Windows |
|---|---|---|
| Shared rules: prompt, DeepSeek client, conversation file, settings lookup, cells, placement, Pip's poses | `Sources/CoachCore/` | the same-named `.cs` files in `Windows/F2L.Windows/` |
| Main window, conversation turn, highlights | `Sources/F2L/Companion.swift` | `MainWindow.xaml(.cs)`, `MainWindow.Guidance.cs` |
| Conversation list and reading follow | `ConversationView.swift` | `ConversationView.xaml(.cs)` |
| Pip's artwork and animation | `Pip.swift` | `PipView.xaml(.cs)`, `PipSprites.cs` |
| Screen picture, window tracking | `ScreenCapture.swift` | `ScreenCaptureService.cs`, `ForegroundAppTracker.cs`, `NativeDesktop.cs` |
| Excel cells, text caret | `ExcelTargetResolver.swift` (not yet able to verify), `Accessibility.swift` | `ExcelTargetResolver.cs`, `NativeDesktop.cs` |
| Voice in and out | `Voice.swift` | `VoiceServices.cs` |
| Artwork and fonts (shared) | `Windows/F2L.Windows/Assets/` | same |

When you change one platform's shared rules, change the other's to match and run both test suites. Decisions and their reasons are in [DECISIONS.md](../reference/DECISIONS.md).
