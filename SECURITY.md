# Credential protection

F2L reads API credentials from environment variables, private `local.settings.json` files, or the operating system credential store. Templates contain empty values. The current app has no ElevenLabs network client; spoken replies are disabled.

API requests use fixed HTTPS provider endpoints. The production HTTP clients refuse redirects so keys and request bodies cannot be forwarded to a different endpoint. Provider error bodies are never displayed or saved as errors because they may echo credentials. Windows builds and publish output exclude `local.settings.json`.

Local signing uses a per-machine random password stored in `~/Library/Application Support/F2L/Signing/keychain-password`, with mode `600`. Signing keys and passwords must stay outside Git. Older local development commits contained a shared signing password; the publication snapshot excludes those commits, and the development Mac's password was rotated without replacing its certificate.

The learner profile (`profile.json`) is personal data, not a credential: it is written with mode `600`, kept out of Git with the other per-user data, and never contains keys.

## Before committing or pushing

Python 3 and Git are required:

```bash
scripts/check-secrets.sh --install             # install commit and push hooks on this clone
scripts/check-secrets.sh                       # scan the complete staged index
scripts/check-secrets.sh --all                 # index + tracked/nonignored working files
scripts/check-secrets.sh --history --ref HEAD  # all history reachable from this branch
python3 -m unittest discover -s scripts -p 'test_check_secrets.py'
```

The scanner detects common provider keys (including DeepSeek and ElevenLabs), named credential assignments, bearer tokens, GitHub/AWS tokens, private keys, and private filenames. It checks UTF-8 and UTF-16 text and never prints matched values. Staged content is read from Git, even if the working file was cleaned or deleted afterward. The push hook checks the history of each outgoing commit, including files deleted in later commits. Existing unrelated hooks are preserved; compose them manually if installation reports a conflict. GitHub Actions repeats the scan on pushes and pull requests.

`.gitignore` excludes private settings, environment files, signing material, session data, logs, diagnostics, and build output. Ignoring a file does not remove previously committed copies. Keep diagnostic exports and screenshots private: they can contain workbook or screen contents even without recognizable API keys.

## Scope and incident response

Pattern checks are a guardrail, not proof that arbitrary or encoded credentials are absent. GitHub Actions runs after upload; install the local hooks to check before upload. Hooks can be bypassed and are not automatically installed on new clones. Branch protection requires repository administration access and is not configured by this change.

If a real key reaches a commit, revoke or rotate it with its provider first. Removing the current file is insufficient: review historical commits, branches, tags, pull requests, artifacts, and logs, and coordinate history cleanup with repository collaborators. Do not paste a credential into an issue, pull request, or scan report.
