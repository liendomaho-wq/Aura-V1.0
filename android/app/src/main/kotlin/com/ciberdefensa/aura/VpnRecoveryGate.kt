package com.ciberdefensa.aura

/**
 * Single-flight ownership for recovery on a retained Android TUN.
 *
 * This gate never starts JNI or asserts that traffic is protected. The service
 * must verify the descriptor, native worker and authenticated SOCKS readiness
 * inside VpnLifecycleGate before it can publish a successful result.
 */
internal class VpnRecoveryGate {
    internal class Attempt internal constructor(val requestId: String?)

    private var active: Attempt? = null

    fun canRetryRetainedTunnel(
        hasValidInterface: Boolean,
        panicIsolationActive: Boolean,
        forwardingVerified: Boolean,
        startInProgress: Boolean,
        closing: Boolean,
    ): Boolean = hasValidInterface && !panicIsolationActive &&
        !forwardingVerified && !startInProgress && !closing

    @Synchronized
    fun tryBegin(requestId: String?): Attempt? {
        if (active != null) return null
        return Attempt(requestId).also { active = it }
    }

    @Synchronized
    fun finish(attempt: Attempt): Boolean {
        if (active !== attempt) return false
        active = null
        return true
    }
}
