"""Exercise the CI wrapper with real subprocesses, not substitute tool outputs."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

RUNNER = Path(__file__).with_name("ci_run.py")


class CiRunTests(unittest.TestCase):
    def run_command(self, source):
        return subprocess.run(
            [sys.executable, str(RUNNER), sys.executable, "-c", source],
            env={**os.environ, "GITHUB_ACTIONS": "true"},
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def test_success_is_not_replaced_with_an_error(self):
        result = self.run_command("print('actual command output')")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("actual command output", result.stdout)
        self.assertNotIn("::error", result.stdout)

    def test_success_summary_exposes_only_the_bounded_actual_output_tail(self):
        result = self.run_command("for index in range(100): print(f'ACTUAL-LINE-{index}')")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("::error", result.stdout)
        self.assertIn("ACTUAL-LINE-0\n", result.stdout)
        annotation = result.stdout.split("::notice title=Command passed 1::", 1)[1]
        self.assertIn("ACTUAL-LINE-99%0A", annotation)
        self.assertNotIn("ACTUAL-LINE-94%0A", annotation)

    def test_nonzero_exit_and_actual_stderr_are_preserved(self):
        result = self.run_command(
            "import sys; print('actual failure', file=sys.stderr); sys.exit(17)"
        )
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertIn("actual failure", result.stdout)
        self.assertIn("::error title=Command failed::", result.stdout)

    def test_long_actual_failure_output_is_reconstructible_from_annotations(self):
        import re

        result = self.run_command("print('ACTUAL-' * 1200); raise SystemExit(7)")
        self.assertEqual(result.returncode, 7, result.stderr)
        messages = re.findall(r"^::error title=[^:]+::(.*)$", result.stdout, re.MULTILINE)
        self.assertGreater(len(messages), 1)
        restored = "".join(
            message.replace("%0D", "\r").replace("%0A", "\n").replace("%25", "%")
            for message in messages
        )
        self.assertIn("ACTUAL-" * 1200, restored)

    def test_patch_chunks_are_lossless_and_below_the_real_annotation_limit(self):
        from ci_run import annotation_chunks

        diff = "línea de código 🚀\n" * 1700
        chunks = list(annotation_chunks(diff))
        self.assertEqual("".join(chunks), diff)
        self.assertTrue(all(len(chunk.encode("utf-8")) <= 3500 for chunk in chunks))

    def test_annotation_escapes_percent_and_newlines(self):
        result = self.run_command("print('100% real'); raise SystemExit(2)")
        self.assertEqual(result.returncode, 2, result.stderr)
        annotation = result.stdout.split("::error title=Command failed::", 1)[1]
        self.assertIn("100%25 real%0A", annotation)


if __name__ == "__main__":
    unittest.main()
