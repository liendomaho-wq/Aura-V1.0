package com.ciberdefensa.aura

/** Pure JVM contract of the local LLM boundary shared with the Dart side.
 *
 * Mirrors lib/llm/aura_llm_runtime.dart: the same channel names, argument
 * keys, value ranges and response shapes. Both sides validate independently;
 * the native layer validates a third time. Any mismatch fails closed instead
 * of being coerced into a partial success.
 */
internal object AuraLlmContract {
    const val METHOD_CHANNEL = "com.ciberdefensa.aura/llm"
    const val EVENT_CHANNEL = "com.ciberdefensa.aura/llm/events"

    const val MIN_CONTEXT_TOKENS = 512
    const val MAX_CONTEXT_TOKENS = 65536
    const val MIN_THREADS = 1
    const val MAX_THREADS = 8
    const val MAX_PROMPT_CHARS = 32768
    const val MIN_OUTPUT_TOKENS = 1
    const val MAX_OUTPUT_TOKENS = 4096
    const val MAX_TEMPERATURE = 2.0
    const val BACKEND_NAME = "llama.cpp"

    const val EVENT_TYPE_TOKEN = "token"
    const val EVENT_TYPE_COMPLETED = "completed"
    const val EVENT_TYPE_ERROR = "error"

    const val ERROR_INVALID_REQUEST = "llm_invalid_request"
    const val ERROR_LIBRARY_MISSING = "llm_library_missing"
    const val ERROR_WORKER_UNAVAILABLE = "llm_worker_unavailable"
    const val ERROR_NOT_LOADED = "llm_not_loaded"
    const val ERROR_ALREADY_LOADED = "llm_already_loaded"
    const val ERROR_LOAD_FAILED = "llm_model_load_failed"
    const val ERROR_CONTEXT_FAILED = "llm_context_failed"
    const val ERROR_BUSY = "llm_busy"
    const val ERROR_CANCELLED = "operation_cancelled"

    data class LoadModelRequest(val modelPath: String, val contextTokens: Int, val threads: Int)

    data class GenerationRequest(val prompt: String, val maxTokens: Int, val temperature: Double)

    /** A model path is only usable when absolute and free of parent traversal. */
    fun isUsableModelPath(path: String): Boolean =
        path.startsWith("/") && !path.contains("..")

    fun parseLoadModelArguments(arguments: Map<*, *>?): LoadModelRequest? {
        if (arguments == null) return null
        val path = arguments["model_path"]
        val contextTokens = arguments["context_tokens"]
        val threads = arguments["threads"]
        if (path !is String || !isUsableModelPath(path)) return null
        if (contextTokens !is Int ||
            contextTokens < MIN_CONTEXT_TOKENS || contextTokens > MAX_CONTEXT_TOKENS
        ) return null
        if (threads !is Int || threads < MIN_THREADS || threads > MAX_THREADS) return null
        return LoadModelRequest(path, contextTokens, threads)
    }

    fun parseGenerationArguments(arguments: Map<*, *>?): GenerationRequest? {
        if (arguments == null) return null
        val prompt = arguments["prompt"]
        val maxTokens = arguments["max_tokens"]
        val temperature = arguments["temperature"]
        if (prompt !is String || prompt.isBlank() || prompt.length > MAX_PROMPT_CHARS) {
            return null
        }
        if (maxTokens !is Int ||
            maxTokens < MIN_OUTPUT_TOKENS || maxTokens > MAX_OUTPUT_TOKENS
        ) return null
        if (temperature !is Double ||
            !temperature.isFinite() || temperature < 0.0 || temperature > MAX_TEMPERATURE
        ) return null
        return GenerationRequest(prompt, maxTokens, temperature)
    }

    fun parseOperationId(arguments: Map<*, *>?): String? {
        if (arguments == null) return null
        val operationId = arguments["operation_id"]
        return if (operationId is String && operationId.isNotEmpty()) operationId else null
    }

    fun capabilitiesPayload(
        available: Boolean,
        loaded: Boolean,
        abi: String,
        maxContextTokens: Int,
    ): Map<String, Any> {
        require(maxContextTokens >= 0) { "max_context_tokens must not be negative." }
        return mapOf(
            "available" to available,
            "loaded" to loaded,
            "backend" to BACKEND_NAME,
            "abi" to abi,
            "max_context_tokens" to maxContextTokens,
        )
    }

    fun eventPayload(
        operationId: String,
        type: String,
        text: String?,
        error: String? = null,
    ): Map<String, Any?> {
        require(operationId.isNotEmpty()) { "operation_id must not be empty." }
        require(
            type == EVENT_TYPE_TOKEN || type == EVENT_TYPE_COMPLETED || type == EVENT_TYPE_ERROR,
        ) { "Unknown native LLM event type: $type" }
        return mapOf(
            "operation_id" to operationId,
            "type" to type,
            "text" to text,
            "error" to error,
        )
    }
}
