package com.ciberdefensa.aura

import android.os.Handler
import android.os.Looper

/** Loads libaura_llm.so and forwards native events to the main thread.
 *
 * Fail-closed: if the library or its worker thread cannot start, every
 * capability reports unavailable and no generation is dispatched. The class
 * never claims resources it does not hold, and native error strings are
 * surfaced verbatim instead of being coerced into success codes.
 */
internal object AuraLlmBridge {
    /** True only when libaura_llm.so loaded and JNI_OnLoad resolved. */
    val libraryAvailable: Boolean

    /** True only when the native worker thread attached to the JVM. */
    val workerReady: Boolean

    private val mainHandler = Handler(Looper.getMainLooper())

    // Set by AuraLlmPlugin; invoked on the main thread only.
    @Volatile
    private var eventListener: ((operationId: String, type: String, text: String?) -> Unit)? = null

    init {
        var libraryLoaded = false
        var workerStarted = false
        try {
            System.loadLibrary("aura_llm")
            libraryLoaded = true
            workerStarted = nativeStartup()
        } catch (_: Throwable) {
            libraryLoaded = false
            workerStarted = false
        }
        libraryAvailable = libraryLoaded
        workerReady = workerStarted
    }

    fun setEventListener(
        listener: ((operationId: String, type: String, text: String?) -> Unit)?,
    ) {
        eventListener = listener
    }

    /** Called from the native worker thread; never blocks it. */
    @JvmStatic
    fun onNativeEvent(operationId: String, typeCode: Int, text: String?) {
        val listener = eventListener ?: return
        val type = when (typeCode) {
            0 -> AuraLlmContract.EVENT_TYPE_TOKEN
            1 -> AuraLlmContract.EVENT_TYPE_COMPLETED
            else -> AuraLlmContract.EVENT_TYPE_ERROR
        }
        mainHandler.post { listener(operationId, type, text) }
    }

    external fun nativeStartup(): Boolean

    external fun nativeIsModelLoaded(): Boolean

    external fun nativeMaxContextTokens(): Int

    /** 0 = ok, 1 = already loaded, 2 = model load failed, 3 = context failed, 4 = rejected. */
    external fun nativeLoadModel(modelPath: String, contextTokens: Int, threads: Int): Int

    external fun nativeGetLastError(): String?

    /** 0 = accepted, 1 = no model, 4 = rejected. */
    external fun nativeStartGeneration(
        operationId: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
    ): Int

    external fun nativeCancelGeneration(operationId: String): Boolean

    /** 0 = ok, 4 = busy with queued or running generations. */
    external fun nativeUnloadModel(): Int
}
