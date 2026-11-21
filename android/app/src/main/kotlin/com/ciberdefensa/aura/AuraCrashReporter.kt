package com.ciberdefensa.aura

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Lightweight on-device crash capture for testers without adb.
 *
 * - Uncaught Java/Kotlin exceptions are written to the app files dir before
 *   the previous (system) handler kills the process.
 * - Native crashes (SIGSEGV/SIGABRT in the tunnel engine) and ANRs cannot be
 *   caught in-process; on the next launch Android 11+ exposes them through
 *   ApplicationExitInfo, including the tombstone/trace, which is saved too.
 * - The last VPN start failure (non-fatal) is stored with its stack trace.
 *
 * The combined text is exposed to Flutter so the user can copy and send it.
 */
object AuraCrashReporter {
    private const val TAG = "AuraCrash"
    private const val CRASH_FILE = "aura_last_crash.txt"
    private const val EXIT_FILE = "aura_last_exit.txt"
    private const val VPN_ERROR_FILE = "aura_last_vpn_error.txt"
    private const val PREFERENCES = "aura_crash_reporter"
    private const val LAST_EXIT_TIMESTAMP = "last_exit_timestamp"
    private const val MAX_TRACE_CHARS = 24_000

    @Volatile private var installed = false

    @JvmStatic
    fun install(context: Context) {
        if (installed) return
        synchronized(this) {
            if (installed) return
            val appContext = context.applicationContext
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                try {
                    writeFile(
                        appContext,
                        CRASH_FILE,
                        header(appContext, "CIERRE INESPERADO (Java/Kotlin)") +
                            "Hilo: ${thread.name}\n\n" + stackTrace(error),
                    )
                } catch (_: Throwable) {
                    // Never prevent the platform handler from running.
                }
                if (previous != null) {
                    previous.uncaughtException(thread, error)
                } else {
                    android.os.Process.killProcess(android.os.Process.myPid())
                    System.exit(10)
                }
            }
            installed = true
        }
    }

    @JvmStatic
    fun recordVpnFailure(context: Context, stage: String, error: Throwable) {
        try {
            writeFile(
                context.applicationContext,
                VPN_ERROR_FILE,
                header(context, "FALLO AL INICIAR LA VPN (sin cierre)") +
                    "Etapa: $stage\n\n" + stackTrace(error),
            )
        } catch (exception: Exception) {
            Log.w(TAG, "No se pudo guardar el diagnóstico de la VPN.", exception)
        }
    }

    /**
     * Imports the most recent abnormal process exit recorded by Android (native
     * crash, Java crash or ANR) that has not been imported yet. Do not call on
     * the main thread: reading a tombstone can take a moment.
     */
    @JvmStatic
    fun importLastProcessExit(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val appContext = context.applicationContext
            val manager = appContext.getSystemService(ActivityManager::class.java) ?: return
            val preferences = appContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val lastImported = preferences.getLong(LAST_EXIT_TIMESTAMP, 0L)
            val exit = manager.getHistoricalProcessExitReasons(appContext.packageName, 0, 10)
                .filter { it.timestamp > lastImported }
                .filter {
                    it.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
                        it.reason == ApplicationExitInfo.REASON_CRASH ||
                        it.reason == ApplicationExitInfo.REASON_ANR
                }
                .maxByOrNull { it.timestamp } ?: return
            val reason = when (exit.reason) {
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH NATIVO (motor C/JNI)"
                ApplicationExitInfo.REASON_CRASH -> "CRASH Java/Kotlin"
                else -> "ANR (la app dejó de responder)"
            }
            val trace = try {
                exit.traceInputStream?.use { stream ->
                    val bytes = stream.readBytes()
                    if (exit.reason == ApplicationExitInfo.REASON_ANR) {
                        String(bytes, Charsets.UTF_8)
                    } else {
                        // Native tombstones are protobuf: keep the readable parts
                        // (abort message, signal, backtrace symbols, maps).
                        printableStrings(bytes)
                    }
                }.orEmpty()
            } catch (exception: Exception) {
                "No se pudo leer la traza: ${exception.javaClass.simpleName}"
            }
            val text = header(appContext, "SALIDA ANORMAL DETECTADA: $reason") +
                "Fecha del cierre: ${formatTime(exit.timestamp)}\n" +
                "Proceso: ${exit.processName} (pid ${exit.pid})\n" +
                "Estado: ${exit.status}  Importancia: ${exit.importance}\n" +
                "Descripción: ${exit.description.orEmpty()}\n\n" +
                trace.take(MAX_TRACE_CHARS)
            writeFile(appContext, EXIT_FILE, text)
            preferences.edit().putLong(LAST_EXIT_TIMESTAMP, exit.timestamp).apply()
        } catch (exception: Exception) {
            Log.w(TAG, "No se pudo leer el historial de cierres de Android.", exception)
        }
    }

    @JvmStatic
    fun lastReport(context: Context): String? {
        val appContext = context.applicationContext
        val sections = listOf(CRASH_FILE, EXIT_FILE, VPN_ERROR_FILE).mapNotNull { name ->
            val file = File(appContext.filesDir, name)
            if (!file.isFile) null else try {
                file.readText(Charsets.UTF_8).takeIf { it.isNotBlank() }
            } catch (_: Exception) {
                null
            }
        }
        return if (sections.isEmpty()) null else sections.joinToString("\n\n----------\n\n")
    }

    @JvmStatic
    fun clear(context: Context): Boolean {
        val appContext = context.applicationContext
        val filesCleared = listOf(CRASH_FILE, EXIT_FILE, VPN_ERROR_FILE).all { name ->
            val file = File(appContext.filesDir, name)
            !file.exists() || file.delete()
        }
        val preferencesCleared = appContext
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        return filesCleared && preferencesCleared
    }

    private fun header(context: Context, title: String): String {
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Exception) {
            "?"
        }
        return "=== Aura · $title ===\n" +
            "Registrado: ${formatTime(System.currentTimeMillis())}\n" +
            "App: ${context.packageName} $version\n" +
            "Dispositivo: ${Build.MANUFACTURER} ${Build.MODEL} · Android " +
            "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · " +
            "ABI ${Build.SUPPORTED_ABIS.firstOrNull().orEmpty()}\n"
    }

    private fun stackTrace(error: Throwable): String {
        val writer = StringWriter()
        PrintWriter(writer).use { error.printStackTrace(it) }
        return writer.toString().take(MAX_TRACE_CHARS)
    }

    private fun printableStrings(bytes: ByteArray): String {
        val output = StringBuilder()
        val current = StringBuilder()
        fun flush() {
            if (current.length >= 6) output.append(current).append('\n')
            current.setLength(0)
        }
        for (byte in bytes) {
            val value = byte.toInt() and 0xFF
            if (value in 0x20..0x7E) current.append(value.toChar()) else flush()
            if (output.length >= MAX_TRACE_CHARS) break
        }
        flush()
        return output.toString()
    }

    private fun formatTime(timestamp: Long): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date(timestamp))

    private fun writeFile(context: Context, name: String, text: String) {
        val target = File(context.filesDir, name)
        val temporary = File(context.filesDir, "$name.tmp")
        temporary.writeText(text, Charsets.UTF_8)
        if (!temporary.renameTo(target)) {
            target.writeText(text, Charsets.UTF_8)
            temporary.delete()
        }
    }
}
