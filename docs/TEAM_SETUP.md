# Team setup: get Beacon running on your Mac

About 30 minutes. Do the steps in order. If something fails, see [Problems](#problems) at the bottom.

## What you need

| Need | Details |
|---|---|
| A Mac | Apple Silicon, macOS 15 or newer. Windows and Intel Macs are not supported. |
| Xcode | Install from the App Store, open it once and accept the license. Beacon was built with Xcode 26; older versions are untested. |
| Headphones or a quiet room | The coach hears itself through speakers and can mix it into your question. |
| Chrome, logged into ChatGPT | The demo target. |

## Which services Beacon uses

| What | Service | Account needed? | Cost |
|---|---|---|---|
| **Speech to text** | Apple, built into macOS | No | Free |
| **Brain** (sees the screen, decides what to circle) | [z.ai](https://z.ai) | **Yes, API key** | About $0.30 per 1M input tokens; add a few dollars |
| **Voice** (text to speech) | [ElevenLabs](https://elevenlabs.io) | **Yes, API key** | Free tier to start |
| Fallback brain (optional) | [Anthropic](https://console.anthropic.com) | Optional | Pay per use |
| Fallback voice | Apple's built-in voice | No | Free |

**There is no cloud, server or database to set up.** Beacon runs entirely on your Mac and talks straight to z.ai and ElevenLabs. Nothing is stored anywhere except your API keys in your own macOS Keychain.

## Step 1: Get the code

```bash
git clone <repo-url> solo-level
cd solo-level
```

Ask the repo owner for the URL. The project folder isn't a git repository yet, so someone has to push it to GitHub first.

## Step 2: Get API keys (one person, then share safely)

One person creates the accounts and shares the two keys with the team through a password manager. **Never paste keys into the repo, a chat, or an email.**

1. **z.ai:** sign in at https://z.ai, open API Keys, and create a key. Add a small balance.
2. **ElevenLabs:** sign in at https://elevenlabs.io, open Profile, then API key. In the Voice Library, pick a calm, friendly voice and copy its **Voice ID**. The default is a premade voice called "George".

## Step 3: Create a signing certificate (once per Mac)

Without this, macOS forgets Beacon's permissions after every rebuild and asks again, possibly in the middle of a recording.

1. Open Xcode, then Settings, then Accounts, and add your Apple ID (free is fine).
2. Click **Manage Certificates…**, press `+`, and choose **Apple Development**.
3. In Terminal, find the certificate name and save it:

```bash
security find-identity -v -p codesigning
echo 'export SIGN_IDENTITY="Apple Development: you@example.com (ABCDE12345)"' >> ~/.zshrc
source ~/.zshrc
```

Paste the exact quoted name from the first command into the second (`ABCDE12345` is a placeholder; use the real code from your output).

If the first command says **0 valid identities found**, install Apple's intermediate certificate and run it again:

```bash
curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
```

## Step 4: Run it

```bash
./scripts/run.sh
```

This builds the app, launches it, and shows live logs (press Ctrl-C to stop watching; Beacon keeps running).

1. A welcome window opens. Under **Permissions**, click **Allow** on all four: Microphone, Speech Recognition, Screen Recording, Accessibility.
2. After allowing Screen Recording, click **Restart Beacon**. macOS only applies that permission after a restart.
3. Tick "I've closed anything private", then click **Start**.
4. A small black bar appears at the top of the screen. Hover over it, click **⋯**, then **Settings…**.
5. Give the app its keys, either way:
   - **Easiest:** in the project folder run `cp .env.example .env`, paste the keys after the `=` signs, and relaunch Beacon. `.env` is git-ignored.
   - **Or** in Settings: paste the z.ai and ElevenLabs keys, set the Voice ID, and click **Save**.

   Then use **Settings**, then **Test voice**: you should hear the coach speak.

To quit Beacon: click the beacon icon in the menu bar, then **Quit Beacon** (or hover the top bar, click **⋯**, then **Quit Beacon**). In Terminal: `pkill -x Beacon`.

## Step 5: Try it

1. Open ChatGPT in Chrome.
2. **Hold the right ⌥ Option key**, say "Where do I type my question?", and let go.
3. You should hear an answer within about 2 seconds and see an orange ring on the message box.
4. Type something, and the coach should speak up with the next step.

To interrupt the coach, press the key again. The menu-bar icon (a beacon light) also has Pause, Start over, and Quit.

## Useful commands

```bash
swift test                    # run the unit tests (should say 31 passed)
./scripts/run.sh              # build, launch, follow logs
./scripts/build-app.sh        # build only
./scripts/reset-permissions.sh   # forget all permissions to rehearse first-run
```

Watch the latency (time from letting go of the key to hearing the first word):

```bash
log stream --predicate 'subsystem == "app.beacon.coach" AND category == "latency"'
```

The goal is under 2.5 seconds.

## Problems

| What you see | Fix |
|---|---|
| "Beacon must run as an app bundle" | Run `./scripts/run.sh`, not `swift run Beacon`. |
| Permissions asked again after each rebuild | Step 3 wasn't done. Check `echo $SIGN_IDENTITY` prints a name. |
| Screen Recording is granted but Beacon can't see | Click **Restart Beacon**; macOS needs a relaunch. |
| Bar says "Add your AI API key" | Open Settings (hover the bar, **⋯**) and save the z.ai key. |
| Voice is robotic | The ElevenLabs key is missing or wrong. Check Settings, then **Test voice**. |
| The coach says it couldn't reach the AI service | Check the z.ai key and balance. See the log for an `HTTP 4xx` line. |
| z.ai error mentions the **image** | Report it. It's a one-line fix in `ImageAttachment.dataURL` in `Sources/CoachCore/Models.swift`. |
| Circles are dashed "around here", not exact | Chrome isn't exposing its buttons. Open `chrome://accessibility` and turn on **Web accessibility**, then retry. |
| It mishears or hears nothing | See [Speech not working](#speech-not-working) below. |
| Can't find the bar on a MacBook | It sits around the notch; use the menu-bar beacon icon instead. |

## Report a bug

Something wrong? Hover the top bar and press the **Bug** button (or use the menu-bar icon, then **Report a bug…**). Write what you did and what went wrong, then **Save report**.

The report is saved in the project's `bug-reports/` folder: your note, the last question, what the coach saw and said, which circles it tried to draw, the screenshot it was given, logs, settings and permissions. It stays on your Mac and is git-ignored.

**To turn bug reports off**, add `BEACON_BUG_REPORTS=off` to your `.env` file (or export it before launching). The Bug buttons disappear and nothing is captured or saved; the screenshot and last-turn details are not even kept in memory. Delete the line, or set it to `on`, to bring it back. Changes to `.env` apply the next time the top bar opens, with no restart. Accepted off values: `off`, `0`, `false`, `no`, `disabled`.

Then ask Claude: *"read the latest bug report in bug-reports/ and fix it."*

## Speech not working

Work through these in order. Each takes under a minute.

0. **Turn on Dictation first.** In System Settings, go to **Keyboard**, then **Dictation**, and switch it on (confirm the prompt). macOS refuses to run speech recognition at all while it's off, even though Beacon's recognition runs on your Mac. The symptom is a working microphone but "no words recognised", and the log line `kLSRErrorDomain 201: Siri and Dictation are disabled`.
1. **Run the built-in test.** Hover the top bar, click **⋯**, then **Settings…**, and press **Test microphone and speech (5 s)**. Say a sentence. It shows the microphone's name, how loud it was, what was heard, and what's wrong. **Play back** lets you hear what the Mac actually recorded.
2. **Pick the right microphone.** In Settings, set **Microphone** to your Mac's own mic (for example "MacBook Air Microphone"), not "External Microphone", BlackHole, Zoom or Teams. "System default" follows whatever macOS has chosen, which is often the wrong one.
3. **Change the language** to match your accent. English (Hong Kong) or English (UK) often works better than English (US) for Hong Kong speakers.
4. **Turn off "Keep my voice on this Mac"** for better accuracy. Apple's servers then do the recognising, so your voice leaves the Mac; the start screen text updates to say so.
5. **Wait for "Listening…"** before you speak, and keep holding the key until you finish. Beacon records a quarter of a second past the release to catch the last word.
6. **Use the text box** if speech still fails: hover the bar and type under "Or type your question…", or use the menu-bar icon, then **Type a question…**.

Watch what the recogniser hears, live:

```bash
log stream --info --predicate 'subsystem == "app.beacon.coach" AND category == "voice"'
```

You'll see lines like `Listening: mic=… locale=… onDevice=…` and `Heard (3.1s, peak -18 dBFS): "…"`. A peak below -40 means the microphone is too quiet or the wrong one.

## What goes where in the code

| Area | Folder | Good first owner |
|---|---|---|
| Decisions and why | `docs/DECISIONS.md` | everyone, read first |
| Reads buttons, takes screenshots | `Sources/Beacon/AccessibilityReader.swift`, `ScreenCapturer.swift` | whoever knows macOS APIs |
| Voice in and out | `Sources/Beacon/SpeechInput.swift`, `SpeechOutput.swift` | |
| Circle on screen, top bar, orb | `Sources/Beacon/Overlay.swift`, `Island.swift` | whoever knows SwiftUI |
| Prompts, AI calls, tool logic | `Sources/CoachCore/` | |
| Choosing the AI model | `docs/SPIKE.md` | one person, in the first days |

More detail: [SETUP.md](../SETUP.md) has the owner's checklist, and [README.md](../README.md) explains how it works.
