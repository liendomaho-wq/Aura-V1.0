package com.ciberdefensa.aura

import android.content.Context
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Reports free space on the app-private volume to lib/infrastructure/storage/aura_storage.dart.
 *
 * The model download is 1 GiB, so the setup UI must know whether the device can
 * hold it before starting. The channel is read-only and accepts no arguments.
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
                    else -> result.notImplemented()
                }
            }
    }
}
