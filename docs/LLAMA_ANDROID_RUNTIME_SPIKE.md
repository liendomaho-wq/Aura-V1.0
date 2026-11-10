# Aura — llama.cpp Android runtime build spike

**Status:** isolated multi-ABI build validation only. This workflow does not integrate an LLM into Aura and does not change the APK build.

## Why this spike exists

Aura currently has no GGUF inference runtime connected to its Flutter agent. Before adding JNI, model management, or agent tool orchestration, CI must prove that a reproducible upstream llama.cpp revision compiles for the Android ABIs and NDK used by Aura.

## Pinned upstream source

- Project: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- Revision: `806b3c2bed44490233f1e8ffa403519370965fe7` (upstream tag `b12224`, signed release commit)
- Build: CPU-only, static libraries, Android `armeabi-v7a`, `arm64-v8a`, `x86` and `x86_64`
- NDK: `28.2.13676358` (matches Aura's Android Gradle configuration)
- Android platform: API 24 (matches Aura's minSdk)
- OpenMP, Vulkan, llamafile, OpenSSL, examples, server and upstream tests are disabled for this portability check.

The upstream Android guide documents the NDK cross-compilation path and cautions against enabling host-native CPU flags during cross-compilation: [llama.cpp Android build guide](https://github.com/ggml-org/llama.cpp/blob/806b3c2bed44490233f1e8ffa403519370965fe7/docs/android.md).

## Why all four ABIs are built

Aura's current Gradle configuration packages four ABIs. Building only ARM64 would leave the other supported APK variants without the runtime. This matrix validates that the pinned engine can be cross-compiled for every ABI Aura currently declares before any packaging or JNI integration is attempted. ARM64 remains the primary target for the Redmi Note 15 Pro+ 5G.

## What the workflow proves

For each ABI, the workflow configures and compiles the upstream `llama` static target with Aura's NDK version, stages the public headers and static archives, verifies the expected files, and uploads a separate artifact.

A green matrix proves only that the pinned native engine can be compiled for those ABIs. It does **not** prove:
- the archives are linked into Aura's APK;
- Kotlin/JNI can load a GGUF model;
- token generation, streaming, cancellation or unload works;
- the selected DeepSeek model fits the Redmi's memory budget;
- 64K context is safe or practical on an 8 GB device;
- model download, digest verification, encrypted storage, or tool execution is implemented.

## Integration design constraint discovered in Aura

The current app compiles its existing tunnel through a custom Gradle `Exec` task that invokes `ndk-build` and stages its output in generated `jniLibs`. It does not use the Android Gradle Plugin's `externalNativeBuild` block. The LLM integration must preserve that tunnel pipeline and add a separate reproducible native build/staging path; it must not silently replace the existing NDK build or remove tunnel tests.

## Required next integration gates

1. Add a separate pinned llama.cpp native build task for each packaged ABI, stage the resulting runtime and its C++ runtime dependencies under generated `jniLibs`, and verify APK contents. Do not rely on a manually downloaded CI artifact.
2. Link a narrow JNI shared library against the pinned static archives without breaking the tunnel build.
3. Add a serialized Kotlin API for load, generate/stream, cancel, unload and runtime capability queries.
4. Expose that API to Dart through a typed platform service; fail closed when the runtime or model is unavailable.
5. Install the GGUF into app-private storage using a pinned source, bounded download, verified SHA-256 and atomic rename. Never commit model weights or package them inside the APK.
6. Connect model output to the existing agent through a strict schema parser. The model may propose tools but must never authorize or directly execute security-sensitive actions.
7. Run instrumented tests on Android 16 and measure peak RSS, load time, tokens/sec, thermal behavior, cancellation and context tiers on the actual Redmi hardware.

## Build decision

Do not ask the user to compile `main` based on this spike. Aura is ready for a meaningful device build only after the native runtime is linked, the Flutter agent is connected, all CI checks pass, and a candidate APK is produced. Until then, `main` remains the last known-good app branch.
