"""Guards that keep the local LLM runtime wired across Dart, Kotlin, C++ and Gradle.

These are source-level policy checks: they fail when a channel name, JNI entry
point, pinned digest or ABI list drifts between layers. They do not execute
Android, llama.cpp inference or JNI; CI compilation and the packaged-APK ELF
checks remain separate evidence.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DART_RUNTIME = ROOT / "lib/llm/aura_llm_runtime.dart"
KOTLIN_CONTRACT = ROOT / "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraLlmContract.kt"
KOTLIN_BRIDGE = ROOT / "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraLlmBridge.kt"
KOTLIN_PLUGIN = ROOT / "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraLlmPlugin.kt"
KOTLIN_OPERATION_REGISTRY = (
    ROOT / "android/app/src/main/kotlin/com/ciberdefensa/aura/AuraLlmOperationRegistry.kt"
)
MAIN_ACTIVITY = ROOT / "android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt"
JNI_SOURCE = ROOT / "android/app/src/main/cpp/aura_llm/aura_llm_jni.cpp"
SHIM_CMAKE = ROOT / "android/app/src/main/cpp/aura_llm/CMakeLists.txt"
APP_GRADLE = ROOT / "android/app/build.gradle"
VERIFY_APK = ROOT / "tool/verify_apk_jni.py"
DART_PLANNER = ROOT / "lib/llm/local_llm_planner.dart"
DART_MODEL_MANAGER = ROOT / "lib/llm/aura_llm_model_manager.dart"
DART_CONTROLLER = ROOT / "lib/agent/agent_controller.dart"
DART_PROPOSAL = ROOT / "lib/agent/llm_tool_proposal.dart"

PINNED_COMMIT = "806b3c2bed44490233f1e8ffa403519370965fe7"
PINNED_SHA256 = "1c073db9bf1dfbaf7dfdfa27c0a1720147d593c6d704acf81a3c4470e6e95d37"
ABIS = ("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
KOTLIN_BRIDGE_NATIVE_PATTERN = re.compile(r"external fun (native[A-Za-z0-9]+)\(")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class AuraLlmNativeIntegrationTest(unittest.TestCase):
    def test_channels_match_between_dart_and_kotlin(self):
        dart = read(DART_RUNTIME)
        kotlin = read(KOTLIN_CONTRACT)
        for channel in ("com.ciberdefensa.aura/llm", "com.ciberdefensa.aura/llm/events"):
            self.assertIn(channel, dart)
            self.assertIn(channel, kotlin)

    def test_event_types_match_between_dart_and_kotlin(self):
        dart = read(DART_RUNTIME)
        kotlin = read(KOTLIN_CONTRACT)
        self.assertIn("'token', 'completed', 'error'", dart)
        for event_type in ("token", "completed", "error"):
            self.assertIn(f'EVENT_TYPE_{event_type.upper()} = "{event_type}"', kotlin)

    def test_argument_keys_match_between_dart_and_kotlin(self):
        dart = read(DART_RUNTIME)
        kotlin = read(KOTLIN_CONTRACT)
        for key in ("model_path", "context_tokens", "threads", "prompt",
                    "max_tokens", "temperature", "operation_id",
                    "available", "loaded", "backend", "abi", "max_context_tokens"):
            self.assertIn(key, dart)
            self.assertIn(key, kotlin)

    def test_bounds_match_between_dart_and_kotlin(self):
        dart = read(DART_RUNTIME)
        kotlin = read(KOTLIN_CONTRACT)
        # Dart validates 512..65536 context tokens, 1..8 threads, <= 32768
        # prompt chars, 1..4096 output tokens and 0..2 temperature.
        for bounds in ("contextTokens < 512", "contextTokens > 65536",
                       "threads < 1", "threads > 8", "prompt.length > 32768",
                       "maxTokens < 1", "maxTokens > 4096",
                       "temperature < 0", "temperature > 2"):
            self.assertIn(bounds, dart)
        self.assertIn("MIN_CONTEXT_TOKENS = 512", kotlin)
        self.assertIn("MAX_CONTEXT_TOKENS = 65536", kotlin)
        self.assertIn("MIN_THREADS = 1", kotlin)
        self.assertIn("MAX_THREADS = 8", kotlin)
        self.assertIn("MAX_PROMPT_CHARS = 32768", kotlin)
        self.assertIn("MIN_OUTPUT_TOKENS = 1", kotlin)
        self.assertIn("MAX_OUTPUT_TOKENS = 4096", kotlin)
        self.assertIn("MAX_TEMPERATURE = 2.0", kotlin)

    def test_every_kotlin_external_function_has_a_jni_export(self):
        bridge = read(KOTLIN_BRIDGE)
        jni = read(JNI_SOURCE)
        natives = KOTLIN_BRIDGE_NATIVE_PATTERN.findall(bridge)
        self.assertGreaterEqual(len(natives), 8)
        for name in natives:
            symbol = f"Java_com_ciberdefensa_aura_AuraLlmBridge_{name}"
            self.assertIn(symbol, jni, f"Missing JNI export for {name}")

    def test_jni_event_callback_signature_matches_kotlin(self):
        jni = read(JNI_SOURCE)
        bridge = read(KOTLIN_BRIDGE)
        # void onNativeEvent(String operationId, int typeCode, String text)
        self.assertIn('"(Ljava/lang/String;ILjava/lang/String;)V"', jni)
        self.assertIn("@JvmStatic", bridge)
        self.assertIn(
            "fun onNativeEvent(operationId: String, typeCode: Int, text: String?)",
            bridge,
        )

    def test_main_activity_registers_the_llm_plugin(self):
        main = read(MAIN_ACTIVITY)
        self.assertIn("AuraLlmPlugin.install(flutterEngine)", main)

    def test_gradle_pins_and_verifies_the_llama_source(self):
        gradle = read(APP_GRADLE)
        self.assertIn(f'"{PINNED_COMMIT}"', gradle)
        self.assertIn(f'"{PINNED_SHA256}"', gradle)
        self.assertIn("MessageDigest.getInstance(\"SHA-256\")", gradle)
        # A digest mismatch must abort the build, never be ignored.
        self.assertIn("Pinned llama.cpp tarball digest mismatch", gradle)
        self.assertNotIn("ignoreExitValue", gradle)

    def test_gradle_builds_every_declared_abi_and_wires_prebuild(self):
        gradle = read(APP_GRADLE)
        self.assertIn('def auraLlmAbis = ["armeabi-v7a", "arm64-v8a", "x86", "x86_64"]', gradle)
        for abi in ABIS:
            self.assertIn(f'"{abi}"', gradle)
        self.assertRegex(gradle, r'dependsOn\("buildAuraLlmRuntime"\)')
        self.assertIn("--target\", \"llama\"", gradle)
        self.assertIn("ANDROID_STL=c++_static", gradle)
        self.assertIn("GGML_OPENMP=OFF", gradle)
        self.assertIn("GGML_VULKAN=OFF", gradle)
        self.assertIn("LLAMA_BUILD_SERVER=OFF", gradle)

    def test_shim_links_all_pinned_static_libraries(self):
        cmake = read(SHIM_CMAKE)
        for library in ("LLAMA_STATIC_LIB", "GGML_STATIC_LIB",
                        "GGML_BASE_STATIC_LIB", "GGML_CPU_STATIC_LIB"):
            self.assertIn(library, cmake)
        self.assertIn("LLAMA_INCLUDE_DIR", cmake)
        self.assertIn("GGML_INCLUDE_DIR", cmake)

    def test_native_failures_never_report_completed(self):
        jni = read(JNI_SOURCE)
        # The cancellation and failure paths emit kError events; only the
        # successful loop end emits kCompleted.
        self.assertIn('emit_event(env, job.operation_id, AuraLlmEventType::kError, "operation_cancelled")',
                      jni)
        self.assertIn('emit_event(env, job.operation_id, AuraLlmEventType::kError, failure)', jni)
        self.assertIn('emit_event(env, job.operation_id, AuraLlmEventType::kCompleted, generated)', jni)

    def test_packaged_runtime_is_verified_per_abi(self):
        verifier = read(VERIFY_APK)
        self.assertIn('"libaura_llm.so"', verifier)
        bridge = read(KOTLIN_BRIDGE)
        for name in KOTLIN_BRIDGE_NATIVE_PATTERN.findall(bridge):
            self.assertIn(f"Java_com_ciberdefensa_aura_AuraLlmBridge_{name}", verifier)
        self.assertIn('"libhev-socks5-tunnel.so"', verifier)


class AuraLlmPluginFailClosedTest(unittest.TestCase):
    def test_capabilities_do_not_claim_availability_without_the_library(self):
        plugin = read(KOTLIN_PLUGIN)
        self.assertIn(
            "val available = AuraLlmBridge.libraryAvailable && AuraLlmBridge.workerReady",
            plugin,
        )

    def test_unload_and_load_refuse_active_generations(self):
        plugin = read(KOTLIN_PLUGIN)
        self.assertGreaterEqual(plugin.count("registry.hasActiveOperations()"), 2)
        self.assertIn("AuraLlmContract.ERROR_BUSY", plugin)

    def test_late_events_for_terminal_operations_are_dropped(self):
        plugin = read(KOTLIN_PLUGIN)
        self.assertIn("if (!registry.markCompleted(operationId))", plugin)
        self.assertIn("if (!registry.markFailed(operationId, text ?: \"native_error\"))", plugin)

    def test_cancellation_stays_active_until_native_confirmation(self):
        plugin = read(KOTLIN_PLUGIN)
        registry = read(KOTLIN_OPERATION_REGISTRY)
        # Cancellation must be cooperative: Dart keeps the operation active
        # until the native worker reports a terminal event, so exactly one
        # terminal event always reaches Dart.
        self.assertIn("val accepted = registry.requestCancel(operationId)", plugin)
        self.assertIn("registry.isCancelRequested(operationId)", plugin)
        self.assertIn("registry.markCancelled(operationId)", plugin)
        self.assertIn("AuraLlmContract.ERROR_CANCELLED", plugin)
        self.assertIn("fun requestCancel(id: String): Boolean", registry)
        self.assertIn("fun markCancelled(id: String): Boolean", registry)

    def test_tokens_after_cancel_are_discarded(self):
        plugin = read(KOTLIN_PLUGIN)
        token_branch = plugin.split("AuraLlmContract.EVENT_TYPE_TOKEN ->", 1)[1]
        token_branch = token_branch.split("AuraLlmContract.EVENT_TYPE_COMPLETED ->", 1)[0]
        self.assertIn("if (registry.isCancelRequested(operationId)) return", token_branch)
        self.assertIn("if (!registry.markRunning(operationId)) return", token_branch)


class AuraLlmDartWiringTest(unittest.TestCase):
    """The agent must reach the local model only through the validated boundary."""

    def test_unknown_orders_ask_the_local_planner(self):
        controller = read(DART_CONTROLLER)
        self.assertIn("import '../llm/local_llm_planner.dart';", controller)
        self.assertIn("intent.kind == AuraIntentKind.unknown", controller)
        self.assertRegex(
            controller,
            r"(?s)if \(intent\.kind == AuraIntentKind\.unknown\) \{.*?_planWithLocalModel",
        )
        self.assertIn("_planWithLocalModel(", controller)
        self.assertIn("bindLocalLlmPlanner(", controller)

    def test_planner_output_is_reparsed_as_untrusted_json(self):
        planner = read(DART_PLANNER)
        self.assertIn("LlmToolProposal.parse(candidate)", planner)
        # The planner itself never executes a tool and never confirms one.
        self.assertNotIn("AuraTools.execute", planner)
        self.assertNotIn("confirmed_by_user': true", planner)
        self.assertIn("operation_cancelled", planner)
        # Hostile output is bounded before decoding.
        self.assertIn("maxCaptureChars", planner)
        self.assertIn("LlmToolProposal.maxOutputBytes", planner)

    def test_controller_maps_only_read_only_tools(self):
        controller = read(DART_CONTROLLER)
        mapping = controller.split("static AuraIntent? intentFromLlmProposal", 1)[1]
        mapping = mapping.split("static ", 1)[0]
        for tool in ("analyze_domain", "audit_device", "scan_apps"):
            self.assertIn(f"'{tool}'", mapping)
        self.assertNotIn("block_domain", mapping)
        self.assertNotIn("panic_isolation", mapping)
        self.assertNotIn("cryptographic_purge", mapping)
        self.assertIn("confirmed_by_user", controller)

    def test_read_only_allowlist_matches_the_planner_prompt(self):
        proposal = read(DART_PROPOSAL)
        planner = read(DART_PLANNER)
        allowlist = proposal.split("_readOnlyTools = <String>{", 1)[1]
        allowlist = allowlist.split("};", 1)[0]
        for tool in ("analyze_domain", "audit_device", "scan_apps"):
            self.assertIn(tool, allowlist)
            self.assertIn(tool, planner)
        for forbidden in ("block_domain", "isolate_app", "cryptographic_purge"):
            self.assertNotIn(forbidden, allowlist)

    def test_model_manager_requires_build_time_digest_and_https(self):
        manager = read(DART_MODEL_MANAGER)
        self.assertIn("AURA_LLM_MODEL_URL", manager)
        self.assertIn("AURA_LLM_MODEL_SHA256", manager)
        self.assertIn("_digestPattern = RegExp(r'^[0-9a-f]{64}$')", manager)
        self.assertIn("uri.scheme != 'https'", manager)
        self.assertIn("sha256.bind(file.openRead()).first", manager)
        self.assertIn("await temporary.rename(target.path)", manager)
        # Verification happens before the rename; a mismatch never installs.
        mismatch = manager.split("if (!await _matchesDigest(temporary))", 1)[1]
        mismatch = mismatch.split("await temporary.rename", 1)[0]
        self.assertIn("return null", mismatch)
        self.assertIn("_deleteIfPresent(temporary)", mismatch)

    def test_model_resolution_is_single_flight(self):
        manager = read(DART_MODEL_MANAGER)
        # Concurrent resolutions must share one download: an abandoned caller
        # must not start a second writer against the same .partial file.
        self.assertIn("Future<String?>? _resolveFuture;", manager)
        resolve = manager.split("Future<String?> resolveVerifiedModel() {", 1)[1]
        resolve = resolve.split("Future<String?> _resolveOrDownload()", 1)[0]
        self.assertIn("final pending = _resolveFuture;", resolve)
        self.assertIn("if (pending != null) return pending;", resolve)

    def test_an_order_never_waits_for_a_model_download(self):
        planner = read(DART_PLANNER)
        self.assertIn("modelResolveTimeout", planner)
        self.assertIn("_resolveModelPath().timeout(modelResolveTimeout)", planner)
        self.assertIn("llm_model_prepare_timeout", planner)
        self.assertIn("Future<void> prefetchModel()", planner)
        # Prefetch is explicitly outside the order path.
        self.assertIn("outside the order path", planner)

    def test_cancellation_token_notifies_the_planner(self):
        token = read(ROOT / "lib/agent/agent_execution_guard.dart")
        planner = read(DART_PLANNER)
        self.assertIn("addCancelListener", token)
        self.assertIn("removeCancelListener", token)
        self.assertIn("addCancelListener(onCancelRequested)", planner)
        self.assertIn("_runtime.cancel(operationId)", planner)


if __name__ == "__main__":
    unittest.main()
