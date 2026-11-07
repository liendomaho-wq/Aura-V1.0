package com.ciberdefensa.aura

/** Serializes short native lifecycle operations with service destruction.
 *
 * Keep network waits and SOCKS readiness checks outside the gate. Android TUN
 * establishment and native start/stop must be serialized here; these calls can
 * block, so shutdown responsiveness still needs real-device validation. Once
 * close acquires the gate, all later work from this service instance is refused.
 */
internal class VpnLifecycleGate {
    @Volatile private var closingRequested = false
    private var closed = false

    // This is non-blocking even if a native operation currently holds the gate.
    fun beginClosing() {
        closingRequested = true
    }

    @Synchronized
    fun <T : Any> runIfOpen(action: () -> T): T? {
        if (closingRequested || closed) return null
        return action()
    }

    fun <T> close(action: () -> T): T {
        beginClosing()
        return synchronized(this) {
            check(!closed) { "VPN lifecycle already closed" }
            closed = true
            action()
        }
    }
}
