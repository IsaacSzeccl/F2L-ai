"""Offline regressions for credential checks; all credential fixtures are generated fakes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from check_secrets import findings, private_path

SCANNER = str(Path(__file__).with_name("check_secrets.py"))


class SecretChecks(unittest.TestCase):
    def test_provider_keys_and_private_keys(self):
        tokens = ["sk-" + "a1" * 24, "sk_" + "z9" * 24, "AIza" + "a" * 35,
                  "sk-ant-" + "b2" * 24, "a" * 32 + "." + "b" * 16,
                  'ElevenLabsApiKey = "' + "a1" * 32 + '"',
                  "ELEVENLABS_API_KEY=" + "b2" * 32,
                  "-----BEGIN " + "PRIVATE KEY-----"]
        for token in tokens:
            for encoding in ["utf-8", "utf-16"]:
                self.assertTrue(list(findings(token.encode(encoding))))

    def test_empty_templates_and_setting_names(self):
        self.assertFalse(list(findings(b'ZAI_API_KEY=\nANTHROPIC_API_KEY=\n')))
        self.assertFalse(list(findings(b'{"DeepSeekApiKey":"", "ElevenLabsApiKey":""}')))
        self.assertFalse(list(findings(b'keyName = "DeepSeekApiKey" : "ElevenLabsApiKey"')))
        self.assertFalse(private_path("Windows/local.settings.example.json"))
        self.assertFalse(private_path(".env.example"))

    def test_private_file_names(self):
        for path in ["nested/local.settings.json", "nested/local.settings.json.bak", ".env.production",
                     "signing.p12", "keychain-password", "diagnostics/window.jpg", "sessions/1.json"]:
            self.assertTrue(private_path(path), path)

    def test_staged_secret_stays_blocked_after_worktree_cleanup_or_deletion(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)
            git("init", "-q")
            path = Path(directory, "a file\nwith whitespace.txt")
            token = "sk_" + "a9" * 24
            path.write_text(token)
            git("add", ".")
            for deleted in [False, True]:
                if deleted:
                    path.unlink()
                else:
                    path.write_text("clean")
                result = subprocess.run(["python3", SCANNER, "--all"], cwd=directory, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertNotIn(token, result.stdout + result.stderr)
                self.assertIn("[REDACTED]", result.stdout)

    def test_deleted_historical_secret_and_push_hook(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=directory, stderr=subprocess.PIPE).decode().strip()
            git("init", "-q")
            git("config", "user.name", "Scanner test")
            git("config", "user.email", "scanner@example.invalid")
            path = Path(directory, "old.txt")
            token = "sk-" + "c3" * 24
            path.write_text(token)
            git("add", ".")
            git("commit", "-qm", "fixture")
            git("rm", "old.txt")
            git("commit", "-qm", "delete fixture")
            for args, stdin in [(["--history", "--ref", "HEAD"], None),
                                (["--pre-push"], "refs/heads/test " + git("rev-parse", "HEAD") + " refs/heads/test " + "0" * 40 + "\n")]:
                result = subprocess.run(["python3", SCANNER, *args], cwd=directory, input=stdin, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertNotIn(token, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
