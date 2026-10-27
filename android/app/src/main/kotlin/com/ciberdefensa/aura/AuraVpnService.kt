package com.ciberdefensa.aura

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.aura.cyberdefense.AuraNotificationService
import hev.htproxy.TProxyService
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.Inet6Address
import java.net.InetAddress
import java.net.URL
import java.util.Collections
import java.util.HashSet
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class AuraVpnService : VpnService() {
    companion object {
        const val ACTION_STATE = "com.ciberdefensa.aura.VPN_STATE"
        private const val DNS_PRIMARY = "1.1.1.1"
        private const val DNS_SECONDARY = "1.0.0.1"
        private const val BLOCKLIST_CACHE_PREFERENCES = "aura_blocklist_cache"
        private const val BLOCKLIST_CACHE_KEY = "blocked_ips"
        private const val THREAT_FEED_URL =
            "https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
        private const val NOTIFICATION_CHANNEL = "com.aura.mobile.defens.vpn"
        private const val NOTIFICATION_CHANNEL_NAME = "Aura Centinela"
        private const val NOTIFICATION_ID = 8816
        private const val NOTIFICATION_TEXT =
            "Protección agéntica local en tiempo real operando sin interrupciones."
        private const val VPN_STATE_PREFERENCES = "aura_vpn_state"
        private const val PANIC_ISOLATION_KEY = "panic_isolation_active"
        private const val MAX_BLOCKED_IPS = 8192
        private val dnsMetricsLock = Any()
        @Volatile private var activeService: AuraVpnService? = null
        private var auditedDnsRequests = 0L
        private var blockedDnsRequests = 0L
        private var lastDnsDomain = ""
        private var lastDnsAction = ""
        @JvmStatic
        fun protectSocket(socketFd: Int): Boolean =
            activeService?.protect(socketFd) ?: false

        @JvmStatic
        fun engagePanicIsolation(): Boolean =
            activeService?.enterPanicIsolation() ?: false

        @JvmStatic
        fun resumeTunnel(): Boolean = activeService?.resumeTunnelForwarding() ?: false

        @JvmStatic
        fun clearDnsAuditMemory() {
            synchronized(dnsMetricsLock) {
                auditedDnsRequests = 0
                blockedDnsRequests = 0
                lastDnsDomain = ""
                lastDnsAction = ""
                activeService?.scheduleNotificationUpdate()
            }
        }

        fun recordDnsAuditEvent(event: Map<String, Any>) {
            val action = event["action"] as? String ?: return
            val domain = event["requested_domain"] as? String ?: return
            val service: AuraVpnService?
            synchronized(dnsMetricsLock) {
                auditedDnsRequests++
                if (action == "BLOCKED" || action == "DGA_ALERT") blockedDnsRequests++
                lastDnsDomain = domain
                lastDnsAction = action
                service = activeService
            }
            service?.scheduleNotificationUpdate()
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val feedRefresh: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor()
    private val integrityMonitor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor()
    private val blockedIps: MutableSet<String> =
        Collections.synchronizedSet(HashSet())
    private val startRequested = AtomicBoolean(false)
    private val notificationHandler = Handler(Looper.getMainLooper())
    private var notificationUpdatePending = false
    private var vpnInterface: ParcelFileDescriptor? = null
    @Volatile private var localSocks5Proxy: LocalSocks5Proxy? = null
    private var integrityCheckScheduled = false
    private var feedRefreshScheduled = false
    @Volatile private var panicIsolationActive = false
    @Volatile private var tunnelStarted = false

    override fun onCreate() {
        super.onCreate()
        activeService = this
        AuraNetworkStream.setApplicationContext(applicationContext)
        panicIsolationActive = getSharedPreferences(
            VPN_STATE_PREFERENCES,
            MODE_PRIVATE,
        ).getBoolean(PANIC_ISOLATION_KEY, false)
    }

    override fun onStartCommand(
        intent: android.content.Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        ensureNotificationChannel()
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        if (!verifyIntegrityOrStop()) return Service.START_NOT_STICKY
        if (integrityMonitor.isShutdown) return Service.START_NOT_STICKY
        if (!integrityCheckScheduled) {
            integrityCheckScheduled = true
            integrityMonitor.scheduleWithFixedDelay(
                { verifyIntegrityOrStop() },
                30,
                30,
                TimeUnit.SECONDS,
            )
        }
        if (panicIsolationActive) {
            if (vpnInterface == null && startRequested.compareAndSet(false, true)) {
                worker.execute { establishPanicIsolationInterface() }
            }
            reportState(false, "Aislamiento de emergencia activo; forwarding detenido.")
            return Service.START_STICKY
        }
        if (tunnelStarted) {
            reportState(true, "El túnel VPN ya estaba activo.")
        } else if (startRequested.compareAndSet(false, true)) {
            worker.execute { startTunnel() }
        }
        return Service.START_STICKY
    }

    override fun onDestroy() {
        feedRefresh.shutdownNow()
        integrityMonitor.shutdownNow()
        worker.shutdownNow()
        if (tunnelStarted) {
            TProxyService.TProxyStopService()
            tunnelStarted = false
        }
        localSocks5Proxy?.close()
        localSocks5Proxy = null
        if (activeService === this) activeService = null
        notificationHandler.removeCallbacksAndMessages(null)
        vpnInterface?.close()
        vpnInterface = null
        stopService(android.content.Intent(this, AuraNotificationService::class.java))
        super.onDestroy()
    }

    override fun onRevoke() {
        val message =
            "[CRIT] TÚNEL REVOCADO POR ANDROID O POR EL OPERADOR — " +
                "LAS DEFENSAS ESTÁN INACTIVAS. " +
                "Remedio: revise el consentimiento VPN y reactive la defensa."
        reportState(false, message, revoked = true)
        AuraNotificationService.triggerPersistentAlert(
            this,
            "Túnel VPN revocado",
            message,
        )
        stopSelf()
        super.onRevoke()
    }

    private fun verifyIntegrityOrStop(): Boolean {
        val report = try {
            AuraAntiTampering.inspect(this)
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo comprobar la integridad del servicio.", exception)
            mapOf("isSecure" to false)
        }
        if (report["isSecure"] == true) return true

        Log.e("AuraVPN", "Deteniendo el túnel por fallo de integridad.")
        if (tunnelStarted) {
            TProxyService.TProxyStopService()
            tunnelStarted = false
        }
        reportState(false, "Túnel detenido por fallo de integridad.")
        stopSelf()
        return false
    }

    private fun startTunnel() {
        var established: ParcelFileDescriptor? = null
        try {
            // The threat feed is defense-in-depth, not a prerequisite for bringing up VPN.
            loadCachedBlocklist()
            try {
                replaceBlockedIps(downloadThreatFeed())
            } catch (feedError: Exception) {
                Log.w("AuraVPN", "Feed no disponible; se conserva la última lista válida.", feedError)
            }

            val localProxy = createLocalProxy()
            localProxy.start()
            localSocks5Proxy = localProxy

            established = createVpnBuilder().establish()
                ?: throw IOException("Android no estableció la interfaz VPN.")

            val configFile = File(filesDir, "aura-hev-socks5.yml")
            configFile.writeText(
                """
                tunnel:
                  name: aura0
                  mtu: 1500
                  ipv4: 10.0.0.2
                  ipv6: 'fd00::2'
                  icmp: 'off'
                socks5:
                  port: ${localProxy.port}
                  address: 127.0.0.1
                  udp: 'udp'
                misc:
                  log-level: error
                """.trimIndent(),
            )

            vpnInterface = established
            TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
            if (!TProxyService.TProxyStartService(configFile.absolutePath, established.fd)) {
                throw IOException("El motor tun2socks no pudo iniciar.")
            }
            tunnelStarted = true
            for (endpoint in AuraBlocklistService.knownEncryptedDnsEndpoints()) {
                if (!TProxyService.TProxyAddDynamicSniRule(endpoint)) {
                    throw IOException(
                        "El firewall SNI no confirmó el bloqueo de $endpoint.",
                    )
                }
            }
            scheduleFeedRefresh()
            reportState(true, "Túnel VPN iniciado con transporte local.")
            Log.i("AuraVPN", "Hev tun2socks conectado al proxy SOCKS5 local protegido.")
        } catch (e: Exception) {
            Log.e("AuraVPN", "No se pudo iniciar el escudo VPN.", e)
            if (tunnelStarted) TProxyService.TProxyStopService()
            tunnelStarted = false
            localSocks5Proxy?.close()
            localSocks5Proxy = null
            established?.close()
            vpnInterface = null
            startRequested.set(false)
            reportState(false, e.message ?: "No se pudo iniciar el túnel.")
            stopSelf()
        }
    }

    private fun createLocalProxy(): LocalSocks5Proxy =
        LocalSocks5Proxy(
            requestedPort = LocalSocks5Proxy.DEFAULT_PORT,
            protectTcpSocket = { socket -> protect(socket) },
            protectUdpSocket = { socket -> protect(socket) },
        )

    private fun loadCachedBlocklist() {
        val cached = getSharedPreferences(BLOCKLIST_CACHE_PREFERENCES, MODE_PRIVATE)
            .getStringSet(BLOCKLIST_CACHE_KEY, emptySet())
            .orEmpty()
            .filter(::isIpAddress)
            .toSet()
        if (cached.isNotEmpty()) replaceBlockedIps(cached, persist = false)
    }

    @Synchronized
    private fun enterPanicIsolation(): Boolean {
        if (panicIsolationActive) return vpnInterface != null
        if (!tunnelStarted || vpnInterface == null) return false

        return try {
            val persisted = getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(PANIC_ISOLATION_KEY, true)
                .commit()
            if (!persisted) return false
            if (!TProxyService.TProxyStopService()) {
                getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                    .edit()
                    .putBoolean(PANIC_ISOLATION_KEY, false)
                    .commit()
                return false
            }
            tunnelStarted = false
            localSocks5Proxy?.close()
            localSocks5Proxy = null
            panicIsolationActive = true
            startRequested.set(false)
            reportState(false, "Aislamiento de emergencia activo; forwarding detenido.")
            updateForegroundNotification()
            true
        } catch (exception: Exception) {
            getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(PANIC_ISOLATION_KEY, false)
                .commit()
            panicIsolationActive = false
            Log.e("AuraVPN", "No se pudo detener el forwarding del túnel.", exception)
            false
        }
    }

    @Synchronized
    private fun resumeTunnelForwarding(): Boolean {
        if (!panicIsolationActive) return tunnelStarted
        val tun = vpnInterface ?: return false
        val configFile = File(filesDir, "aura-hev-socks5.yml")
        if (!configFile.isFile) return false

        return try {
            val localProxy = createLocalProxy()
            localProxy.start()
            localSocks5Proxy = localProxy
            TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
            if (!TProxyService.TProxyStartService(configFile.absolutePath, tun.fd)) {
                return false
            }
            val cleared = getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                .edit()
                .putBoolean(PANIC_ISOLATION_KEY, false)
                .commit()
            if (!cleared) {
                TProxyService.TProxyStopService()
                return false
            }
            panicIsolationActive = false
            tunnelStarted = true
            startRequested.set(true)
            scheduleFeedRefresh()
            reportState(true, "Forwarding del túnel VPN restablecido.")
            updateForegroundNotification()
            true
        } catch (exception: Exception) {
            if (TProxyService.TProxyIsRunning()) {
                TProxyService.TProxyStopService()
            }
            localSocks5Proxy?.close()
            localSocks5Proxy = null
            Log.e("AuraVPN", "No se pudo reanudar el forwarding del túnel.", exception)
            false
        }
    }

    private fun establishPanicIsolationInterface() {
        var established: ParcelFileDescriptor? = null
        try {
            established = createVpnBuilder().establish()
                ?: throw IOException("Android no restableció la interfaz VPN aislada.")
            vpnInterface = established
            reportState(false, "Aislamiento de emergencia activo; tráfico en descarte.")
            updateForegroundNotification()
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo restablecer la interfaz aislada.", exception)
            established?.close()
            vpnInterface = null
            startRequested.set(false)
            reportState(false, exception.message ?: "Falló el aislamiento de red.")
        }
    }

    private fun createVpnBuilder(): Builder = Builder()
        .setSession("Aura Mobile Defens")
        .setMtu(1500)
        .addAddress("10.0.0.2", 24)
        .addAddress("fd00::2", 64)
        // Full routes capture TCP and UDP on both IP families for tunnel inspection.
        .addRoute("0.0.0.0", 0)
        .addRoute("::", 0)
        // DNS packets are routed through TUN; protected relay sockets bypass it.
        .addDnsServer(DNS_PRIMARY)
        .addDnsServer(DNS_SECONDARY)

    private fun downloadThreatFeed(): Set<String> {
        val connection = URL(THREAT_FEED_URL).openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 15000
        connection.useCaches = false

        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw IOException("El feed de amenazas devolvió HTTP ${connection.responseCode}.")
            }
            return connection.inputStream.bufferedReader().useLines { lines ->
                lines.asSequence()
                    .map { it.substringBefore('#').trim() }
                    .filter(::isIpAddress)
                    .take(MAX_BLOCKED_IPS)
                    .toCollection(HashSet())
            }.also {
                if (it.isEmpty()) throw IOException("El feed no contiene direcciones IP válidas.")
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun isIpv4Address(value: String): Boolean {
        val parts = value.split('.')
        if (parts.size != 4) return false
        return parts.all { part ->
            val octet = part.toIntOrNull()
            octet != null && octet in 0..255 && octet.toString() == part
        }
    }

    private fun isIpAddress(value: String): Boolean {
        if (isIpv4Address(value)) return true
        if (!value.contains(':')) return false
        return try {
            InetAddress.getByName(value) is Inet6Address
        } catch (_: IOException) {
            false
        }
    }

    private fun replaceBlockedIps(updated: Set<String>, persist: Boolean = true) {
        val validated = updated.filter(::isIpAddress).take(MAX_BLOCKED_IPS).toSet()
        synchronized(blockedIps) {
            blockedIps.clear()
            blockedIps.addAll(validated)
        }
        if (persist) {
            getSharedPreferences(BLOCKLIST_CACHE_PREFERENCES, MODE_PRIVATE)
                .edit()
                .putStringSet(BLOCKLIST_CACHE_KEY, validated)
                .apply()
        }
    }

    private fun blockedIpSnapshot(): Array<String> = synchronized(blockedIps) {
        blockedIps.toTypedArray()
    }

    private fun scheduleFeedRefresh() {
        if (feedRefreshScheduled) return
        feedRefreshScheduled = true
        feedRefresh.scheduleWithFixedDelay({
            try {
                val updated = downloadThreatFeed()
                replaceBlockedIps(updated)
                TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
            } catch (e: Exception) {
                Log.w("AuraVPN", "No se pudo actualizar el feed; se conserva la lista anterior.", e)
            }
        }, 1, 60, TimeUnit.MINUTES)
    }

    private fun reportState(
        started: Boolean,
        message: String,
        revoked: Boolean = false,
    ) {
        sendBroadcast(
            android.content.Intent(ACTION_STATE)
                .setPackage(packageName)
                .putExtra("started", started)
                .putExtra("message", message)
                .putExtra("revoked", revoked),
        )
    }

    private fun scheduleNotificationUpdate() {
        if (notificationUpdatePending) return
        notificationUpdatePending = true
        notificationHandler.postDelayed({
            notificationUpdatePending = false
            if (tunnelStarted) {
                getSystemService(NotificationManager::class.java)
                    .notify(NOTIFICATION_ID, createNotification(currentDnsSummary()))
            }
        }, 500)
    }

    private fun currentDnsSummary(): String = synchronized(dnsMetricsLock) {
        if (panicIsolationActive) {
            "AISLAMIENTO ACTIVO · forwarding detenido"
        } else if (auditedDnsRequests == 0L) {
            "Túnel activo · esperando eventos DNS"
        } else {
            val domain = lastDnsDomain.take(52)
            "DNS $auditedDnsRequests · bloqueados $blockedDnsRequests · " +
                "$domain $lastDnsAction"
        }
    }

    private fun updateForegroundNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, createNotification(currentDnsSummary()))
    }

    private fun createNotification(
        contentText: String = NOTIFICATION_TEXT,
    ): Notification {
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setContentTitle("🛡️ Aura Centinela Activo")
            .setContentText(NOTIFICATION_TEXT)
            .setSubText(contentText.takeIf { it != NOTIFICATION_TEXT })
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }
}
