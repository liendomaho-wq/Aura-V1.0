# Aura — llama.cpp Android runtime build spike

**Status:** isolated build validation only. This document and its workflow do not integrate an LLM into Aura and do not change the APK build.

## Why this spike exists

Aura currently has no GGUF inference runtime connected to its Flutter agent. Before adding JNI, model management, or agent tool orchestration, CI must prove that a reproducible upstream llama.cpp revision compiles for the Android ABI and NDK used by Aura.

## Pinned upstream source

- Project: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- Revision: `806b3c2bed44490233f1e8ffa403519370965fe7` (upstream tag `b12224`, signed release commit)
- Build: CPU-only, static libraries, Android `arm64-v8a`
- NDK: `28.2.13676358` (matches Aura's Android Gradle configuration)
- Android platform: API 24 (matches Aura's minSdk)
- OpenMP, Vulkan, llamafile, OpenSSL, examples, server and upstream tests are disabled for this first portability check.

The upstream Android guide documents the NDK cross-compilation path and cautions against enabling host-native CPU flags during cross-compilation: [llama.cpp Android build guide](https://github.com/ggml-org/llama.cpp/blob/806b3c2bed44490233f1e8ffa403519370965fe7/docs/android.md).

## What the workflow proves

The workflow configures and compiles the upstream `llama` static target with the same NDK version as Aura, installs the public headers and static archives, verifies the expected artifacts, and uploads them for inspection.

A green run proves only that the pinned native engine can be compiled for ARM64. It does **not** prove:
- the archive is linked into Aura's APK;
- Kotlin/JNI can load a GGUF model;
- token generation or cancellation works;
- the selected DeepSeek model fits the Redmi's memory budget;
- 64K context is safe or practical on an 8 GB device;
- model download, digest verification, encrypted storage, or tool execution is implemented.

## Required next integration gates

1. Link the verified native libraries into the Android app without breaking Aura's existing native tunnel build or emulator ABIs.
2. Add a narrow JNI/Kotlin API with serialized lifecycle operations: load, generate/stream, cancel, unload, and query runtime capabilities.
3. Expose that API to Dart through a typed platform service; fail closed when the runtime or model is unavailable.
4. Install the GGUF into app-private storage using a pinned source, bounded download, verified SHA-256 and atomic rename. Never commit model weights or package them inside the APK.
5. Connect model output to the existing agent through a strict schema parser. The model may propose tools but must never authorize or directly execute security-sensitive actions.
6. Run instrumented tests on Android 16 and measure peak RSS, load time, tokens/sec, thermal behavior, cancellation and context tiers on the actual Redmi hardware.
7. Only after these gates pass should the runtime be enabled in the production app build.

## Build decision

Do not ask the user to compile `main` based on this spike. Aura is ready for a meaningful device build only after the native runtime is linked, the Flutter agent is connected, all CI checks pass, and a candidate APK is produced. Until then, `main` remains the last known-good app branch.
