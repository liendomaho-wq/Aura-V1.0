package com.ciberdefensa.aura

import java.security.SecureRandom

/** Ephemeral credentials shared only by Aura's native SOCKS5 listener and tunnel client. */
internal class AuraSocks5Credentials(
    val username: String,
    val password: String,
) {
    init {
        require(username.isSocks5Token())
        require(password.isSocks5Token())
    }

    companion object {
        private const val PASSWORD_BYTES = 32
        private const val HEX = "0123456789abcdef"
        private const val LOCAL_USERNAME = "aura"

        fun generate(random: SecureRandom = SecureRandom()): AuraSocks5Credentials {
            val secret = ByteArray(PASSWORD_BYTES)
            return try {
                random.nextBytes(secret)
                val encoded = buildString(PASSWORD_BYTES * 2) {
                    for (byte in secret) {
                        val value = byte.toInt() and 0xff
                        append(HEX[value ushr 4])
                        append(HEX[value and 0x0f])
                    }
                }
                AuraSocks5Credentials(LOCAL_USERNAME, encoded)
            } finally {
                secret.fill(0)
            }
        }
    }
}

private fun String.isSocks5Token(): Boolean =
    isNotEmpty() && length <= 255 && all { character ->
        character in 'a'..'z' || character in 'A'..'Z' ||
            character in '0'..'9' || character == '-' || character == '_'
    }
