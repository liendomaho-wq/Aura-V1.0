#!/usr/bin/env python3
"""Static guards for the pinned on-device GGUF build configuration.

The model itself is untrusted input; only a build-time URL plus SHA-256 can
activate it. These checks keep the pinned revision, the digest and every build
entry point in sync so a release cannot silently ship with an unverified or
unpinned model source.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_ENV = ROOT / "tool/aura_llm_model.env"
BUILD_SCRIPT = ROOT / "tool/compile_aura.sh"
DEBUG_WORKFLOW = ROOT / ".github/workflows/android-debug-build.yml"
QUALITY_WORKFLOW = ROOT / ".github/workflows/flutter-quality.yml"
CODEMAGIC = ROOT / "codemagic.yaml"
MODEL_INFO = ROOT / "lib/llm/aura_llm_model_info.dart"

REQUIRED_KEYS = (
    "AURA_LLM_MODEL_LABEL",
    "AURA_LLM_MODEL_LICENSE",
    "AURA_LLM_MODEL_SIZE_BYTES",
    "AURA_LLM_MODEL_URL",
    "AURA_LLM_MODEL_SHA256",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def env_value(source: str, key: str) -> str:
    match = re.search(
        rf"(?m)^{re.escape(key)}='([^']*)'\s*$",
        source,
    )
    if match is None:
        raise AssertionError(f"{key} must be single-quoted in the model env file")
    return match.group(1)


class LocalModelConfigTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.env = read(MODEL_ENV)
        cls.build_script = read(BUILD_SCRIPT)
        cls.debug_workflow = read(DEBUG_WORKFLOW)
        cls.quality_workflow = read(QUALITY_WORKFLOW)
        cls.codemagic = read(CODEMAGIC)
        cls.model_info = read(MODEL_INFO)

    def test_env_file_declares_every_required_value(self) -> None:
        for key in REQUIRED_KEYS:
            self.assertIn(key, self.env)
            env_value(self.env, key)

    def test_model_url_is_https_and_pinned_to_a_commit(self) -> None:
        url = env_value(self.env, "AURA_LLM_MODEL_URL")
        self.assertTrue(url.startswith("https://"), url)
        self.assertRegex(
            url,
            re.compile(
                r"/resolve/[0-9a-f]{40}/[A-Za-z0-9._-]+\.gguf$"
            ),
        )
        self.assertNotIn("/resolve/main/", url)

    def test_digest_is_a_lowercase_sha256(self) -> None:
        digest = env_value(self.env, "AURA_LLM_MODEL_SHA256")
        self.assertRegex(digest, re.compile(r"^[0-9a-f]{64}$"))

    def test_declared_size_matches_a_real_gguf_download(self) -> None:
        size = int(env_value(self.env, "AURA_LLM_MODEL_SIZE_BYTES"))
        self.assertGreater(size, 64 * 1024 * 1024)
        self.assertLessEqual(size, 4 * 1024 * 1024 * 1024)

    def test_license_is_declared(self) -> None:
        self.assertEqual(env_value(self.env, "AURA_LLM_MODEL_LICENSE"), "Apache-2.0")

    def test_build_script_sources_the_env_and_passes_both_defines(self) -> None:
        self.assertIn("tool/aura_llm_model.env", self.build_script)
        self.assertIn('AURA_LLM_MODEL_URL=$AURA_LLM_MODEL_URL', self.build_script)
        self.assertIn(
            'AURA_LLM_MODEL_SHA256=$AURA_LLM_MODEL_SHA256', self.build_script
        )
        # Both release formats must carry the same model configuration.
        self.assertEqual(self.build_script.count("${llm_defines[@]}"), 2)

    def test_debug_workflow_exports_the_pinned_model_before_building(self) -> None:
        self.assertIn("tool/aura_llm_model.env", self.debug_workflow)
        self.assertIn("AURA_LLM_MODEL_URL", self.debug_workflow)
        self.assertIn("AURA_LLM_MODEL_SHA256", self.debug_workflow)
        self.assertIn("--dart-define", self.debug_workflow)

    def test_quality_workflow_runs_this_guard(self) -> None:
        self.assertIn("tool/test_local_llm_model_config.py", self.quality_workflow)

    def test_codemagic_build_uses_the_shared_compile_script(self) -> None:
        self.assertIn("bash tool/compile_aura.sh", self.codemagic)

    def test_dart_model_info_reads_the_same_defines(self) -> None:
        for define in (
            "AURA_LLM_MODEL_LABEL",
            "AURA_LLM_MODEL_LICENSE",
            "AURA_LLM_MODEL_SIZE_BYTES",
        ):
            self.assertIn(define, self.model_info)


if __name__ == "__main__":
    unittest.main()
