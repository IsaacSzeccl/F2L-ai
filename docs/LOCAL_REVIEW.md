# Local review and Mac verification

Reviewed on 4 October 2026 against commit `5626501`.
Working copy: `C:\Users\solom\OneDrive\Desktop\F2L-ai`.
These are local changes, with no commit or push performed. Claude generated the original implementation; no separate Claude session participated in this review.

## Changes

- **Pause during a request:** cancel the active turn, speech input/output and background summary task; invalidate screen reads that were already waiting. Recheck pause, cancellation, active app and password focus after window enumeration, just before requesting a screenshot. Discard capture results that finish after pause, reset or an app change, including a quick pause/resume. An image or request already handed to macOS or a vendor cannot be recalled.
- **Stale pointers:** stop a previous reply when switching to another app. Keep the original source app ID with each turn, reject pointers belonging to another app, reject missing/dead/unreadable accessibility targets, and use the target's current frame before drawing.
- **Approximate pointers without a screenshot:** omit the region tool on turns without a screenshot and reject such commands in shared pointer resolution. This also prevents the model benchmark from crediting a guessed region when no screenshot was supplied.
- **Background work:** track and cancel the summary task, prevent overlapping summary requests, and clear summary memory on Start over. Developer snapshots are not saved after their screen context is invalidated or when no screenshot is available.

Changed code: `Sources/Beacon/CoachSession.swift`, `Sources/Beacon/ScreenCapturer.swift`, `Sources/CoachCore/Pointer.swift`.
Tests: `Tests/CoachCoreTests/CoachCoreTests.swift` now has 33 test functions, including two new no-screenshot regressions and an updated screenshot-present case.

## Verification status

The changes were reviewed and checked for patch/whitespace errors on Windows. There is no Swift toolchain or macOS SDK here. **Compilation, the Swift tests, and the live app checks below have not been run.** Do not treat this review as a successful Mac build or a verified demo.

On your Mac, transfer the updated folder privately, enter it in Terminal, then run:

```sh
swift test
./scripts/build-app.sh
./scripts/run.sh
```

Use the signing and permission instructions in `SETUP.md`. Do not copy API keys into the repository.

### Live checks on the Mac

1. Ask a screen question, then pause immediately while the reply is pending. The circle and speech should stop; no late circle or reply should reappear. Repeat with a quick pause/resume, and while a background summary is pending.
2. While paused, hold right Option and ask a general question. Voice conversation should still work, without reading the screen or drawing a circle.
3. Ask about a button, then switch to a different app before the reply arrives. The old reply should stop; the previous app's circle must not appear over the new app.
4. Ask about a control, then move the window or scroll before the reply. The first precise circle should use the current control position. Remove the target before the reply and check that no stale circle is drawn.
5. Select a password field while capture is being prepared. No new screenshot should be submitted once that focus is detected.
6. Use Start over while a summary is pending. Its late result must not repopulate the reset session's summary cache.
7. In developer mode, attempt a snapshot while paused or with screenshot capture blocked. No snapshot file should be saved.

## Remaining review areas

- A switch between tabs/windows **inside the same app** needs more robust window identity tracking; the app-switch fix tracks process IDs. Approximate regions can still become stale if the page changes while a model is replying.
- The summary cache uses process ID and window title, so content changes without a title change can leave an old summary.
- Step tracking currently treats a filled text field becoming empty as submission; deleting the text can trigger the same event.
- Live provider/model compatibility, pointing coverage, speech quality and end-to-end latency remain unverified. Older setup claims and model prices are not independent test results.

## Working across Mac and Windows

The Mac is the build and demo machine. A Windows teammate can edit and review code, prompts, docs and test cases. The current app and core package use Apple frameworks, so running them on Windows requires a port; a Docker upload does not supply those frameworks or the macOS desktop. Docker may become useful for a separate server later, but there is no server to deploy in this repository today.
