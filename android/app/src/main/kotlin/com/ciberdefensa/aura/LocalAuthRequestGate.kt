package com.ciberdefensa.aura

/** One owner across biometric/credential prompts. This does not bind vault keys. */
internal class LocalAuthRequestGate<T : Any> {
    class Ticket<T : Any> internal constructor(val result: T)

    private var active: Ticket<T>? = null
    private var closed = false

    @Synchronized
    fun begin(result: T): Ticket<T>? {
        if (closed || active != null) return null
        return Ticket(result).also { active = it }
    }

    @Synchronized
    fun complete(ticket: Ticket<T>): T? {
        if (active !== ticket) return null
        active = null
        return ticket.result
    }

    @Synchronized
    fun close(): T? {
        closed = true
        return active?.result.also { active = null }
    }
}
