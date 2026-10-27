package com.ciberdefensa.aura

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalSocks5ProxyTest {
    private val testUsername = "aura-test-user"
    private val testPassword = "aura-test-password"

    @Test
    fun tcpConnectUsesLocalProxyAndRelaysBytes() {
        val loopback = InetAddress.getByName("127.0.0.1")
        ServerSocket(0, 1, loopback).use { echoServer ->
            val echoReady = CountDownLatch(1)
            val echoThread = thread(isDaemon = true) {
                echoServer.accept().use { upstream ->
                    echoReady.countDown()
                    val buffer = ByteArray(64)
                    val count = upstream.getInputStream().read(buffer)
                    if (count > 0) {
                        upstream.getOutputStream().write(buffer, 0, count)
                        upstream.getOutputStream().flush()
                    }
                }
            }

            val proxy = LocalSocks5Proxy(
                requestedPort = 0,
                username = testUsername,
                password = testPassword,
                protectTcpSocket = { true },
                protectUdpSocket = { true },
            )
            try {
                val proxyPort = proxy.start()
                Socket(loopback, proxyPort).use { client ->
                    client.soTimeout = 3000
                    val output = client.getOutputStream()
                    val input = client.getInputStream()
                    authenticate(output, input)

                    val targetPort = echoServer.localPort
                    output.write(
                        byteArrayOf(
                            5, 1, 0, 1, 127, 0, 0, 1,
                            (targetPort shr 8).toByte(), targetPort.toByte(),
                        ),
                    )
                    output.flush()
                    val reply = readExactly(input, 10)
                    assertEquals(5, reply[0].toInt())
                    assertEquals(0, reply[1].toInt())
                    assertTrue(echoReady.await(2, TimeUnit.SECONDS))

                    val payload = "aura-local-tcp".toByteArray(Charsets.UTF_8)
                    output.write(payload)
                    output.flush()
                    assertArrayEquals(payload, readExactly(input, payload.size))
                }
                echoThread.join(1000)
            } finally {
                proxy.close()
            }
        }
    }

    @Test
    fun udpAssociateRelaysDatagrams() {
        val loopback = InetAddress.getByName("127.0.0.1")
        DatagramSocket(null).use { echoServer ->
            echoServer.bind(InetSocketAddress(loopback, 0))
            echoServer.soTimeout = 3000
            val echoThread = thread(isDaemon = true) {
                val buffer = ByteArray(1024)
                val request = DatagramPacket(buffer, buffer.size)
                echoServer.receive(request)
                echoServer.send(
                    DatagramPacket(request.data, request.length, request.address, request.port),
                )
            }

            val proxy = LocalSocks5Proxy(
                requestedPort = 0,
                protectTcpSocket = { true },
                protectUdpSocket = { true },
            )
            try {
                val proxyPort = proxy.start()
                Socket(loopback, proxyPort).use { control ->
                    control.soTimeout = 3000
                    val output = control.getOutputStream()
                    val input = control.getInputStream()
                    authenticate(output, input)

                    output.write(byteArrayOf(5, 3, 0, 1, 0, 0, 0, 0, 0, 0))
                    output.flush()
                    val reply = readExactly(input, 10)
                    assertEquals(5, reply[0].toInt())
                    assertEquals(0, reply[1].toInt())
                    assertEquals(1, reply[3].toInt())
                    val relayPort = ((reply[8].toInt() and 0xff) shl 8) or
                        (reply[9].toInt() and 0xff)

                    DatagramSocket(null).use { clientUdp ->
                        clientUdp.bind(InetSocketAddress(loopback, 0))
                        clientUdp.soTimeout = 3000
                        val payload = "aura-local-udp".toByteArray(Charsets.UTF_8)
                        val targetPort = echoServer.localPort
                        val header = byteArrayOf(
                            0, 0, 0, 1, 127, 0, 0, 1,
                            (targetPort shr 8).toByte(), targetPort.toByte(),
                        )
                        val request = header + payload
                        clientUdp.send(DatagramPacket(request, request.size, loopback, relayPort))

                        val buffer = ByteArray(2048)
                        val response = DatagramPacket(buffer, buffer.size)
                        clientUdp.receive(response)
                        assertTrue(response.length >= 10 + payload.size)
                        assertEquals(0, response.data[0].toInt())
                        assertEquals(0, response.data[1].toInt())
                        assertEquals(0, response.data[2].toInt())
                        assertArrayEquals(
                            payload,
                            response.data.copyOfRange(10, response.length),
                        )
                    }
                }
                echoThread.join(1000)
            } finally {
                proxy.close()
            }
        }
    }

    private fun authenticate(output: java.io.OutputStream, input: java.io.InputStream) {
        output.write(byteArrayOf(5, 1, 2))
        output.flush()
        assertArrayEquals(byteArrayOf(5, 2), readExactly(input, 2))
        val username = testUsername.toByteArray(Charsets.UTF_8)
        val password = testPassword.toByteArray(Charsets.UTF_8)
        output.write(
            byteArrayOf(1, username.size.toByte()) + username +
                byteArrayOf(password.size.toByte()) + password,
        )
        output.flush()
        assertArrayEquals(byteArrayOf(1, 0), readExactly(input, 2))
    }

    private fun readExactly(input: java.io.InputStream, length: Int): ByteArray {
        val result = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val count = input.read(result, offset, length - offset)
            if (count < 0) throw AssertionError("EOF while reading SOCKS5 response")
            offset += count
        }
        return result
    }
}
