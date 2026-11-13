package com.ciberdefensa.aura

import android.app.ActivityManager
import android.content.Context
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Reports app-private free space and Android memory pressure to
 * lib/infrastructure/storage/aura_storage.dart.
 *
 * The model download is 1 GiB, so setup must know whether the device can hold
 * it before starting, and the planner uses memory pressure to choose a bounded
 * context. The channel is read-only and accepts no arguments.
 */
internal object AuraStoragePlugin {
    private const val CHANNEL = "com.ciberdefensa.aura/storage"

    fun install(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> {
                        try {
                            val stat = StatFs(context.filesDir.absolutePath)
                            result.success(stat.availableBytes)
                        } catch (error: Throwable) {
                            result.error(
                                "storage_unavailable",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                    "memoryInfo" -> {
                        try {
                            val manager = context.getSystemService(
                                Context.ACTIVITY_SERVICE,
                            ) as? ActivityManager
                            if (manager == null) {
                                result.error(
                                    "memory_unavailable",
                                    "ActivityManager is unavailable.",
                                    null,
                                )
                            } else {
                                val info = ActivityManager.MemoryInfo()
                                manager.getMemoryInfo(info)
                                result.success(
                                    mapOf(
                                        "total_bytes" to info.totalMem,
                                        "available_bytes" to info.availMem,
                                        "threshold_bytes" to info.threshold,
                                        "low_memory" to info.lowMemory,
                                    ),
                                )
                            }
                        } catch (error: Throwable) {
                            result.error(
                                "memory_unavailable",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
