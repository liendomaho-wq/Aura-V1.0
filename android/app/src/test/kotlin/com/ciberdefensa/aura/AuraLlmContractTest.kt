package com.ciberdefensa.aura

import org.junit.Test

class AuraLlmContractTest {
    @Test
    fun channelNamesMatchTheDartBoundary() {
        // lib/llm/aura_llm_runtime.dart binds exactly these channel names;
        // renaming one side without the other breaks the runtime silently.
        check(AuraLlmContract.METHOD_CHANNEL == "com.ciberdefensa.aura/llm")
        check(AuraLlmContract.EVENT_CHANNEL == "com.ciberdefensa.aura/llm/events")
    }

    @Test
    fun modelPathsMustBeAbsoluteWithoutTraversal() {
        check(AuraLlmContract.isUsableModelPath("/data/user/0/app/files/model.gguf"))
        check(!AuraLlmContract.isUsableModelPath("model.gguf"))
        check(!AuraLlmContract.isUsableModelPath("../outside/model.gguf"))
        check(!AuraLlmContract.isUsableModelPath("/data/../../outside/model.gguf"))
        check(!AuraLlmContract.isUsableModelPath(""))
    }

    @Test
    fun loadModelArgumentsAreValidatedFailClosed() {
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf(
                    "model_path" to "/data/local/tmp/model.gguf",
                    "context_tokens" to 4096,
                    "threads" to 2,
                ),
            ) != null,
        )
        check(AuraLlmContract.parseLoadModelArguments(null) == null)
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf(
                    "model_path" to "relative.gguf",
                    "context_tokens" to 4096,
                    "threads" to 2,
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf(
                    "model_path" to "/model.gguf",
                    "context_tokens" to 511,
                    "threads" to 2,
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf(
                    "model_path" to "/model.gguf",
                    "context_tokens" to 65537,
                    "threads" to 2,
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf(
                    "model_path" to "/model.gguf",
                    "context_tokens" to 4096,
                    "threads" to 0,
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf(
                    "model_path" to "/model.gguf",
                    "context_tokens" to 4096,
                    "threads" to "2",
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseLoadModelArguments(
                mapOf("context_tokens" to 4096, "threads" to 2),
            ) == null,
        )
    }

    @Test
    fun generationArgumentsAreValidatedFailClosed() {
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf(
                    "prompt" to "Hola",
                    "max_tokens" to 512,
                    "temperature" to 0.2,
                ),
            ) != null,
        )
        check(AuraLlmContract.parseGenerationArguments(null) == null)
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf("prompt" to "   ", "max_tokens" to 512, "temperature" to 0.2),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf(
                    "prompt" to "x".repeat(AuraLlmContract.MAX_PROMPT_CHARS + 1),
                    "max_tokens" to 512,
                    "temperature" to 0.2,
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf("prompt" to "Hola", "max_tokens" to 0, "temperature" to 0.2),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf("prompt" to "Hola", "max_tokens" to 4097, "temperature" to 0.2),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf("prompt" to "Hola", "max_tokens" to 512, "temperature" to 2.1),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf("prompt" to "Hola", "max_tokens" to 512, "temperature" to -0.1),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf(
                    "prompt" to "Hola",
                    "max_tokens" to 512,
                    "temperature" to Double.NaN,
                ),
            ) == null,
        )
        check(
            AuraLlmContract.parseGenerationArguments(
                mapOf("prompt" to "Hola", "max_tokens" to 512, "temperature" to 0.0),
            ) != null,
        )
    }

    @Test
    fun operationIdsAreValidated() {
        check(AuraLlmContract.parseOperationId(mapOf("operation_id" to "op-1")) == "op-1")
        check(AuraLlmContract.parseOperationId(null) == null)
        check(AuraLlmContract.parseOperationId(mapOf("operation_id" to "")) == null)
        check(AuraLlmContract.parseOperationId(mapOf("operation_id" to 7)) == null)
    }

    @Test
    fun capabilitiesPayloadMatchesDartDecoding() {
        val payload = AuraLlmContract.capabilitiesPayload(
            available = true,
            loaded = false,
            abi = "arm64-v8a",
            maxContextTokens = 65536,
        )
        check(payload.keys == setOf("available", "loaded", "backend", "abi", "max_context_tokens"))
        check(payload["backend"] == "llama.cpp")
        check(payload["max_context_tokens"] == 65536)
        check(payload["abi"] == "arm64-v8a")
        check(payload["available"] == true)
        check(payload["loaded"] == false)
        val threw = try {
            AuraLlmContract.capabilitiesPayload(true, true, "arm64-v8a", -1)
            false
        } catch (_: IllegalArgumentException) {
            true
        }
        check(threw)
    }

    @Test
    fun eventPayloadMatchesDartDecoding() {
        val payload = AuraLlmContract.eventPayload(
            operationId = "op-1",
            type = AuraLlmContract.EVENT_TYPE_TOKEN,
            text = "Hola",
        )
        check(payload.keys == setOf("operation_id", "type", "text", "error"))
        check(payload["operation_id"] == "op-1")
        check(payload["type"] == "token")
        check(payload["text"] == "Hola")
        check(payload["error"] == null)

        val rejected = try {
            AuraLlmContract.eventPayload("", "token", null)
            false
        } catch (_: IllegalArgumentException) {
            true
        }
        check(rejected)
        val rejectedType = try {
            AuraLlmContract.eventPayload("op-1", "execute_tool", null)
            false
        } catch (_: IllegalArgumentException) {
            true
        }
        check(rejectedType)
    }
}
