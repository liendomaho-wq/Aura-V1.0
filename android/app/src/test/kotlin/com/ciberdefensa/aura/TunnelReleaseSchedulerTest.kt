package com.ciberdefensa.aura

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelReleaseSchedulerTest {
    @Test
    fun slowReleaseDoesNotBlockTheCaller() {
        val caller = Thread.currentThread()
        val ranOn = AtomicReference<Thread>()
        val releaseEntered = CountDownLatch(1)
        val allowReleaseToFinish = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        val scheduler = TunnelReleaseScheduler(executor) {
            ranOn.set(Thread.currentThread())
            releaseEntered.countDown()
            check(allowReleaseToFinish.await(2, TimeUnit.SECONDS))
            true
        }
        val startedAt = System.nanoTime()
        assertTrue(scheduler.schedule { })
        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
        assertTrue("schedule blocked the caller for ${elapsedMs}ms", elapsedMs < 500)
        assertTrue(releaseEntered.await(2, TimeUnit.SECONDS))
        assertNotEquals(caller, ranOn.get())
        allowReleaseToFinish.countDown()
        executor.shutdown()
        assertTrue(executor.awaitTermination(2, TimeUnit.SECONDS))
    }
}
