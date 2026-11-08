package com.ciberdefensa.aura

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Test

class LocalAuthRequestGateTest {
    @Test
    fun concurrentPromptIsRejectedWithoutReplacingOriginalResult() {
        val gate = LocalAuthRequestGate<String>()
        val original = checkNotNull(gate.begin("original"))
        check(gate.begin("replacement") == null)
        check(gate.complete(original) == "original")
    }

    @Test
    fun successfulCallbackIsConsumedOnlyOnce() {
        val gate = LocalAuthRequestGate<String>()
        val ticket = checkNotNull(gate.begin("result"))
        check(gate.complete(ticket) == "result")
        check(gate.complete(ticket) == null)
    }

    @Test
    fun oldCallbackCannotConsumeNewPrompt() {
        val gate = LocalAuthRequestGate<String>()
        val first = checkNotNull(gate.begin("first"))
        check(gate.complete(first) == "first")
        val second = checkNotNull(gate.begin("second"))
        check(gate.complete(first) == null)
        check(gate.complete(second) == "second")
    }

    @Test
    fun destructionTakesResultOnceAndRejectsLateCallbacksAndStarts() {
        val gate = LocalAuthRequestGate<String>()
        val ticket = checkNotNull(gate.begin("pending"))
        check(gate.close() == "pending")
        check(gate.close() == null)
        check(gate.complete(ticket) == null)
        check(gate.begin("late") == null)
    }

    @Test
    fun destructionBeforeAnyPromptStillRejectsFutureStarts() {
        val gate = LocalAuthRequestGate<String>()
        check(gate.close() == null)
        check(gate.begin("late") == null)
    }

    @Test
    fun completionReleasesGateForAnotherRequest() {
        val gate = LocalAuthRequestGate<String>()
        val failedPrompt = checkNotNull(gate.begin("failure"))
        check(gate.complete(failedPrompt) == "failure")
        val retry = checkNotNull(gate.begin("retry"))
        check(gate.complete(retry) == "retry")
    }

    @Test
    fun racingThreadsHaveExactlyOneOwner() {
        val gate = LocalAuthRequestGate<String>()
        val ready = CountDownLatch(8)
        val release = CountDownLatch(1)
        val owners = Collections.synchronizedList(
            mutableListOf<LocalAuthRequestGate.Ticket<String>>()
        )
        val failure = AtomicReference<Throwable?>(null)
        val threads = (0 until 8).map { index ->
            Thread {
                try {
                    ready.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    gate.begin("request-$index")?.let { owners.add(it) }
                } catch (error: Throwable) {
                    failure.compareAndSet(null, error)
                }
            }.also { it.start() }
        }
        check(ready.await(5, TimeUnit.SECONDS))
        release.countDown()
        threads.forEach { it.join(5000); check(!it.isAlive) }
        failure.get()?.let { throw AssertionError(it) }
        check(owners.size == 1)
        check(gate.complete(owners.single()) == owners.single().result)
    }
}
