"""Unit tests for benchmark orchestration; these do not execute Android or a model."""

import argparse
import json
import shlex
import subprocess
import unittest
from unittest.mock import patch

from benchmark_llm_android import adb_shell, android_path, run_benchmark


class BenchmarkAndroidTests(unittest.TestCase):
    def setUp(self):
        self.args = argparse.Namespace(
            serial="authorized-device", binary="/data/local/tmp/llama-bench",
            model="/data/local/tmp/test.gguf", sha256="a" * 64, binary_sha256="b" * 64,
            lib_dir=None, threads=4, repetitions=3, prompt_tokens=512,
            generate_tokens=128, timeout=1200,
        )

    def test_shell_arguments_are_quoted(self):
        with patch("benchmark_llm_android.subprocess.run") as run:
            run.return_value.stdout = "ok\n"
            adb_shell("device", ["stat", "/tmp/model; touch /tmp/no"], 30)
            args = run.call_args.args[0]
            self.assertEqual(shlex.split(args[-1]), ["stat", "/tmp/model; touch /tmp/no"])
            self.assertNotIn("shell", run.call_args.kwargs)
            self.assertTrue(run.call_args.kwargs["check"])

    def test_path_rejects_traversal_and_control_characters(self):
        for value in ("relative/model", "/tmp/../secret", "/tmp/a\ncommand", "/tmp/a\0b"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                android_path(value)

    def test_mismatch_stops_before_execution(self):
        values = ["arm64-v8a", "36", "b" * 64 + "  /data/local/tmp/test.gguf"]
        with patch("benchmark_llm_android.adb_shell", side_effect=values) as shell:
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                run_benchmark(self.args)
            self.assertEqual(shell.call_count, 3)

    def test_binary_mismatch_stops_before_execution(self):
        values = ["arm64-v8a", "36", "a" * 64 + "  model", "c" * 64 + "  binary"]
        with patch("benchmark_llm_android.adb_shell", side_effect=values) as shell:
            with self.assertRaisesRegex(ValueError, "Binary SHA-256 mismatch"):
                run_benchmark(self.args)
            self.assertEqual(shell.call_count, 4)

    def test_valid_result_records_real_measurement_fields(self):
        values = ["arm64-v8a", "36", "a" * 64 + "  model", "b" * 64 + "  binary",
                  "123456", json.dumps([{"avg_ts": 7.5, "n_gen": 128}]), "a" * 64 + "  model"]
        with patch("benchmark_llm_android.adb_shell", side_effect=values) as shell:
            result = run_benchmark(self.args)
            self.assertEqual(result["benchmark"][0]["avg_ts"], 7.5)
            self.assertEqual(result["model_bytes"], 123456)
            self.assertIn("-ngl", shell.call_args_list[5].args[1])
            self.assertIn("not measured", result["limitations"][1])

    def test_changed_model_discards_results(self):
        values = ["arm64-v8a", "36", "a" * 64 + "  model", "b" * 64 + "  binary",
                  "123456", '[{"avg_ts": 7.5}]', "c" * 64 + "  model"]
        with patch("benchmark_llm_android.adb_shell", side_effect=values):
            with self.assertRaisesRegex(ValueError, "changed during"):
                run_benchmark(self.args)

    def test_malformed_and_nonfinite_measurements_fail(self):
        for output in ("not json", "[]", '[{"avg_ts": NaN}]', '[{"avg_ts": 0}]'):
            values = ["arm64-v8a", "36", "a" * 64 + "  model", "b" * 64 + "  binary",
                      "123456", output, "a" * 64 + "  model"]
            with self.subTest(output=output), patch("benchmark_llm_android.adb_shell", side_effect=values):
                with self.assertRaises(ValueError):
                    run_benchmark(self.args)

    def test_command_failure_is_not_hidden(self):
        with patch("benchmark_llm_android.subprocess.run", side_effect=subprocess.CalledProcessError(1, "adb")):
            with self.assertRaises(subprocess.CalledProcessError):
                adb_shell("device", ["getprop", "ro.product.cpu.abi"], 30)


if __name__ == "__main__":
    unittest.main()
