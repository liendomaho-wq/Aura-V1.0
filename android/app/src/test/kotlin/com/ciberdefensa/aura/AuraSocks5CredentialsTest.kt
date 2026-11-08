package com.ciberdefensa.aura

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AuraSocks5CredentialsTest {
    @Test
    fun generatesFreshFixedLengthHexadecimalPasswords() {
        val credentials = List(32) { AuraSocks5Credentials.generate() }

        assertTrue(credentials.all { it.username == "aura" })
        assertTrue(credentials.all { it.password.length == 64 })
        assertTrue(credentials.all { it.password.all { character -> character in '0'..'9' || character in 'a'..'f' } })
        assertEquals(credentials.size, credentials.map { it.password }.toSet().size)
    }
}
