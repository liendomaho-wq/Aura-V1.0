package com.ciberdefensa.aura

import java.io.DataInputStream
import java.io.IOException
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Socks5AuthProtocolTest {
    @Test
    fun completesRfc1929AuthenticationWithTheSuppliedCredentials() {
        val credentials = AuraSocks5Credentials("aura", "a1b2c3")

        assertNull(runHandshake(credentials, expectedPassword = "a1b2c3"))
    }

    @Test
    fun rejectsAServerThatSelectsNoAuthentication() {
        val error = runHandshake(
            AuraSocks5Credentials("aura", "a1b2c3"),
            selectedMethod = 0,
            expectedPassword = "a1b2c3",
        )

        assertTrue(error is IOException)
    }

    @Test
    fun surfacesRfc1929CredentialRejection() {
        val error = runHandshake(
            AuraSocks5Credentials("aura", "wrong-password"),
            expectedPassword = "correct-password",
        )

        assertTrue(error is IOException)
    }

    private fun runHandshake(
        credentials: AuraSocks5Credentials,
        selectedMethod: Int = 2,
        expectedUsername: String = "aura",
        expectedPassword: String,
    ): Throwable? {
        val clientInput = PipedInputStream()
        val clientOutput = PipedOutputStream()
        val serverInput = PipedInputStream(clientOutput)
        val serverOutput = PipedOutputStream(clientInput)
        val serverFailure = AtomicReference<Throwable?>(null)

        val server = Thread {
            try {
                val input = DataInputStream(serverInput)
                assertEquals(5, input.readUnsignedByte())
                assertEquals(1, input.readUnsignedByte())
                assertEquals(2, input.readUnsignedByte())
                serverOutput.write(byteArrayOf(5, selectedMethod.toByte()))
                serverOutput.flush()

                if (selectedMethod == 2) {
                    assertEquals(1, input.readUnsignedByte())
                    val username = ByteArray(input.readUnsignedByte())
                    input.readFully(username)
                    val password = ByteArray(input.readUnsignedByte())
                    input.readFully(password)
                    val accepted =
                        String(username, Charsets.UTF_8) == expectedUsername &&
                            String(password, Charsets.UTF_8) == expectedPassword
                    serverOutput.write(byteArrayOf(1, if (accepted) 0 else 1))
                    serverOutput.flush()
                }
            } catch (error: Throwable) {
                serverFailure.set(error)
            } finally {
                try {
                    serverOutput.close()
                } catch (_: IOException) {
                    // Closing after the reply also unblocks a failed client test.
                }
            }
        }
        server.start()

        var clientFailure: Throwable? = null
        try {
            Socks5AuthProtocol.authenticate(clientInput, clientOutput, credentials)
        } catch (error: Throwable) {
            clientFailure = error
        } finally {
            try {
                clientOutput.close()
            } catch (_: IOException) {
                // The server thread may already have closed its pipe.
            }
        }

        server.join(2000)
        assertFalse("Fake SOCKS5 server did not finish", server.isAlive)
        serverFailure.get()?.let { throw AssertionError("Fake SOCKS5 server failed", it) }
        clientInput.close()
        serverInput.close()
        return clientFailure
    }
}
