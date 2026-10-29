package com.ciberdefensa.aura

import android.net.Network
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Private loopback SOCKS5 egress for the TUN engine.
 *
 * TCP uses SOCKS5 CONNECT. UDP uses Hev's documented FWD_UDP framing
 * (2-byte payload length, 1-byte header length, SOCKS address, payload).
 * Every outbound socket is bound to Android's physical Network and protected
 * from the VPN interface to prevent recursive routing.
 */
internal class AuraLocalSocks5Proxy(
    private val physicalNetwork: () -> Network?,
    private val protectTcp: (Socket) -> Boolean,
    private val protectUdp: (DatagramSocket) -> Boolean,
    private val port: Int = 18763,
) {
    private val running = AtomicBoolean(false)
    private val workers: ExecutorService = Executors.newCachedThreadPool { task ->
        Thread(task, "AuraLocalProxyWorker").apply { isDaemon = true }
    }
    private val clients = ConcurrentHashMap.newKeySet<Socket>()
    @Volatile private var listener: ServerSocket? = null
    private var acceptThread: Thread? = null

    @Synchronized
    fun start() {
        if (running.get()) return
        val server = ServerSocket()
        server.reuseAddress = false
        server.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 64)
        listener = server
        running.set(true)
        acceptThread = Thread({ acceptLoop(server) }, "AuraLocalProxyAccept").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    fun stop() {
        if (!running.getAndSet(false)) return
        try { listener?.close() } catch (_: Exception) { }
        listener = null
        clients.toList().forEach { try { it.close() } catch (_: Exception) { } }
        clients.clear()
        workers.shutdownNow()
        acceptThread = null
    }

    private fun acceptLoop(server: ServerSocket) {
        while (running.get()) {
            try {
                val client = server.accept()
                client.tcpNoDelay = true
                clients.add(client)
                workers.execute {
                    try { handleClient(client) }
                    catch (_: Exception) { }
                    finally {
                        clients.remove(client)
                        try { client.close() } catch (_: Exception) { }
                    }
                }
            } catch (error: IOException) {
                if (running.get()) android.util.Log.e("AuraLocalProxy", "Accept failed", error)
                break
            }
        }
    }

    private fun handleClient(client: Socket) {
        client.soTimeout = 15_000
        val input = DataInputStream(BufferedInputStream(client.getInputStream()))
        val output = DataOutputStream(BufferedOutputStream(client.getOutputStream()))

        if (input.readUnsignedByte() != 5) throw IOException("SOCKS version mismatch")
        val methodCount = input.readUnsignedByte()
        val methods = ByteArray(methodCount)
        input.readFully(methods)
        if (methods.none { (it.toInt() and 0xff) == 0 }) {
            output.write(byteArrayOf(5, 0xff.toByte()))
            output.flush()
            throw IOException("No supported SOCKS authentication method")
        }
        output.write(byteArrayOf(5, 0))
        output.flush()

        val version = input.readUnsignedByte()
        val command = input.readUnsignedByte()
        val reserved = input.readUnsignedByte()
        val addressType = input.readUnsignedByte()
        if (version != 5 || reserved != 0) throw IOException("Invalid SOCKS request")
        val destination = readAddress(input, addressType)
        val port = input.readUnsignedShort()
        when (command) {
            1 -> connectTcp(destination, port, client, input, output)
            5 -> relayUdp(client, input, output)
            else -> {
                writeReply(output, 7)
                throw IOException("Unsupported SOCKS command $command")
            }
        }
    }

    private fun connectTcp(
        host: String,
        destinationPort: Int,
        client: Socket,
        input: DataInputStream,
        output: DataOutputStream,
    ) {
        var outbound: Socket? = null
        try {
            val network = physicalNetwork() ?: throw IOException("No physical network")
            val address = resolve(network, host)
            outbound = Socket()
            if (!protectTcp(outbound)) throw IOException("Could not protect outbound TCP socket")
            network.bindSocket(outbound)
            outbound.tcpNoDelay = true
            outbound.connect(InetSocketAddress(address, destinationPort), 12_000)
            client.soTimeout = 0
            writeReply(output, 0)
            val remote = outbound
            val up = workers.submit { copyStream(input, remote.getOutputStream(), remote, true) }
            val down = workers.submit { copyStream(remote.getInputStream(), output, remote, false) }
            try { up.get() } finally {
                try { remote.shutdownOutput() } catch (_: Exception) { }
                try { client.shutdownInput() } catch (_: Exception) { }
                down.cancel(true)
            }
        } catch (error: Exception) {
            try { writeReply(output, 1) } catch (_: Exception) { }
            throw error
        } finally {
            try { outbound?.close() } catch (_: Exception) { }
        }
    }

    private fun copyStream(
        source: java.io.InputStream,
        destination: java.io.OutputStream,
        socket: Socket,
        outboundDirection: Boolean,
    ) {
        val buffer = ByteArray(32 * 1024)
        try {
            while (true) {
                val count = source.read(buffer)
                if (count < 0) break
                destination.write(buffer, 0, count)
                destination.flush()
            }
        } catch (_: Exception) {
        } finally {
            if (outboundDirection) {
                try { socket.shutdownOutput() } catch (_: Exception) { }
            } else {
                try { socket.shutdownInput() } catch (_: Exception) { }
            }
        }
    }

    private fun relayUdp(
        client: Socket,
        input: DataInputStream,
        output: DataOutputStream,
    ) {
        val network = physicalNetwork() ?: throw IOException("No physical network")
        val datagram = DatagramSocket(null)
        try {
            if (!protectUdp(datagram)) throw IOException("Could not protect outbound UDP socket")
            network.bindSocket(datagram)
            datagram.bind(InetSocketAddress(0))
            client.soTimeout = 0
            writeReply(output, 0)
            val writeLock = Any()
            val receiver = workers.submit {
                val buffer = ByteArray(65_507)
                while (running.get() && !datagram.isClosed) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        datagram.receive(packet)
                        val address = encodeAddress(packet.address, packet.port)
                        synchronized(writeLock) {
                            output.writeShort(packet.length)
                            output.writeByte(3 + address.size)
                            output.write(address)
                            output.write(buffer, packet.offset, packet.length)
                            output.flush()
                        }
                    } catch (error: Exception) {
                        if (!datagram.isClosed) android.util.Log.w("AuraLocalProxy", "UDP receive ended", error)
                        break
                    }
                }
            }

            while (running.get() && !client.isClosed) {
                val length = try { input.readUnsignedShort() } catch (_: EOFException) { break }
                val headerLength = input.readUnsignedByte()
                if (length !in 1..65_507 || headerLength !in 8..260) {
                    throw IOException("Invalid UDP frame")
                }
                val encodedAddress = ByteArray(headerLength - 3)
                input.readFully(encodedAddress)
                val payload = ByteArray(length)
                input.readFully(payload)
                val target = decodeAddress(encodedAddress)
                val resolved = resolve(network, target.first)
                val packet = DatagramPacket(payload, payload.size, resolved, target.second)
                datagram.send(packet)
            }
            receiver.cancel(true)
        } finally {
            datagram.close()
        }
    }

    private fun readAddress(input: DataInputStream, type: Int): String = when (type) {
        1 -> InetAddress.getByAddress(ByteArray(4).also(input::readFully)).hostAddress
        4 -> InetAddress.getByAddress(ByteArray(16).also(input::readFully)).hostAddress
        3 -> {
            val length = input.readUnsignedByte()
            if (length !in 1..253) throw IOException("Invalid domain length")
            ByteArray(length).also(input::readFully).toString(Charsets.US_ASCII)
        }
        else -> throw IOException("Unsupported address type $type")
    }

    private fun decodeAddress(bytes: ByteArray): Pair<String, Int> {
        val input = DataInputStream(bytes.inputStream())
        val type = input.readUnsignedByte()
        val host = readAddress(input, type)
        val port = input.readUnsignedShort()
        if (input.available() != 0) throw IOException("Trailing SOCKS address bytes")
        return host to port
    }

    private fun encodeAddress(address: InetAddress, port: Int): ByteArray {
        val raw = address.address
        val type = when (address) {
            is Inet4Address -> 1
            is Inet6Address -> 4
            else -> throw IOException("Unsupported UDP address family")
        }
        return byteArrayOf(type.toByte()) + raw + byteArrayOf((port shr 8).toByte(), port.toByte())
    }

    private fun resolve(network: Network, host: String): InetAddress {
        return try {
            InetAddress.getByName(host).takeIf { host == it.hostAddress || host.contains(':') || host.matches(Regex("^(?:\\d{1,3}\\.){3}\\d{1,3}$")) }
                ?: network.getAllByName(host).firstOrNull()
                ?: throw IOException("DNS resolution returned no addresses for $host")
        } catch (error: Exception) {
            throw IOException("Could not resolve $host on the physical network", error)
        }
    }

    private fun writeReply(output: DataOutputStream, result: Int) {
        output.write(byteArrayOf(5, result.toByte(), 0, 1, 0, 0, 0, 0, 0, 0))
        output.flush()
    }
}
