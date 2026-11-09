"""Unit tests only; mocked adb is not evidence of Android inference."""

import argparse
import unittest
from unittest.mock import patch

from evaluate_llm_android import CASES, evaluate


class EvaluateAndroidTests(unittest.TestCase):
    def setUp(self):
        self.args = argparse.Namespace(serial="device", model="/data/local/tmp/model.gguf",
                                       binary="/data/local/tmp/llama-completion", sha256="a" * 64,
                                       binary_sha256="b" * 64, timeout=1200, tokens=256)

    def values(self, answers=None):
        return ["arm64-v8a", "36", "a" * 64 + " model", "b" * 64 + " binary",
                *(answers or ["Respuesta de prueba"] * len(CASES)), "a" * 64 + " model"]

    def test_records_answers_without_claiming_tool_execution(self):
        with patch("benchmark_llm_android.adb_shell", side_effect=self.values()) as shell:
            result = evaluate(self.args)
        self.assertEqual(len(result["cases"]), len(CASES))
        self.assertTrue(all("NOT VERIFIED" in case["assessment"] for case in result["cases"]))
        for call in shell.call_args_list[4:4 + len(CASES)]:
            command = call.args[1]
            self.assertIn("--offline", command)
            self.assertIn("--single-turn", command)
            self.assertIn("--no-display-prompt", command)
        self.assertIn("no Aura tool is called", result["limitations"][0])

    def test_mismatch_does_not_run_model(self):
        with patch("benchmark_llm_android.adb_shell", side_effect=["arm64-v8a", "36", "c" * 64 + " model"]) as shell:
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                evaluate(self.args)
            self.assertEqual(shell.call_count, 3)

    def test_empty_response_fails(self):
        values = ["arm64-v8a", "36", "a" * 64 + " model", "b" * 64 + " binary", ""]
        with patch("benchmark_llm_android.adb_shell", side_effect=values):
            with self.assertRaisesRegex(ValueError, "empty response"):
                evaluate(self.args)

    def test_model_change_discards_results(self):
        values = self.values()
        values[-1] = "c" * 64 + " model"
        with patch("benchmark_llm_android.adb_shell", side_effect=values):
            with self.assertRaisesRegex(ValueError, "changed during"):
                evaluate(self.args)

    def test_rejects_unsupported_device_and_excess_tokens(self):
        with patch("benchmark_llm_android.adb_shell", side_effect=["x86_64", "36"]):
            with self.assertRaises(ValueError):
                evaluate(self.args)
        self.args.tokens = 513
        with self.assertRaises(ValueError):
            evaluate(self.args)


if __name__ == "__main__":
    unittest.main()
