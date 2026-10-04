# Beacon (solo-level)

Native macOS voice coach that circles the control to click. Read `README.md` for the layout and `docs/DECISIONS.md` for why things are the way they are. Setup is in `SETUP.md` and `docs/TEAM_SETUP.md`.

## Bug reports

Testers press **Report bug** in the app. Each report is a folder under `bug-reports/` (named by timestamp; newest last when sorted).

When asked to investigate or fix a bug, or to "check the latest bug report":
1. Read `bug-reports/<newest>/report.md` first. It has the tester's note, what the model was shown, what it said, every tool call and what the app did with it, the conversation, speech details, settings and permissions.
2. Look at `screenshot.jpg` (what the model saw), then `elements.json` (the controls read from the screen) and `logs.txt`.
3. Find the cause in `Sources/`, add a regression test in `Tests/CoachCoreTests/` where the logic lives in `CoachCore`, and run `swift test`.
4. If there is no `bug-reports/` folder or no recent report, the feature may be switched off: `BEACON_BUG_REPORTS=off` in `.env` or the environment.
5. Never commit bug reports: they hold screen content and typed text (they are git-ignored).

## Build and run

- Tests: `swift test`
- App: `./scripts/run.sh`. When rebuilding from an agent shell, set `SIGN_IDENTITY` to the developer certificate hash from `security find-identity -v -p codesigning`; an ad-hoc build resets the user's macOS permissions.
- Headless check of the bug-report writer: `build/Beacon.app/Contents/MacOS/Beacon --write-test-bug-report` (writes a sample report into `bug-reports/`; delete it afterwards).
- In zsh, `log` is a shell builtin: use `/usr/bin/log show --info --predicate 'subsystem == "app.beacon.coach"'`.
