package com.ciberdefensa.aura

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/** RFC 1928 method negotiation and RFC 1929 username/password authentication. */
internal object Socks5AuthProtocol {
    private const val VERSION = 5
    private const val USER_PASSWORD_METHOD = 2
    private const val USER_PASSWORD_VERSION = 1

    @Throws(IOException::class)
    fun authenticate(
        input: InputStream,
        output: OutputStream,
        credentials: AuraSocks5Credentials,
    ) {
        val username = credentials.username.toByteArray(Charsets.UTF_8)
        val password = credentials.password.toByteArray(Charsets.UTF_8)
        try {
            if (username.isEmpty() || username.size > 255 ||
                password.isEmpty() || password.size > 255
            ) {
                throw IOException("Las credenciales SOCKS5 locales tienen una longitud no válida.")
            }

            output.write(byteArrayOf(VERSION.toByte(), 1, USER_PASSWORD_METHOD.toByte()))
            output.flush()
            val method = readExactly(input, 2)
            if ((method[0].toInt() and 0xff) != VERSION ||
                (method[1].toInt() and 0xff) != USER_PASSWORD_METHOD
            ) {
                throw IOException("El proxy SOCKS5 local no exige autenticación por contraseña.")
            }

            output.write(USER_PASSWORD_VERSION)
            output.write(username.size)
            output.write(username)
            output.write(password.size)
            output.write(password)
            output.flush()

            val result = readExactly(input, 2)
            if ((result[0].toInt() and 0xff) != USER_PASSWORD_VERSION || result[1].toInt() != 0) {
                throw IOException("El proxy SOCKS5 local rechazó las credenciales efímeras.")
            }
        } finally {
            username.fill(0.toByte())
            password.fill(0.toByte())
        }
    }

    @Throws(IOException::class)
    private fun readExactly(input: InputStream, length: Int): ByteArray {
        val bytes = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val count = input.read(bytes, offset, length - offset)
            if (count < 0) throw IOException("El proxy SOCKS5 local cerró la autenticación.")
            offset += count
        }
        return bytes
    }
}
