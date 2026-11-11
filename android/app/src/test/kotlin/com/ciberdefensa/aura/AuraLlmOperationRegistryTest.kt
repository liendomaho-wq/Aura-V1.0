package com.ciberdefensa.aura

import org.junit.Test
import java.util.UUID

class AuraLlmOperationRegistryTest {
    private fun registry() = AuraLlmOperationRegistry(
        idGenerator = { "op-${UUID.randomUUID()}" },
    )

    @Test
    fun beginReturnsUniqueIdentifiers() {
        val registry = registry()
        val first = registry.begin()
        val second = registry.begin()
        check(first.isNotEmpty())
        check(second.isNotEmpty())
        check(first != second)
        check(registry.stateOf(first) == AuraLlmOperationRegistry.State.QUEUED)
        check(registry.stateOf(second) == AuraLlmOperationRegistry.State.QUEUED)
    }

    @Test
    fun queuedOperationsMayCoexistButOnlyOneRuns() {
        val registry = registry()
        val first = registry.begin()
        val second = registry.begin()
        check(registry.markRunning(first))
        check(!registry.markRunning(second))
        check(registry.stateOf(first) == AuraLlmOperationRegistry.State.RUNNING)
        check(registry.stateOf(second) == AuraLlmOperationRegistry.State.QUEUED)
        check(registry.markCompleted(first))
        check(registry.markRunning(second))
    }

    @Test
    fun markRunningIsIdempotentOnlyWhileRunning() {
        val registry = registry()
        val operation = registry.begin()
        check(registry.markRunning(operation))
        check(registry.markRunning(operation))
        check(registry.markCompleted(operation))
        check(!registry.markRunning(operation))
    }

    @Test
    fun beginRefusesWhileAnOperationRuns() {
        val registry = registry()
        val operation = registry.begin()
        registry.markRunning(operation)
        val threw = try {
            registry.begin()
            false
        } catch (error: IllegalStateException) {
            error.message == "llm_generation_busy"
        }
        check(threw)
        registry.markCompleted(operation)
        check(registry.begin().isNotEmpty())
    }

    @Test
    fun completedOperationsNeverTransitionAgain() {
        val registry = registry()
        val operation = registry.begin()
        registry.markRunning(operation)
        check(registry.markCompleted(operation))
        check(!registry.markCompleted(operation))
        check(!registry.markFailed(operation, "late"))
        check(!registry.markCancelled(operation))
        check(!registry.requestCancel(operation))
        check(registry.stateOf(operation) == AuraLlmOperationRegistry.State.COMPLETED)
    }

    @Test
    fun failedOperationsAcceptOnlyQueuedAndRunningSources() {
        val registry = registry()
        val queued = registry.begin()
        check(registry.markFailed(queued, "native_rejected"))
        check(!registry.markFailed(queued, "again"))
        val running = registry.begin()
        registry.markRunning(running)
        check(registry.markFailed(running, "decode_failed"))
        check(registry.stateOf(running) == AuraLlmOperationRegistry.State.FAILED)
    }

    @Test
    fun emptyErrorMessagesAreRejected() {
        val registry = registry()
        val operation = registry.begin()
        check(!registry.markFailed(operation, ""))
        check(registry.stateOf(operation) == AuraLlmOperationRegistry.State.QUEUED)
    }

    @Test
    fun cancelRequestIsCooperativeUntilNativeConfirmation() {
        val registry = registry()
        val queued = registry.begin()
        check(registry.requestCancel(queued))
        check(registry.isCancelRequested(queued))
        // Still active: Dart must receive a terminal event from the native side.
        check(registry.stateOf(queued) == AuraLlmOperationRegistry.State.QUEUED)
        check(registry.hasActiveOperations())
        check(registry.markCancelled(queued))
        check(registry.stateOf(queued) == AuraLlmOperationRegistry.State.CANCELLED)
        check(!registry.hasActiveOperations())
        check(!registry.requestCancel(queued))
        check(!registry.markCancelled(queued))

        val running = registry.begin()
        registry.markRunning(running)
        check(registry.requestCancel(running))
        check(registry.requestCancel(running))  // Idempotent while active.
        check(registry.stateOf(running) == AuraLlmOperationRegistry.State.RUNNING)
        check(registry.markCancelled(running))
        check(!registry.requestCancel("does-not-exist"))
    }

    @Test
    fun completedWithoutRunningIsRejected() {
        val registry = registry()
        val operation = registry.begin()
        check(!registry.markCompleted(operation))
        check(registry.stateOf(operation) == AuraLlmOperationRegistry.State.QUEUED)
    }

    @Test
    fun unknownIdentifiersAreRejectedFailClosed() {
        val registry = registry()
        check(!registry.markRunning("unknown"))
        check(!registry.markCompleted("unknown"))
        check(!registry.markFailed("unknown", "reason"))
        check(!registry.markCancelled("unknown"))
        check(!registry.requestCancel("unknown"))
        check(!registry.isCancelRequested("unknown"))
        check(registry.stateOf("unknown") == null)
    }

    @Test
    fun hasActiveOperationsTracksEveryNonTerminalState() {
        val registry = registry()
        check(!registry.hasActiveOperations())
        val queued = registry.begin()
        check(registry.hasActiveOperations())
        registry.markRunning(queued)
        check(registry.hasActiveOperations())
        registry.requestCancel(queued)
        check(registry.hasActiveOperations())
        registry.markCancelled(queued)
        check(!registry.hasActiveOperations())
    }

    @Test
    fun terminalHistoryIsBounded() {
        val registry = AuraLlmOperationRegistry(
            idGenerator = { "op-${UUID.randomUUID()}" },
            maxHistory = 1,
        )
        val first = registry.begin()
        registry.markFailed(first, "done")
        val second = registry.begin()
        registry.requestCancel(second)
        registry.markCancelled(second)
        val third = registry.begin()
        registry.markRunning(third)
        registry.markCompleted(third)
        check(registry.stateOf(first) == null)
        check(registry.stateOf(second) == null)
        check(registry.stateOf(third) == AuraLlmOperationRegistry.State.COMPLETED)
        check(registry.snapshot().size <= 1)
    }

    @Test
    fun snapshotsAreIndependentOfRegistryMutation() {
        val registry = registry()
        val first = registry.begin()
        val second = registry.begin()
        val snapshot = registry.snapshot().toMutableList()
        check(snapshot.map { it.id } == listOf(first, second))
        snapshot.clear()
        check(registry.snapshot().size == 2)
    }

    @Test
    fun concurrentTransitionsOnOneOperationYieldOneTerminalState() {
        // Real threads: cancel and completion race for the same operation.
        // The registry must always end in exactly one terminal state and
        // never leave a dangling active operation.
        repeat(32) {
            val registry = registry()
            val operation = registry.begin()
            val start = java.util.concurrent.CountDownLatch(1)
            val threads = (1..8).map { index ->
                Thread {
                    start.await()
                    if (index % 2 == 0) {
                        if (registry.markRunning(operation)) {
                            if (registry.isCancelRequested(operation)) {
                                registry.markCancelled(operation)
                            } else {
                                registry.markCompleted(operation)
                            }
                        }
                    } else {
                        if (registry.requestCancel(operation)) {
                            registry.markCancelled(operation)
                        }
                    }
                }
            }
            threads.forEach { it.start() }
            start.countDown()
            threads.forEach { it.join() }
            val state = registry.stateOf(operation)
            check(
                state == AuraLlmOperationRegistry.State.COMPLETED ||
                    state == AuraLlmOperationRegistry.State.CANCELLED,
            ) { "Operation ended in $state" }
            check(!registry.hasActiveOperations())
        }
    }
}
