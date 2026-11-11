package com.ciberdefensa.aura

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

/** Registers the local LLM channels that lib/llm/aura_llm_runtime.dart binds to.
 *
 * The channels are com.ciberdefensa.aura/llm (methods) and
 * com.ciberdefensa.aura/llm/events (generation events). Every argument is
 * re-validated here even though Dart already validated it: the native layer
 * validates a third time. Model output remains untrusted text; this plugin
 * never authorizes security tools or bypasses AgentController policy.
 */
internal object AuraLlmPlugin {
    private val registry = AuraLlmOperationRegistry()

    // Written on the main thread by the stream handler; read there too.
    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun install(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, AuraLlmContract.METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
        EventChannel(messenger, AuraLlmContract.EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
        AuraLlmBridge.setEventListener(::dispatchNativeEvent)
    }

    private fun handleMethodCall(call: MethodCall, result: Result) {
        val arguments = call.arguments as? Map<*, *>
        try {
            when (call.method) {
                "capabilities" -> capabilities(result)
                "loadModel" -> loadModel(arguments, result)
                "startGeneration" -> startGeneration(arguments, result)
                "cancel" -> cancel(arguments, result)
                "unloadModel" -> unloadModel(result)
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            // A crash while handling a call must surface as an error result,
            // never as a dangling future or a fake success.
            if (error is IllegalStateException && error.message == "llm_generation_busy") {
                result.error(AuraLlmContract.ERROR_BUSY, "Another generation is already active.", null)
            } else {
                result.error(
                    "llm_internal_error",
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
        }
    }

    private fun capabilities(result: Result) {
        val available = AuraLlmBridge.libraryAvailable && AuraLlmBridge.workerReady
        val loaded = if (available) {
            runCatching { AuraLlmBridge.nativeIsModelLoaded() }.getOrDefault(false)
        } else {
            false
        }
        val maxContextTokens = if (available) {
            runCatching { AuraLlmBridge.nativeMaxContextTokens() }.getOrDefault(0)
        } else {
            0
        }
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: ""
        result.success(
            AuraLlmContract.capabilitiesPayload(available, loaded, abi, maxContextTokens),
        )
    }

    private fun loadModel(arguments: Map<*, *>?, result: Result) {
        val request = AuraLlmContract.parseLoadModelArguments(arguments)
            ?: return result.error(
                AuraLlmContract.ERROR_INVALID_REQUEST,
                "loadModel requires a usable absolute model path, 512..65536 context tokens " +
                    "and 1..8 threads.",
                null,
            )
        if (!AuraLlmBridge.libraryAvailable || !AuraLlmBridge.workerReady) {
            return result.error(
                if (AuraLlmBridge.libraryAvailable) {
                    AuraLlmContract.ERROR_WORKER_UNAVAILABLE
                } else {
                    AuraLlmContract.ERROR_LIBRARY_MISSING
                },
                "The native llama.cpp runtime is not available on this build.",
                null,
            )
        }
        if (AuraLlmBridge.nativeIsModelLoaded()) {
            return result.error(
                AuraLlmContract.ERROR_ALREADY_LOADED,
                "A local model is already loaded; unload it first.",
                null,
            )
        }
        if (registry.hasActiveOperations()) {
            return result.error(
                AuraLlmContract.ERROR_BUSY,
                "A generation is queued or running; wait or cancel it before loading.",
                null,
            )
        }
        when (AuraLlmBridge.nativeLoadModel(request.modelPath, request.contextTokens, request.threads)) {
            0 -> result.success(null)
            2 -> result.error(
                AuraLlmContract.ERROR_LOAD_FAILED,
                AuraLlmBridge.nativeGetLastError()
                    ?: "The GGUF model could not be loaded by llama.cpp.",
                null,
            )
            3 -> result.error(
                AuraLlmContract.ERROR_CONTEXT_FAILED,
                AuraLlmBridge.nativeGetLastError()
                    ?: "The inference context could not be created.",
                null,
            )
            else -> result.error(
                AuraLlmContract.ERROR_INVALID_REQUEST,
                "The native layer rejected the model loading request.",
                null,
            )
        }
    }

    private fun startGeneration(arguments: Map<*, *>?, result: Result) {
        val request = AuraLlmContract.parseGenerationArguments(arguments)
            ?: return result.error(
                AuraLlmContract.ERROR_INVALID_REQUEST,
                "startGeneration requires a non-blank prompt (<= 32768 chars), 1..4096 output " +
                    "tokens and a finite temperature within 0..2.",
                null,
            )
        if (!AuraLlmBridge.libraryAvailable || !AuraLlmBridge.workerReady) {
            return result.error(
                if (AuraLlmBridge.libraryAvailable) {
                    AuraLlmContract.ERROR_WORKER_UNAVAILABLE
                } else {
                    AuraLlmContract.ERROR_LIBRARY_MISSING
                },
                "The native llama.cpp runtime is not available on this build.",
                null,
            )
        }
        if (!AuraLlmBridge.nativeIsModelLoaded()) {
            return result.error(
                AuraLlmContract.ERROR_NOT_LOADED,
                "No local model is loaded.",
                null,
            )
        }
        val operationId = registry.begin()
        when (
            AuraLlmBridge.nativeStartGeneration(
                operationId,
                request.prompt,
                request.maxTokens,
                request.temperature,
            )
        ) {
            0 -> result.success(operationId)
            else -> {
                registry.markFailed(operationId, "native_rejected_generation")
                result.error(
                    AuraLlmContract.ERROR_INVALID_REQUEST,
                    "The native layer rejected the generation request.",
                    null,
                )
            }
        }
    }

    private fun cancel(arguments: Map<*, *>?, result: Result) {
        val operationId = AuraLlmContract.parseOperationId(arguments)
            ?: return result.error(
                AuraLlmContract.ERROR_INVALID_REQUEST,
                "cancel requires a non-empty operation_id.",
                null,
            )
        val accepted = registry.requestCancel(operationId)
        if (accepted) {
            // Cooperative: the operation stays active until the native worker
            // reports a terminal event, so Dart always receives exactly one
            // terminal event. A race where the job already finished is not an
            // error; the pending terminal event resolves the operation.
            runCatching { AuraLlmBridge.nativeCancelGeneration(operationId) }
        }
        result.success(accepted)
    }

    private fun unloadModel(result: Result) {
        if (registry.hasActiveOperations()) {
            return result.error(
                AuraLlmContract.ERROR_BUSY,
                "A generation is queued or running; cancel it before unloading.",
                null,
            )
        }
        if (!AuraLlmBridge.libraryAvailable) {
            return result.error(
                AuraLlmContract.ERROR_LIBRARY_MISSING,
                "The native llama.cpp runtime is not available on this build.",
                null,
            )
        }
        when (AuraLlmBridge.nativeUnloadModel()) {
            0 -> result.success(null)
            else -> result.error(
                AuraLlmContract.ERROR_BUSY,
                "The native layer still holds queued or running generations.",
                null,
            )
        }
    }

    /** Runs on the main thread via AuraLlmBridge's handler. */
    private fun dispatchNativeEvent(operationId: String, type: String, text: String?) {
        when (type) {
            AuraLlmContract.EVENT_TYPE_TOKEN -> {
                // Tokens after a cancellation request are discarded so the
                // caller never observes partial output it asked to abandon.
                if (registry.isCancelRequested(operationId)) return
                // Unknown or terminal operations never stream tokens.
                if (!registry.markRunning(operationId)) return
                emit(operationId, type, text, null)
            }
            AuraLlmContract.EVENT_TYPE_COMPLETED -> {
                if (registry.isCancelRequested(operationId)) {
                    // The caller cancelled before the terminal event arrived.
                    // Report one deterministic cancelled terminal event.
                    if (!registry.markCancelled(operationId)) return
                    emit(operationId, AuraLlmContract.EVENT_TYPE_ERROR, null,
                        AuraLlmContract.ERROR_CANCELLED)
                    return
                }
                if (!registry.markCompleted(operationId)) {
                    return  // Late or unknown completion for a terminal operation.
                }
                emit(operationId, type, text, null)
            }
            AuraLlmContract.EVENT_TYPE_ERROR -> {
                if (registry.isCancelRequested(operationId)) {
                    if (!registry.markCancelled(operationId)) return
                    emit(operationId, AuraLlmContract.EVENT_TYPE_ERROR, null,
                        AuraLlmContract.ERROR_CANCELLED)
                    return
                }
                if (!registry.markFailed(operationId, text ?: "native_error")) {
                    return  // Late error for an operation already terminal.
                }
                emit(operationId, type, null, text ?: "native_error")
            }
        }
    }

    private fun emit(
        operationId: String,
        type: String,
        text: String?,
        error: String?,
    ) {
        eventSink?.success(
            AuraLlmContract.eventPayload(operationId, type, text, error),
        )
    }
}
