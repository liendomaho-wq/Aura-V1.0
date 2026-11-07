package com.ciberdefensa.aura

import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class VpnLifecycleGateTest {
    @Test
    fun closingWaitsForInFlightStartAndRefusesLaterWork() {
        val gate = VpnLifecycleGate()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val closeRequested = CountDownLatch(1)
        val steps = Collections.synchronizedList(mutableListOf<String>())
        val failure = AtomicReference<Throwable?>(null)
        val start = Thread {
            try {
                gate.runIfOpen {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    steps.add("start-finished")
                }
            } catch (error: Throwable) { failure.set(error) }
        }
        val close = Thread {
            try {
                closeRequested.countDown()
                gate.close { steps.add("cleanup") }
            } catch (error: Throwable) { failure.set(error) }
        }
        start.start()
        check(entered.await(5, TimeUnit.SECONDS))
        close.start()
        check(closeRequested.await(5, TimeUnit.SECONDS))
        release.countDown()
        start.join(5000)
        close.join(5000)
        check(!start.isAlive && !close.isAlive)
        failure.get()?.let { throw AssertionError(it) }
        check(steps == listOf("start-finished", "cleanup"))
        check(gate.runIfOpen { steps.add("late-start"); true } == null)
        check(steps == listOf("start-finished", "cleanup"))
    }

    @Test
    fun beginClosingRejectsWorkBeforeCleanupAcquiresTheGate() {
        val gate = VpnLifecycleGate()
        gate.beginClosing()
        check(gate.runIfOpen { true } == null)
        check(gate.close { "cleaned" } == "cleaned")
        check(gate.runIfOpen { true } == null)
    }

    @Test
    fun cleanupFailureStillClosesTheGate() {
        val gate = VpnLifecycleGate()
        try {
            gate.close { error("cleanup failed") }
            error("expected cleanup error")
        } catch (expected: IllegalStateException) {
            check(expected.message == "cleanup failed")
        }
        check(gate.runIfOpen { true } == null)
    }
}

fun main() {
    val tests = VpnLifecycleGateTest()
    tests.closingWaitsForInFlightStartAndRefusesLaterWork()
    tests.beginClosingRejectsWorkBeforeCleanupAcquiresTheGate()
    tests.cleanupFailureStillClosesTheGate()
    println("PASS: 3 VPN lifecycle gate tests")
}
