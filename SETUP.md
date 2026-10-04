# Setup checklist

These are the things only you can do: accounts, keys, signing, permissions, and a few facts to confirm.
Work through them in order. Everything else is already in the repo.

---

## 1. Check your Mac (2 min)

- [ ] macOS 15 or newer, Apple Silicon. This Mac has macOS 15.7 with Xcode 26.2 and Swift 6.2, which is enough.
- [ ] Confirm the tests pass: `swift test` (31 tests).

## 2. Give the app a stable signing identity (10 min). Do this before anything else.

macOS remembers the Screen Recording and Accessibility permissions for a specific signed app.
Builds are currently **ad-hoc signed**: the Mac has no signing certificate (`security find-identity -v -p codesigning` lists 0).
Ad-hoc signing means **every rebuild looks like a new app**, so macOS asks for permissions again, possibly in the middle of a recording.

Pick one of these:

- **Option A: free Apple ID (recommended).** In Xcode, go to Settings → Accounts, add your Apple ID, then Manage Certificates → `+` → **Apple Development**.
- **Option B: self-signed.** In Keychain Access, choose Certificate Assistant → Create a Certificate…, enter Name `Beacon Dev`, set Identity Type to *Self Signed Root* and Certificate Type to *Code Signing*.

Then:

```bash
security find-identity -v -p codesigning        # must say "1 valid identities found"
```

`ABCDE12345` in the example below is a placeholder. **Don't type it.** Copy the real name, or the 40-character code at the start of the line, from the command above.

```bash
echo 'export SIGN_IDENTITY="szeisaac1126@gmail.com (V69DY6BUVP)"' >> ~/.zshrc
source ~/.zshrc
./scripts/build-app.sh                           # should no longer print the ad-hoc warning
```

**If it says "0 valid identities found" even though the certificate exists** (`security find-identity -p codesigning` without `-v` lists it), your Mac is missing Apple's current intermediate certificate, so the chain can't be verified. Fix:

```bash
curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
```

Run the `find-identity -v` command again. The first time you build, macOS may ask for your login password to use the key: choose **Always Allow**.

Every teammate who builds the app needs to do this on their own Mac.

## 3. Create the API keys (15 min)

| Service | What it's used for | Where | Notes |
|---|---|---|---|
| **z.ai** (required) | The coach's brain (sees the screenshot, decides where to point) | https://z.ai → API Keys | The default model `glm-4.6v` costs about $0.30 per 1M input tokens. Add a small balance. `glm-4.6v-flash` is free if you want to experiment. |
| **ElevenLabs** (required for a natural voice) | The coach's voice | https://elevenlabs.io → Profile → API key | The free tier works; the app uses `pcm_22050`, which every tier allows. Without a key the app falls back to the robotic macOS voice. |
| Anthropic (optional) | Fallback brain if z.ai doesn't work out | https://console.anthropic.com | Switch the provider in Settings to use it. |

Two ways to give the app its keys:
- **A `.env` file (easiest for development).** Run `cp .env.example .env` in the project folder, paste the keys after the `=` signs, and relaunch Beacon. The file is git-ignored. It overrides anything saved in Settings.
- **In the app:** hover the bar at the top of the screen, click **⋯**, then **Settings…**. The keys are saved to your macOS Keychain.

Shell exports such as `export ZAI_API_KEY=…` only reach the app if you start its binary from that same terminal, not with `open` or `./scripts/run.sh`. Use `.env` instead.

- [ ] **Choose a voice:** in Settings, set *Voice ID* to a warm, patient voice from your ElevenLabs Voice Library. The default is the premade voice "George" (`JBFqnCBsd6RMkjVDRZzb`). Press **Test voice**.

## 4. First run and permissions (5 min)

```bash
./scripts/run.sh        # builds, launches, and follows the logs
```

The onboarding window asks for four permissions: **Microphone, Speech Recognition, Screen Recording, Accessibility**.
After you allow Screen Recording, click **Restart Beacon**, because macOS only applies that permission after a relaunch.
Tick "I've closed anything private", then click **Start**.
A menu-bar icon (a beacon light) also gives you Settings, Pause and Quit, in case the top bar is hard to reach.

- [ ] To rehearse the first-run flow again from scratch, run `./scripts/reset-permissions.sh`.
- [ ] Do one cold run on a **fresh macOS user account** before demo week. That's the real first-run experience.

## 5. Confirm two facts the app relies on (before the Oct 18 submission)

- [ ] **z.ai data retention.** The start screen says what each vendor receives, and that "their data policy applies". Read z.ai's API terms. If they keep inputs, or train on them, by default, say so plainly in `PrivacyCopy` in [Sources/Beacon/Support.swift](Sources/Beacon/Support.swift). Do the same for ElevenLabs. Judges for a Future Work track may ask about data sent to a China-based provider, so have the answer ready.
- [ ] **z.ai image format.** Screenshots are sent as `data:image/jpeg;base64,…` URLs. The z.ai docs say "URL or Base64" without showing which form. If the first screen-aware question returns an HTTP 400 that mentions the image, change `ImageAttachment.dataURL` in [Sources/CoachCore/Models.swift](Sources/CoachCore/Models.swift) to return just `jpegBase64`.

## 6. Run the week-1 model spike (half a day, decide by day 3–4)

Follow [docs/SPIKE.md](docs/SPIKE.md). In short: save about 15 snapshots of real ChatGPT, Gemini and Copilot screens, write the expected answer for each, then run:

```bash
ZAI_API_KEY=… swift run beacon-spike ~/Library/Application\ Support/Beacon/spike-cases --model glm-4.6v
ZAI_API_KEY=… swift run beacon-spike ~/Library/Application\ Support/Beacon/spike-cases --model glm-5.3-flashx
```

- [ ] Pick the model that reaches **≥80% hit rate** with the faster first-token time, and set it in Settings → Coach model.
- [ ] If neither passes, switch the provider to Anthropic and rerun the spike with `--provider anthropic`.

## 7. Check Chrome exposes its buttons (5 min)

Beacon turns on Chrome's web accessibility automatically, so it can circle exact buttons. To confirm it worked:

- [ ] Open ChatGPT in Chrome, then run `log stream --predicate 'subsystem == "app.beacon.coach" AND category == "screen"' --level debug`, ask a question, and look for `Context: Google Chrome – N controls`. N should be in the dozens.
- [ ] If N is around 0–5, open `chrome://accessibility` and turn on **Web accessibility**, then try again. If it's still empty, the coach falls back to approximate "around here" circles.

## 7b. If speech recognition is poor

**First, turn on Dictation:** System Settings, then Keyboard, then Dictation. macOS blocks speech recognition entirely while it's off (log line: `kLSRErrorDomain 201: Siri and Dictation are disabled`). If the microphone meter moves but nothing is recognised, this is why.

Open Settings (hover the top bar, **⋯**, **Settings…**) and use **Test microphone and speech**. It reports the microphone, its loudness, and what was heard, with a **Play back** button. The usual fixes are choosing the right microphone, changing the language to English (Hong Kong) or English (UK), or turning off "Keep my voice on this Mac". The full list is in [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md#speech-not-working). You can also type questions in the bar's text box.

## 8a. Bug reports (optional switch)

The **Bug** button saves a report into `bug-reports/` for later debugging (see [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md#report-a-bug)). To turn the feature off, put `BEACON_BUG_REPORTS=off` in `.env`. Remove the line, or set `on`, to turn it back on. No restart is needed.

## 8. Measure latency (10 min)

Each spoken reply logs a line like `speech→request …, request→first token …, TOTAL speech→audio …`, and the island shows "1.8s to first word".

- [ ] Target: **under 2.5 s** from letting go of the key to hearing the first word. If it's slower, try `glm-4.6v-flashx` or `glm-5.3-flashx`, or turn off the background summary in Settings.

## 9. Decide the name (before recording)

- [ ] "**Beacon**" is a working name. "Solo-Leveling" is also the title of a well-known Korean web novel and anime, which is a trademark risk for a public pitch, so use it only as an internal codename. To rename the app, change `CFBundleName` and `CFBundleDisplayName` in [App/Info.plist](App/Info.plist), the first line of `PromptBuilder.systemPrompt`, and the onboarding title in [Sources/Beacon/Windows.swift](Sources/Beacon/Windows.swift).

## 10. Prepare the demo Mac (the day before recording)

- [ ] Use a dedicated macOS user account, logged into ChatGPT in Chrome, with nothing else open.
- [ ] Turn on Do Not Disturb, and pause Chrome and macOS updates until Oct 24.
- [ ] Record with QuickTime (File → New Screen Recording). The circle and the top bar appear in recordings.
- [ ] Record scene (a), a blank ChatGPT page with "how do I start?", and scene (c), "what's this?" with the coach pointing at an unfamiliar control, in **one continuous take** with someone who has **never used Beacon**. Keep a teammate-run backup take.
- [ ] Use a quiet room and a decent mic. Apple's speech recognition is good, but not in a noisy hall.

---

## What has and hasn't been verified

**Verified on this Mac:** the package builds with no warnings, the 31 unit tests pass, the `.app` bundle builds and signs with the microphone entitlement, and the app launches and shows the onboarding window.

**Not verified, because it needs your keys, permissions or voice:**
- live calls to z.ai or ElevenLabs
- speech recognition
- Accessibility coverage on ChatGPT, Gemini and Copilot
- where the circle lands on a real page
- proactive nudges
- end-to-end latency

Steps 4–8 above are how you check each of these.
