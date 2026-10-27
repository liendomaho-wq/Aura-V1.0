package com.ciberdefensa.aura

import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.util.HashSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Device-local SOCKS5 transport for hev-socks5-tunnel.
 *
 * Only binds its control listener to IPv4 loopback. Outbound TCP/UDP sockets must
 * be protected by VpnService before connect/send so they do not re-enter the TUN.
 * This deliberately accepts numeric destinations only: DNS is supplied by the VPN
 * builder and traverses the tunnel as ordinary UDP, avoiding resolver recursion.
 */
internal class LocalSocks5Proxy(
    private val requestedPort: Int = DEFAULT_PORT,
    private val protectTcpSocket: (Socket) -> Boolean,
    private val protectUdpSocket: (DatagramSocket) -> Boolean,
) : Closeable {
    companion object {
        const val DEFAULT_PORT = 10808
        private const val SOCKS_VERSION = 5
        private const val CONNECT = 1
        private const val UDP_ASSOCIATE = 3
        private const val ATYP_IPV4 = 1
        private const val ATYP_DOMAIN = 3
        private const val ATYP_IPV6 = 4
        private const val MAX_UDP_PAYLOAD = 65507
    }

    @Volatile private var listener: ServerSocket? = null
    @Volatile private var running = false
    private val workers: ExecutorService = Executors.newCachedThreadPool()
    private val activeResources = ConcurrentHashMap.newKeySet<Closeable>()
    private val closed = AtomicBoolean(false)

    val port: Int
        get() = listener?.localPort ?: requestedPort

    @Synchronized
    fun start(): Int {
        check(!closed.get()) { "El proxy local ya fue cerrado." }
        if (running) return port
        val server = ServerSocket()
        server.reuseAddress = false
        server.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), requestedPort))
        listener = server
        running = true
        thread(name = "aura-local-socks5-accept", isDaemon = true) {
            acceptLoop(server)
        }
        return server.localPort
    }

    private fun acceptLoop(server: ServerSocket) {
        while (running && !server.isClosed) {
            try {
                val client = server.accept()
                activeResources.add(client)
                workers.execute { handleClient(client) }
            } catch (_: SocketException) {
                if (running) close()
            } catch (_: IOException) {
                if (running) close()
            }
        }
    }

    private fun handleClient(client: Socket) {
        client.use { socket ->
            try {
                socket.soTimeout = 15_000
                val input = socket.getInputStream()
                val output = socket.getOutputStream()
                if (readByte(input) != SOCKS_VERSION) return
                val methodsCount = readByte(input)
                var noAuthOffered = false
                repeat(methodsCount) {
                    if (readByte(input) == 0) noAuthOffered = true
                }
                output.write(byteArrayOf(5, if (noAuthOffered) 0.toByte() else 0xff.toByte()))
                output.flush()
                if (!noAuthOffered) return

                if (readByte(input) != SOCKS_VERSION) return
                val command = readByte(input)
                readByte(input) // RSV
                val destination = readAddress(input)
                val destinationPort = (readByte(input) shl 8) or readByte(input)

                when (command) {
                    CONNECT -> handleConnect(socket, destination, destinationPort)
                    UDP_ASSOCIATE -> handleUdpAssociate(socket)
                    else -> writeReply(socket, 7)
                }
            } catch (_: Exception) {
                // Invalid or disconnected clients are isolated to this session.
            } finally {
                activeResources.remove(socket)
            }
        }
    }

    private fun handleConnect(client: Socket, address: InetAddress?, port: Int) {
        if (address == null || port !in 1..65535) {
            writeReply(client, 8)
            return
        }
        val upstream = Socket()
        try {
            if (!protectTcpSocket(upstream)) throw IOException("VpnService.protect(Socket) falló.")
            upstream.connect(InetSocketAddress(address, port), 10_000)
            upstream.soTimeout = 0
            client.soTimeout = 0
            writeReply(client, 0)
            relay(client, upstream)
        } catch (_: Exception) {
            writeReply(client, 5)
            try { upstream.close() } catch (_: IOException) { }
        }
    }

    private fun relay(client: Socket, upstream: Socket) {
        val done = AtomicBoolean(false)
        val latch = java.util.concurrent.CountDownLatch(2)
        fun pump(from: Socket, to: Socket) {
            try {
                from.getInputStream().copyTo(to.getOutputStream())
            } catch (_: IOException) {
                // Closing the opposite side below wakes the other pump.
            } finally {
                if (done.compareAndSet(false, true)) {
                    try { client.close() } catch (_: IOException) { }
                    try { upstream.close() } catch (_: IOException) { }
                }
                latch.countDown()
            }
        }
        workers.execute { pump(client, upstream) }
        workers.execute { pump(upstream, client) }
        try { latch.await() } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    private fun handleUdpAssociate(control: Socket) {
        val relay = DatagramSocket(null)
        try {
            relay.reuseAddress = false
            relay.bind(InetSocketAddress(0))
            activeResources.add(relay)
            if (!protectUdpSocket(relay)) throw IOException("VpnService.protect(DatagramSocket) falló.")
            relay.soTimeout = 120_000
            val remoteUdpEndpoints = HashSet<InetSocketAddress>()
            val advertised = InetAddress.getByName("127.0.0.1").address
            val response = byteArrayOf(5, 0, 0, ATYP_IPV4.toByte()) +
                advertised + byteArrayOf((relay.localPort shr 8).toByte(), relay.localPort.toByte())
            control.getOutputStream().write(response)
            control.getOutputStream().flush()
            control.soTimeout = 0

            val buffer = ByteArray(MAX_UDP_PAYLOAD)
            var clientAddress: InetAddress? = null
            var clientPort = -1
            while (running && !control.isClosed && !relay.isClosed) {
                val packet = DatagramPacket(buffer, buffer.size)
                try {
                    relay.receive(packet)
                } catch (_: SocketTimeoutException) {
                    break
                }
                val packetEndpoint = InetSocketAddress(packet.address, packet.port)
                val fromClient = packet.address.isLoopbackAddress &&
                    (clientAddress == null ||
                        (packet.address == clientAddress && packet.port == clientPort))
                if (fromClient) {
                    clientAddress = packet.address
                    clientPort = packet.port
                    val decoded = decodeUdp(packet.data, packet.length) ?: continue
                    val remoteEndpoint = InetSocketAddress(decoded.address, decoded.port)
                    if (remoteUdpEndpoints.size >= 1024) remoteUdpEndpoints.clear()
                    remoteUdpEndpoints.add(remoteEndpoint)
                    val outgoing = DatagramPacket(
                        decoded.payload, decoded.payload.size,
                        decoded.address, decoded.port,
                    )
                    relay.send(outgoing)
                } else {
                    if (packetEndpoint !in remoteUdpEndpoints) continue
                    val target = clientAddress ?: continue
                    if (clientPort < 1) continue
                    val encoded = encodeUdp(packet.address, packet.port, packet.data, packet.length)
                    relay.send(DatagramPacket(encoded, encoded.size, target, clientPort))
                }
            }
        } catch (_: Exception) {
            // A failed UDP association must not terminate the VPN service.
        } finally {
            relay.close()
            activeResources.remove(relay)
        }
    }

    private data class UdpDestination(
        val address: InetAddress,
        val port: Int,
        val payload: ByteArray,
    )

    private fun decodeUdp(data: ByteArray, length: Int): UdpDestination? {
        if (length < 10 || data[0] != 0.toByte() || data[1] != 0.toByte() ||
            data[2] != 0.toByte()) return null // RSV + FRAG (fragmentation unsupported)
        var offset = 4
        val address: InetAddress = when (data[3].toInt() and 0xff) {
            ATYP_IPV4 -> {
                if (length < offset + 4 + 2) return null
                val bytes = data.copyOfRange(offset, offset + 4)
                offset += 4
                InetAddress.getByAddress(bytes)
            }
            ATYP_IPV6 -> {
                if (length < offset + 16 + 2) return null
                val bytes = data.copyOfRange(offset, offset + 16)
                offset += 16
                InetAddress.getByAddress(bytes)
            }
            ATYP_DOMAIN -> return null // Never trigger recursive system DNS from the relay.
            else -> return null
        }
        val port = ((data[offset].toInt() and 0xff) shl 8) or (data[offset + 1].toInt() and 0xff)
        if (port == 0) return null
        offset += 2
        return UdpDestination(address, port, data.copyOfRange(offset, length))
    }

    private fun encodeUdp(address: InetAddress, port: Int, payload: ByteArray, length: Int): ByteArray {
        val addressBytes = address.address
        val atyp = if (addressBytes.size == 16) ATYP_IPV6 else ATYP_IPV4
        val result = ByteArray(4 + addressBytes.size + 2 + length)
        result[3] = atyp.toByte()
        System.arraycopy(addressBytes, 0, result, 4, addressBytes.size)
        val offset = 4 + addressBytes.size
        result[offset] = (port shr 8).toByte()
        result[offset + 1] = port.toByte()
        System.arraycopy(payload, 0, result, offset + 2, length)
        return result
    }

    private fun readAddress(input: java.io.InputStream): InetAddress? {
        return when (readByte(input)) {
            ATYP_IPV4 -> InetAddress.getByAddress(ByteArray(4) { readByte(input).toByte() })
            ATYP_IPV6 -> InetAddress.getByAddress(ByteArray(16) { readByte(input).toByte() })
            ATYP_DOMAIN -> {
                val length = readByte(input)
                repeat(length) { readByte(input) }
                null // Domain resolution here could recurse through the VPN DNS route.
            }
            else -> null
        }
    }

    private fun writeReply(socket: Socket, status: Int) {
        try {
            socket.getOutputStream().write(
                byteArrayOf(5, status.toByte(), 0, ATYP_IPV4.toByte(), 0, 0, 0, 0, 0, 0),
            )
            socket.getOutputStream().flush()
        } catch (_: IOException) { }
    }

    private fun readByte(input: java.io.InputStream): Int {
        val value = input.read()
        if (value < 0) throw EOFException("Conexión SOCKS5 cerrada.")
        return value
    }

    @Synchronized
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        running = false
        try { listener?.close() } catch (_: IOException) { }
        listener = null
        activeResources.toList().forEach { resource ->
            try { resource.close() } catch (_: IOException) { }
        }
        activeResources.clear()
        workers.shutdownNow()
    }
}
