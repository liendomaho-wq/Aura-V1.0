package com.ciberdefensa.aura

/**
 * Runs the blocking native join off the caller thread.
 * [schedule] returns as soon as the work is queued.
 */
internal class TunnelReleaseScheduler(
    private val executor: java.util.concurrent.Executor,
    private val release: () -> Boolean,
) {
    private val scheduled = java.util.concurrent.atomic.AtomicBoolean(false)

    fun schedule(after: (Boolean) -> Unit): Boolean {
        if (!scheduled.compareAndSet(false, true)) return false
        executor.execute {
            val confirmed = release()
            after(confirmed)
        }
        return true
    }
}
