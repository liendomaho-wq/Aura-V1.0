package com.ciberdefensa.aura

import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class VpnRecoveryGateTest {
    @Test
    fun retriesStoppedForwardingButNeverIsolationInvalidTunStartupOrClosing() {
        val gate = VpnRecoveryGate()
        check(gate.canRetryRetainedTunnel(true, false, false, false, false))
        check(!gate.canRetryRetainedTunnel(false, false, false, false, false))
        check(!gate.canRetryRetainedTunnel(true, true, false, false, false))
        check(!gate.canRetryRetainedTunnel(true, false, true, false, false))
        check(!gate.canRetryRetainedTunnel(true, false, false, true, false))
        check(!gate.canRetryRetainedTunnel(true, false, false, false, true))
    }

    @Test
    fun failedAutomaticRecoveryReleasesOwnershipForAnExplicitRetry() {
        val gate = VpnRecoveryGate()
        val automatic = checkNotNull(gate.tryBegin(null))
        check(automatic.requestId == null)
        check(gate.tryBegin("concurrent") == null)
        check(gate.finish(automatic))
        val explicit = checkNotNull(gate.tryBegin("retry-after-network-failure"))
        check(explicit.requestId == "retry-after-network-failure")
        check(gate.finish(explicit))
    }

    @Test
    fun lateCompletionCannotReleaseANewerRecovery() {
        val gate = VpnRecoveryGate()
        val first = checkNotNull(gate.tryBegin("first"))
        check(gate.finish(first))
        val second = checkNotNull(gate.tryBegin("second"))
        check(!gate.finish(first))
        check(gate.tryBegin("third") == null)
        check(second.requestId == "second")
        check(gate.finish(second))
    }

    @Test
    fun recoveryResultOnlyMatchesItsOwnActivityRequest() {
        val activity = VpnStartRequestGate()
        val recovery = VpnRecoveryGate()
        check(activity.begin())
        check(activity.beginServiceRequest("user-retry"))
        val attempt = checkNotNull(recovery.tryBegin("user-retry"))
        check(!activity.matchesServiceResponse(null))
        check(!activity.matchesServiceResponse("old-request"))
        check(activity.matchesServiceResponse(attempt.requestId))
        check(recovery.finish(attempt))
        activity.finish()
        check(!activity.matchesServiceResponse(attempt.requestId))
    }

    @Test
    fun finallyReleasesOwnershipWhenTheRecoveryOperationThrows() {
        val gate = VpnRecoveryGate()
        val attempt = checkNotNull(gate.tryBegin("failed"))
        try {
            try {
                throw IllegalStateException("recovery operation failed")
            } finally {
                check(gate.finish(attempt))
            }
        } catch (expected: IllegalStateException) {
            check(expected.message == "recovery operation failed")
        }
        check(gate.tryBegin("retry")?.requestId == "retry")
    }

    @Test
    fun closingLifecycleStillRefusesRecoveryWork() {
        val lifecycle = VpnLifecycleGate()
        val recovery = VpnRecoveryGate()
        val attempt = checkNotNull(recovery.tryBegin("before-close"))
        lifecycle.beginClosing()
        check(lifecycle.runIfOpen { error("closed lifecycle must not run this") } == null)
        check(recovery.finish(attempt))
        check(lifecycle.close { "closed" } == "closed")
        check(lifecycle.runIfOpen { true } == null)
    }

    @Test
    fun concurrentRequestsHaveExactlyOneRecoveryOwner() {
        val gate = VpnRecoveryGate()
        val ready = CountDownLatch(12)
        val release = CountDownLatch(1)
        val attempts = Collections.synchronizedList(mutableListOf<VpnRecoveryGate.Attempt>())
        val failures = Collections.synchronizedList(mutableListOf<Throwable>())
        val threads = (1..12).map { index ->
            Thread {
                try {
                    ready.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    gate.tryBegin("request-$index")?.let { attempts.add(it) }
                } catch (error: Throwable) {
                    failures.add(error)
                }
            }.also { it.start() }
        }
        check(ready.await(5, TimeUnit.SECONDS))
        release.countDown()
        threads.forEach { it.join(5000); check(!it.isAlive) }
        check(failures.isEmpty()) { failures.toString() }
        check(attempts.size == 1)
        check(gate.finish(attempts.single()))
        check(gate.tryBegin("after-concurrency")?.requestId == "after-concurrency")
    }
}
