package com.ciberdefensa.aura

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.aura.cyberdefense.AuraNotificationService
import hev.htproxy.TProxyService
import java.io.DataInputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Android lifecycle and TUN owner for Aura's local-only VPN. */
class AuraVpnService : VpnService() {
    companion object {
        const val ACTION_STATE = "com.ciberdefensa.aura.VPN_STATE"
        private const val CHANNEL_ID = "aura_local_vpn"
        private const val NOTIFICATION_ID = 8816
        private const val PROXY_HOST = "127.0.0.1"
        private const val PROXY_PORT = 18763
        private const val PREFS = "aura_local_vpn"
        private const val PANIC_KEY = "panic_isolation_active"
        private val auditLock = Any()
        @Volatile private var activeService: AuraVpnService? = null
        private var dnsCount = 0L
        private var blockedCount = 0L
        private var lastDomain = ""
        private var lastAction = ""

        @JvmStatic fun protectSocket(fd: Int): Boolean = activeService?.protect(fd) ?: false
        @JvmStatic fun resolveHostForTunnel(host: String): String? =
            activeService?.resolveOnPhysicalNetwork(host)
        fun engagePanicIsolation(): Boolean = activeService?.enterPanicIsolation() ?: false
        fun resumeTunnel(): Boolean = activeService?.resumeTunnelForwarding() ?: false

        fun clearDnsAuditMemory() {
            synchronized(auditLock) {
                dnsCount = 0; blockedCount = 0; lastDomain = ""; lastAction = ""
            }
            activeService?.refreshNotification()
        }

        fun recordDnsAuditEvent(event: Map<String, Any>) {
            val action = event["action"] as? String ?: return
            val domain = event["requested_domain"] as? String ?: return
            synchronized(auditLock) {
                dnsCount++
                if (action == "BLOCKED" || action == "DGA_ALERT") blockedCount++
                lastDomain = domain
                lastAction = action
            }
            activeService?.refreshNotification()
        }
    }

    private val worker = Executors.newSingleThreadExecutor { Thread(it, "AuraVpnLifecycle").apply { isDaemon = true } }
    private val handler = Handler(Looper.getMainLooper())
    private val startRequested = AtomicBoolean(false)
    @Volatile private var physicalNetwork: Network? = null
    @Volatile private var tun: ParcelFileDescriptor? = null
    @Volatile private var proxy: AuraLocalSocks5Proxy? = null
    @Volatile private var running = false
    @Volatile private var panic = false
    @Volatile private var notificationQueued = false
    private var configPath: String? = null
    private var callbackRegistered = false

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val cm = getSystemService(ConnectivityManager::class.java)
            val caps = cm.getNetworkCapabilities(network) ?: return
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return
            val old = physicalNetwork
            if (old == null) physicalNetwork = network
            else if (old != network && running) worker.execute { restartOnNetwork(network) }
        }
        override fun onLost(network: Network) {
            if (physicalNetwork == network) {
                physicalNetwork = null
                if (running) {
                    reportState(false, "Se perdió la red física; VPN detenida por seguridad.")
                    worker.execute { stopResources() }
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeService = this
        panic = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(PANIC_KEY, false)
        try {
            getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(networkCallback)
            callbackRegistered = true
        } catch (error: Exception) {
            Log.w("AuraVPN", "Network callback unavailable.", error)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        startForeground(NOTIFICATION_ID, notification("Preparando VPN local…"))
        if (panic) {
            if (tun == null && startRequested.compareAndSet(false, true)) worker.execute { establishIsolation() }
        } else if (running) {
            reportState(true, "La VPN local ya está activa.")
        } else if (startRequested.compareAndSet(false, true)) {
            worker.execute { startTunnel() }
        }
        return Service.START_STICKY
    }

    override fun onRevoke() {
        reportState(false, "Android revocó el permiso VPN. La protección está inactiva.", true)
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopResources()
        if (callbackRegistered) {
            try { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback) }
            catch (_: Exception) { }
        }
        worker.shutdownNow()
        handler.removeCallbacksAndMessages(null)
        if (activeService === this) activeService = null
        stopService(Intent(this, AuraNotificationService::class.java))
        super.onDestroy()
    }

    private fun startTunnel() {
        var descriptor: ParcelFileDescriptor? = null
        try {
            val integrity = AuraAntiTampering.inspect(this)
            if (integrity["isSecure"] != true) {
                throw IOException("La comprobación de integridad de Aura no fue superada.")
            }
            val network = findPhysicalNetwork()
                ?: throw IOException("No se encontró una red física con Internet.")
            physicalNetwork = network
            descriptor = createBuilder(network).establish()
                ?: throw IOException("Android no pudo crear la interfaz TUN.")
            tun = descriptor
            startProxy()
            val path = writeConfig()
            configPath = path
            TProxyService.TProxySetBlockedIps(emptyArray())
            if (!TProxyService.TProxyStartService(path, descriptor.fd))
                throw IOException("El motor de transporte no pudo iniciar.")
            running = true
            verifyEgress()
            for (endpoint in AuraBlocklistService.knownEncryptedDnsEndpoints()) {
                if (!TProxyService.TProxyAddDynamicSniRule(endpoint))
                    throw IOException("El firewall no confirmó la regla DNS: " + endpoint)
            }
            startRequested.set(true)
            reportState(true, "VPN local activa: salida TCP/DNS comprobada.")
            refreshNotification()
        } catch (error: Exception) {
            Log.e("AuraVPN", "Local VPN startup failed.", error)
            stopResources()
            reportState(false, error.message ?: "No se pudo iniciar la VPN local.")
            stopSelf()
        }
    }

    private fun startProxy() {
        val next = AuraLocalSocks5Proxy(
            physicalNetwork = { physicalNetwork },
            protectTcp = { protect(it) },
            protectUdp = { protect(it) },
        )
        next.start()
        proxy = next
    }

    private fun writeConfig(): String {
        val file = java.io.File(filesDir, "aura-local-tunnel.yml")
        file.writeText(
            """
            tunnel:
              name: aura0
              mtu: 1500
              ipv4: 10.0.0.2
              ipv6: 'fd00::2'
              icmp: 'off'
            socks5:
              port: $PROXY_PORT
              address: $PROXY_HOST
              udp: 'tcp'
            misc:
              log-level: error
            mapdns:
              address: 10.0.0.3
              port: 53
              network: 100.64.0.0
              netmask: 255.192.0.0
              cache-size: 4096
            """.trimIndent() + "\n",
        )
        return file.absolutePath
    }

    private fun createBuilder(network: Network): Builder = Builder()
        .setSession("Aura Protección Local")
        .setMtu(1500)
        .setUnderlyingNetworks(arrayOf(network))
        .addAddress("10.0.0.2", 24)
        .addAddress("fd00::2", 64)
        .addRoute("0.0.0.0", 0)
        .addRoute("::", 0)
        .addDnsServer("10.0.0.3")

    private fun findPhysicalNetwork(): Network? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val candidates = cm.allNetworks.mapNotNull { network ->
            val caps = cm.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) null else network to caps
        }
        return candidates.firstOrNull {
            it.second.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }?.first ?: candidates.firstOrNull()?.first
    }

    private fun resolveOnPhysicalNetwork(host: String): String? {
        val normalized = host.trim().trimEnd('.')
        if (normalized.isBlank() || normalized.length > 253 ||
            normalized.any { it.isWhitespace() || it == '/' }) return null
        return try {
            physicalNetwork?.getAllByName(normalized)?.firstOrNull()?.hostAddress?.substringBefore('%')
        } catch (error: Exception) {
            Log.w("AuraVPN", "Physical DNS resolution failed.", error)
            null
        }
    }

    private fun verifyEgress() {
        val deadline = android.os.SystemClock.elapsedRealtime() + 15_000
        var last: Exception? = null
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            try {
                if (!TProxyService.TProxyIsRunning()) throw IOException("El motor TUN se detuvo.")
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(PROXY_HOST, PROXY_PORT), 1000)
                    socket.soTimeout = 5000
                    val input = DataInputStream(socket.getInputStream())
                    val output = socket.getOutputStream()
                    output.write(byteArrayOf(5, 1, 0)); output.flush()
                    val greeting = ByteArray(2); input.readFully(greeting)
                    if (greeting[0].toInt() != 5 || greeting[1].toInt() != 0)
                        throw IOException("Negociación SOCKS5 fallida.")
                    val host = "example.com".toByteArray(Charsets.US_ASCII)
                    output.write(byteArrayOf(5, 1, 0, 3, host.size.toByte()))
                    output.write(host); output.write(byteArrayOf(1, -69)); output.flush()
                    val response = ByteArray(4); input.readFully(response)
                    if (response[0].toInt() != 5 || response[1].toInt() != 0)
                        throw IOException("La salida TCP/DNS falló (SOCKS REP=" + response[1].toInt() + ").")
                }
                return
            } catch (error: Exception) {
                last = error
                Thread.sleep(250)
            }
        }
        throw IOException("No se verificó la salida TCP/DNS por la red física.", last)
    }

    @Synchronized
    private fun enterPanicIsolation(): Boolean {
        if (panic) return tun != null
        if (!running || tun == null) return false
        if (!getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(PANIC_KEY, true).commit())
            return false
        stopNative()
        running = false
        proxy?.stop(); proxy = null
        panic = true
        startRequested.set(false)
        reportState(false, "Aislamiento de emergencia activo; tráfico bloqueado.")
        refreshNotification()
        return true
    }

    @Synchronized
    private fun resumeTunnelForwarding(): Boolean {
        if (!panic) return running
        val descriptor = tun ?: return false
        val network = physicalNetwork ?: findPhysicalNetwork() ?: return false
        return try {
            physicalNetwork = network
            startProxy()
            val path = configPath ?: writeConfig().also { configPath = it }
            TProxyService.TProxySetBlockedIps(emptyArray())
            if (!TProxyService.TProxyStartService(path, descriptor.fd))
                throw IOException("No se pudo reanudar el motor TUN.")
            running = true
            verifyEgress()
            if (!getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(PANIC_KEY, false).commit())
                throw IOException("No se pudo guardar el estado de reanudación.")
            panic = false
            startRequested.set(true)
            reportState(true, "VPN local reanudada y salida verificada.")
            refreshNotification()
            true
        } catch (error: Exception) {
            Log.e("AuraVPN", "Tunnel resume failed.", error)
            stopNative(); proxy?.stop(); proxy = null; running = false
            false
        }
    }

    private fun establishIsolation() {
        try {
            val network = findPhysicalNetwork() ?: throw IOException("No hay red física.")
            physicalNetwork = network
            tun = createBuilder(network).establish()
                ?: throw IOException("No se pudo establecer el aislamiento.")
            reportState(false, "Aislamiento de emergencia activo; tráfico bloqueado.")
            refreshNotification()
        } catch (error: Exception) {
            startRequested.set(false)
            reportState(false, error.message ?: "Falló el aislamiento.")
        }
    }

    private fun restartOnNetwork(network: Network) {
        if (!running || network == physicalNetwork) return
        reportState(false, "Cambio de red detectado; reconectando VPN local.")
        stopNative(); proxy?.stop(); proxy = null
        try {
            physicalNetwork = network
            tun?.close()
            tun = createBuilder(network).establish()
                ?: throw IOException("No se pudo recrear la interfaz TUN.")
            startProxy()
            val path = writeConfig(); configPath = path
            TProxyService.TProxySetBlockedIps(emptyArray())
            if (!TProxyService.TProxyStartService(path, tun!!.fd))
                throw IOException("No se pudo reiniciar el motor.")
            verifyEgress()
            running = true
            reportState(true, "VPN local reconectada a la nueva red.")
        } catch (error: Exception) {
            Log.e("AuraVPN", "Network handover failed.", error)
            stopResources()
            reportState(false, "La VPN se detuvo porque no pudo recuperar la conexión.")
            stopSelf()
        }
    }

    private fun stopNative() {
        try {
            if (TProxyService.TProxyIsRunning()) TProxyService.TProxyStopService()
        } catch (error: Exception) {
            Log.w("AuraVPN", "Native tunnel stop failed.", error)
        }
    }

    @Synchronized
    private fun stopResources() {
        running = false
        stopNative()
        proxy?.stop(); proxy = null
        try { tun?.close() } catch (_: Exception) { }
        tun = null
        physicalNetwork = null
        startRequested.set(false)
    }

    private fun reportState(started: Boolean, message: String, revoked: Boolean = false) {
        sendBroadcast(
            Intent(ACTION_STATE).setPackage(packageName)
                .putExtra("started", started)
                .putExtra("message", message)
                .putExtra("revoked", revoked),
        )
    }

    private fun refreshNotification() {
        if (notificationQueued) return
        notificationQueued = true
        handler.postDelayed({
            notificationQueued = false
            if (running || panic) getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification(statusText()))
        }, 400)
    }

    private fun statusText(): String = synchronized(auditLock) {
        when {
            panic -> "Aislamiento activo · tráfico bloqueado"
            dnsCount == 0L -> "VPN local activa · esperando DNS"
            else -> "DNS $dnsCount · bloqueados $blockedCount · " +
                lastDomain.take(40) + " " + lastAction
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Aura Protección de Red", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    private fun notification(text: String = "Preparando protección local…"): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Aura · Protección de red")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
}
