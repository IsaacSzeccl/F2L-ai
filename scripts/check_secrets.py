#!/usr/bin/env python3
"""Check index, publishable working files, or reachable Git history without printing secrets."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


RULES = [
    ("provider API key", re.compile(r"\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|sk_[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{35}|[a-fA-F0-9]{32}\.[A-Za-z0-9]{16,})\b")),
    ("GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("private key", re.compile(r"-----BEGIN (?:[A-Z0-9 ]+)?PRIVATE KEY-----")),
    # Also catches legacy ElevenLabs keys with no sk_ prefix and named generic secrets.
    ("assigned credential", re.compile(r'''(?i)\b[A-Za-z0-9_.-]*(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret|password)[A-Za-z0-9_.-]*["']?[ \t]*[:=][ \t]*["']([A-Za-z0-9_./+=-]{16,})["']''')),
    ("environment credential", re.compile(r"(?m)^[ \t]*(?:export[ \t]+)?[A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*=[ \t]*[A-Za-z0-9_./+=-]{16,}[ \t]*$")),
    ("bearer credential", re.compile(r"(?i)\bBearer\s+[A-Za-z0-9_./+=-]{20,}")),
    ("URL credential", re.compile(r"https?://[^\s/:@]+:[^\s/@]{8,}@")),
]


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def private_path(path):
    parts = Path(path).parts
    name = Path(path).name.lower()
    return (name == "local.settings.json" or name.startswith("local.settings.json.")
            or (name.startswith(".env") and name not in (".env.example", ".env.template"))
            or name.endswith((".env", ".keychain", ".keychain-db", ".pem", ".key", ".p12", ".pfx", ".mobileprovision", ".log"))
            or name in (".rhistory", "conversation.json", "id_rsa", "id_ed25519", "keychain-password")
            or any(part.lower() in ("diagnostics", "sessions") for part in parts))


def findings(data):
    # Check UTF-16 settings/export files as well as ordinary UTF-8 source and binary bytes.
    encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8"
    content = data.decode(encoding, errors="replace")
    setting_names = {
        "DEEPSEEK_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY",
        "GLM_API_KEY", "ZAI_API_KEY", "ELEVENLABS_API_KEY", "DeepSeekApiKey",
        "OpenAIApiKey", "ClaudeApiKey", "GeminiApiKey", "GLMApiKey", "ElevenLabsApiKey",
    }
    for rule, pattern in RULES:
        for match in pattern.finditer(content):
            if rule == "assigned credential" and match.group(1) in setting_names:
                continue  # Literal setting names in source switches are not key values.
            yield rule, content.count("\n", 0, match.start()) + 1
            break


def check(path, data, location="", check_path=True):
    label = repr(path) + (" (" + location + ")" if location else "")
    failed = False
    if check_path and private_path(path):
        print("Blocked private file:", label)
        failed = True
    for rule, line in findings(data):
        print(f"Blocked {rule}: {label}, line {line} [REDACTED]")
        failed = True
    return failed


def scan_index():
    failed, count = False, 0
    for entry in git("ls-files", "--stage", "-z").split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, oid, stage = metadata.split()
        path = os.fsdecode(raw_path)
        if stage != b"0" or mode == b"160000":
            raise RuntimeError("Resolve unmerged entries or audit submodules separately before publishing.")
        failed |= check(path, git("cat-file", "blob", oid.decode()), "index")
        count += 1
    return failed, count


def scan_worktree():
    failed, count = False, 0
    paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    for raw_path in sorted(set(paths.split(b"\0")) - {b""}):
        path = Path(os.fsdecode(raw_path))
        if path.is_symlink():
            data = os.fsencode(os.readlink(path))
        elif path.is_file():
            data = path.read_bytes()
        elif not path.exists():
            continue  # Unstaged deletion; the index is still checked separately.
        else:
            raise RuntimeError("Cannot scan a non-file Git entry.")
        failed |= check(str(path), data, "worktree")
        count += 1
    return failed, count


def scan_history(refs=None):
    failed, count = False, 0
    # Parse trees with NUL delimiters so whitespace/newlines in names cannot bypass checks.
    objects = {}
    commits = git("rev-list", *(refs or ["--all"])).splitlines()
    for commit in commits:
        sha = commit.decode()
        failed |= check("commit message", git("show", "-s", "--format=%B", sha), sha[:12], False)
        for entry in git("ls-tree", "-rz", "--full-tree", sha).split(b"\0"):
            if not entry:
                continue
            metadata, raw_path = entry.split(b"\t", 1)
            mode, kind, oid = metadata.split()
            path = os.fsdecode(raw_path)
            if kind != b"blob":
                raise RuntimeError("Audit historical submodules separately before publishing.")
            if private_path(path):
                failed |= check(path, b"", sha[:12])
            objects.setdefault(oid, path)
    for oid, path in objects.items():
        failed |= check(path, git("cat-file", "blob", oid.decode()), "blob " + oid.decode()[:12], False)
        count += 1
    return failed, count


def install():
    hooks = Path(os.fsdecode(git("rev-parse", "--git-path", "hooks").strip()))
    hooks.mkdir(parents=True, exist_ok=True)
    targets = {"pre-commit": "", "pre-push": " --pre-push"}
    # Never replace a hook belonging to another tool.
    for name in targets:
        path = hooks / name
        if path.exists():
            content = path.read_text()
            legacy = '#!/usr/bin/env bash\nexec "' + str(Path.cwd()) + '/scripts/check-secrets.sh"\n'
            if "# F2L managed secret hook\n" not in content and content != legacy:
                raise RuntimeError(f"Existing {name} hook preserved; add scripts/check-secrets.sh manually.")
    for name, arguments in targets.items():
        path = hooks / name
        path.write_text('#!/usr/bin/env bash\n# F2L managed secret hook\nset -euo pipefail\n'
                        'ROOT="$(git rev-parse --show-toplevel)"\n'
                        'exec "$ROOT/scripts/check-secrets.sh"' + arguments + '\n')
        path.chmod(0o755)
    print("Installed secret checks: full index before commits, outgoing reachable history before pushes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--all", action="store_true", help="check index plus tracked and nonignored working files")
    mode.add_argument("--history", action="store_true", help="check all locally reachable branches/tags and commit messages")
    mode.add_argument("--install", action="store_true", help="install pre-commit and pre-push hooks")
    mode.add_argument("--pre-push", action="store_true", help="check the exact commits supplied by Git before push")
    parser.add_argument("--ref", action="append", help="with --history, audit only this reachable ref (repeatable)")
    args = parser.parse_args()
    os.chdir(os.fsdecode(git("rev-parse", "--show-toplevel").strip()))
    if args.install:
        install()
        return 0
    if args.pre_push:
        refs = []
        for line in sys.stdin:
            fields = line.split()
            if len(fields) != 4:
                raise RuntimeError("Invalid pre-push input")
            sha = fields[1]
            if set(sha) != {"0"}:
                if not re.fullmatch(r"[0-9a-f]{40,64}", sha):
                    raise RuntimeError("Invalid pre-push object")
                refs.append(sha)
        if not refs:
            return 0
        failed, count = scan_history(refs)
    elif args.history:
        failed, count = scan_history(args.ref)
    else:
        failed, count = scan_index()
        if args.all:
            working_failed, working_count = scan_worktree()
            failed |= working_failed
            count += working_count
    print(f"Scanned {count} file versions; " + ("blocked findings need review." if failed else "no credential patterns found."))
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        # Do not print command output, file contents, or exception representations.
        print("Secret scan failed (" + type(error).__name__ + "); publishing is blocked.", file=sys.stderr)
        sys.exit(2)
