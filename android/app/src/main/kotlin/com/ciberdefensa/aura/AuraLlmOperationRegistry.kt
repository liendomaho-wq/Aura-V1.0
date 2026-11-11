package com.ciberdefensa.aura

import java.util.ArrayDeque
import java.util.UUID

/** Tracks the lifecycle of local LLM generations crossing the Dart boundary.
 *
 * Pure JVM state machine with no Android dependencies so it can be unit
 * tested on the JVM exactly like the VPN gates. Fail-closed rules:
 *
 *  * An operation id exists from [begin] until it reaches a terminal state.
 *  * Only one operation may be RUNNING at a time.
 *  * Cancellation is cooperative: [requestCancel] records the request but the
 *    operation stays active until a native terminal event confirms it. That
 *    guarantees Dart always observes exactly one terminal event.
 *  * Terminal operations never transition again; late native events for a
 *    terminal operation are dropped by the caller instead of being rewritten.
 *  * QUEUED may only move to RUNNING, CANCELLED or FAILED; RUNNING only to
 *    COMPLETED, CANCELLED or FAILED.
 *  * History is bounded so a long session cannot grow it without limit.
 */
internal class AuraLlmOperationRegistry(
    private val idGenerator: () -> String = { "op-${UUID.randomUUID()}" },
    private val maxHistory: Int = 256,
) {
    enum class State { QUEUED, RUNNING, COMPLETED, FAILED, CANCELLED }

    data class Operation(
        val id: String,
        val state: State,
        val cancelRequested: Boolean = false,
        val error: String? = null,
    )

    private val operations = LinkedHashMap<String, Operation>()
    private val terminalOrder = ArrayDeque<String>()

    /** Registers a new operation as QUEUED and returns its identifier. */
    @Synchronized
    fun begin(): String {
        check(stateOfRunningLocked() == null) { "llm_generation_busy" }
        val id = idGenerator()
        check(!operations.containsKey(id)) { "llm_operation_id_collision" }
        operations[id] = Operation(id, State.QUEUED)
        return id
    }

    /** Marks a QUEUED operation as RUNNING. Idempotent for a running id. */
    @Synchronized
    fun markRunning(id: String): Boolean {
        val current = operations[id] ?: return false
        if (current.state == State.RUNNING) return true
        if (current.state != State.QUEUED) return false
        if (stateOfRunningLocked() != null) return false
        operations[id] = current.copy(state = State.RUNNING)
        return true
    }

    @Synchronized
    fun markCompleted(id: String): Boolean =
        transitionLocked(id, State.COMPLETED, expected = setOf(State.RUNNING))

    @Synchronized
    fun markFailed(id: String, error: String): Boolean {
        if (error.isEmpty()) return false
        return transitionLocked(id, State.FAILED, expected = setOf(State.QUEUED, State.RUNNING), error)
    }

    /** Terminalizes a cancelled operation after the native side confirmed it. */
    @Synchronized
    fun markCancelled(id: String): Boolean =
        transitionLocked(id, State.CANCELLED, expected = setOf(State.QUEUED, State.RUNNING))

    /**
     * Records a cooperative cancellation request.
     *
     * The operation stays QUEUED/RUNNING until a native terminal event arrives,
     * so the caller is never left without a terminal event. Returns false for
     * unknown or already-terminal operations.
     */
    @Synchronized
    fun requestCancel(id: String): Boolean {
        val current = operations[id] ?: return false
        if (isTerminal(current.state)) return false
        if (current.cancelRequested) return true
        operations[id] = current.copy(cancelRequested = true)
        return true
    }

    @Synchronized
    fun isCancelRequested(id: String): Boolean =
        operations[id]?.cancelRequested == true

    @Synchronized
    fun stateOf(id: String): State? = operations[id]?.state

    @Synchronized
    fun hasActiveOperations(): Boolean =
        operations.values.any { !isTerminal(it.state) }

    /** Immutable snapshot ordered by registration. */
    @Synchronized
    fun snapshot(): List<Operation> = operations.values.toList()

    private fun transitionLocked(
        id: String,
        next: State,
        expected: Set<State>,
        error: String? = null,
    ): Boolean {
        val current = operations[id] ?: return false
        if (current.state !in expected) return false
        val updated = current.copy(state = next, error = error)
        operations[id] = updated
        if (isTerminal(next)) {
            terminalOrder.addLast(id)
            evictLocked()
        }
        return true
    }

    private fun stateOfRunningLocked(): String? =
        operations.values.firstOrNull { it.state == State.RUNNING }?.id

    private fun isTerminal(state: State): Boolean =
        state == State.COMPLETED || state == State.FAILED || state == State.CANCELLED

    private fun evictLocked() {
        while (terminalOrder.size > maxHistory) {
            val oldest = terminalOrder.removeFirst()
            val operation = operations[oldest]
            if (operation != null && isTerminal(operation.state)) {
                operations.remove(oldest)
            }
        }
    }
}
