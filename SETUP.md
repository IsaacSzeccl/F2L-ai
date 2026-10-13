# Owner's setup checklist

The things only you can do: keys, signing, permissions and a few checks. Everything else is in the repository.
Teammates setting up their own computer should follow [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md) instead.

## 1. Keys (10 min)

| Service | Used for | Where | Notes |
|---|---|---|---|
| **DeepSeek** (required) | Answers, and reading the shared screen picture | https://platform.deepseek.com → API keys | F2L uses `deepseek-flash` with thinking off. Add a small balance; a 402 error in Pip means it ran out. |
| **ElevenLabs** (optional) | A natural voice for spoken replies | https://elevenlabs.io → Profile → API key | Voice "George" (`JBFqnCBsd6RMkjVDRZzb`), model `eleven_flash_v2_5`. Without a key, F2L uses the computer's own voice. The free plan is non-commercial only. |

Put them in `local.settings.json` (see [README › Keys](README.md#ai-providers-and-keys) for every place F2L looks). The quickest way: open Pip, choose **··· › Settings…**, pick your AI and paste its key. Or fill in the file yourself (**Show the settings file** creates it):

```json
{ "DeepSeekApiKey": "sk-…", "ElevenLabsApiKey": "" }
```

On a Mac you can keep the key out of files entirely: `security add-generic-password -s F2L -a DEEPSEEK_API_KEY -w` (it asks for the key). Each person should use their own key; never put a key in the repository, a chat or an email.

- [ ] Check DeepSeek answers: `F2L_LIVE_DEEPSEEK=1 scripts/test.sh --filter LiveDeepSeek` (Mac) or `dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj -- --provider-smoke` (Windows).

## 2. Mac: signing, once (2 min)

macOS ties Screen Recording and Accessibility permission to how an app is signed. Ad-hoc signed builds look like a new app every time, so macOS asks again after every rebuild. Fix that once:

```bash
scripts/setup-signing.sh
```

Every build then signs with it automatically (no environment variable needed). Rebuild (the launcher or `scripts/build-app.sh`) and grant F2L's permissions one last time. The script creates a private F2L signing certificate in its own keychain file under `~/Library/Application Support/F2L/Signing` (delete that folder to undo). Its random password is stored beside it in `keychain-password` with owner-only permissions; keep the entire Signing folder private. If you have an Apple Development certificate you can use it instead: `export SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"`.

## 3. Mac: permissions (5 min)

Open Pip with **Open F2L Companion.command**. macOS asks for each permission the first time it's needed:

| Permission | Asked when | Why |
|---|---|---|
| Screen Recording | the first question with screen sharing on | to send a picture of the app you're using |
| Accessibility | optional; add F2L yourself in that list | lets Pip fade when your text cursor comes near it, as on Windows |
| Microphone, Speech Recognition | the first **Speak** | dictation, processed on the Mac when possible |

After allowing Screen Recording, quit F2L (**··· › Quit F2L**) and open it again; macOS applies that permission on relaunch. `scripts/reset-permissions.sh` clears all of F2L's permissions to rehearse the first run.

## 4. Windows (10 min)

- [ ] Install the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0), then double-click **Open F2L Companion.bat** (or run it with `--install-shortcut` to add **F2L Companion** to the Desktop).
- [ ] Windows needs no extra permissions. Dictation uses an installed Windows speech recogniser for your display language.
- [ ] Optional: `dotnet run --project Windows/F2L.Windows.Tests/F2L.Windows.Tests.csproj -- --excel-smoke` checks cell outlines against a blank workbook it creates and discards.

## 5. Check the things only a person can (before a demo)

- [ ] Ask a question about a real app with screen sharing on, on both computers. The reply should mention what's on screen.
- [ ] Windows, desktop Excel: ask "circle B2". A green outline should sit exactly on B2, follow it when you scroll or move the window, and disappear when you switch apps. (On Mac, Pip names the cell without an outline.)
- [ ] While Pip points at something, click into a text box next to it: Pip should fade while your text cursor is nearby.
- [ ] Speak a question and check the transcript before sending.
- [ ] Do one run on a fresh user account; that's the real first-run experience.

## 6. Demo day

- [ ] A dedicated user account with only the demo apps open; Do Not Disturb on; updates paused.
- [ ] Record with QuickTime (Mac) or the Xbox Game Bar (Windows); Pip, the outline and the panel all appear in recordings.
- [ ] A quiet room and a decent microphone. Keep a backup take.

## What has and hasn't been verified

The latest verification record is in [CHANGELOG.md](CHANGELOG.md). In short: the Mac app builds, its Swift tests pass and a live DeepSeek question succeeds on the owner's Mac; the Windows code is checked by its own harness on a Windows PC. Anything not listed there as verified (microphones, ElevenLabs playback, other people's screens) should be checked with the steps above.
