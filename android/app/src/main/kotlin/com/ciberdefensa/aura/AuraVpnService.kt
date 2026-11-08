package com.ciberdefensa.aura

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
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
import java.net.InetSocketAddress
import java.net.Socket
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
        const val EXTRA_START_REQUEST_ID = "com.ciberdefensa.aura.VPN_START_REQUEST_ID"
        private const val LOCAL_SOCKS5_HOST = "127.0.0.1"
        private const val LOCAL_SOCKS5_PORT = 18763
        private const val THREAT_FEED_URL =
            "https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
        private const val NOTIFICATION_CHANNEL = "com.aura.mobile.defens.vpn"
        private const val NOTIFICATION_CHANNEL_NAME = "Aura Centinela"
        private const val NOTIFICATION_ID = 8816
        private const val NOTIFICATION_TEXT =
            "Iniciando motor de red local; verificando interfaz y forwarding."
        private const val VPN_STATE_PREFERENCES = "aura_vpn_state"
        private const val PANIC_ISOLATION_KEY = "panic_isolation_active"
        private const val MAX_BLOCKED_IPS = 8192
        private const val MAX_THREAT_FEED_BYTES = 4 * 1024 * 1024
        private val dnsMetricsLock = Any()
        @Volatile private var activeService: AuraVpnService? = null
        @Volatile private var lastShutdownConfirmed = true
        private var auditedDnsRequests = 0L
        private var blockedDnsRequests = 0L
        /**
         * Returns the currently loaded IP block rules, not a history of packets blocked.
         * An empty result means no active VPN service currently exposes its rule set.
         */
        @JvmStatic
        fun activeBlockedIpRules(): List<String> =
            activeService?.blockedIpSnapshot()?.sorted()?.take(512) ?: emptyList()

        @JvmStatic
        fun protectSocket(socketFd: Int): Boolean =
            activeService?.protectAndBindSocket(socketFd) ?: false

        @JvmStatic
        fun resolveHostForTunnel(hostname: String): String? =
            activeService?.resolveHostOnUnderlyingNetwork(hostname)

        @JvmStatic
        fun engagePanicIsolation(): Boolean =
            activeService?.enterPanicIsolation() ?: false

        @JvmStatic
        fun resumeTunnel(): Boolean = activeService?.resumeTunnelForwarding() ?: false

        @JvmStatic
        fun shieldStatus(): Map<String, Boolean> {
            val service = activeService ?: return mapOf(
                "service_active" to false,
                "vpn_interface_active" to false,
                "forwarding_active" to false,
                "isolation_active" to false,
                // A failed native stop or TUN close is not proof of shutdown.
                "status_verified" to lastShutdownConfirmed,
            )
            val interfaceActive = service.vpnInterface?.fileDescriptor?.valid() == true
            val nativeRunning = try {
                TProxyService.TProxyIsRunning()
            } catch (error: Exception) {
                Log.e("AuraVPN", "No se pudo verificar el motor VPN nativo.", error)
                null
            } catch (error: LinkageError) {
                Log.e("AuraVPN", "El motor VPN nativo no está disponible.", error)
                null
            }
            if (service.tunnelStarted && (!interfaceActive || nativeRunning != true)) {
                service.scheduleNotificationUpdate()
            }
            return mapOf(
                "service_active" to true,
                "vpn_interface_active" to interfaceActive,
                "forwarding_active" to (service.tunnelStarted && interfaceActive &&
                    nativeRunning == true && !service.panicIsolationActive &&
                    !service.serviceShuttingDown),
                "isolation_active" to service.panicIsolationActive,
                "status_verified" to (nativeRunning != null && !service.serviceShuttingDown),
            )
        }

        @JvmStatic
        fun clearDnsAuditMemory() {
            synchronized(dnsMetricsLock) {
                auditedDnsRequests = 0
                blockedDnsRequests = 0
                activeService?.scheduleNotificationUpdate()
            }
        }

        fun recordDnsAuditEvent(event: Map<String, Any>) {
            val action = event["action"] as? String ?: return
            if (event["requested_domain"] !is String) return
            val service: AuraVpnService?
            synchronized(dnsMetricsLock) {
                auditedDnsRequests++
                if (action == "BLOCKED" || action == "DGA_ALERT") blockedDnsRequests++
                service = activeService
            }
            service?.scheduleNotificationUpdate()
        }
    }

    @Volatile private var underlyingNetwork: Network? = null
    @Volatile private var networkCallbackRegistered = false
    @Volatile private var serviceShuttingDown = false
    private val underlyingNetworkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            enqueueUnderlyingNetworkRefresh()
        }

        override fun onLost(network: Network) {
            enqueueUnderlyingNetworkRefresh(excludedNetwork = network)
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            enqueueUnderlyingNetworkRefresh()
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
    private val lifecycleGate = VpnLifecycleGate()
    private val notificationHandler = Handler(Looper.getMainLooper())
    private var notificationUpdatePending = false
    @Volatile private var vpnInterface: ParcelFileDescriptor? = null
    private var integrityCheckScheduled = false
    private var feedRefreshScheduled = false
    @Volatile private var panicIsolationActive = false
    @Volatile private var tunnelStarted = false

    override fun onCreate() {
        super.onCreate()
        activeService = this
        AuraNetworkStream.setApplicationContext(applicationContext)
        registerUnderlyingNetworkCallback()
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
        val requestId = intent?.getStringExtra(EXTRA_START_REQUEST_ID)
        ensureNotificationChannel()
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        if (!verifyIntegrityOrStop()) {
            if (requestId != null) {
                reportState(false, "La comprobación de integridad falló.", requestId = requestId)
            }
            return Service.START_NOT_STICKY
        }
        if (integrityMonitor.isShutdown) {
            if (requestId != null) {
                reportState(false, "El servicio VPN está cerrándose.", requestId = requestId)
            }
            return Service.START_NOT_STICKY
        }
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
            reportState(
                false,
                "Aislamiento de emergencia activo; forwarding detenido.",
                requestId = requestId,
            )
            return Service.START_STICKY
        }
        if (tunnelStarted) {
            if (shieldStatus()["forwarding_active"] == true) {
                reportState(true, "El túnel VPN ya estaba activo.", requestId = requestId)
            } else {
                reportState(
                    false,
                    "El estado del motor VPN no está confirmado. Revise la protección.",
                    requestId = requestId,
                )
            }
        } else if (startRequested.compareAndSet(false, true)) {
            try {
                worker.execute { startTunnel(requestId) }
            } catch (error: java.util.concurrent.RejectedExecutionException) {
                startRequested.set(false)
                reportState(false, "El servicio VPN está cerrándose.", requestId = requestId)
            }
        } else if (requestId != null) {
            // A previous start (possibly an Android service restart) is still
            // running. Do not attribute that operation's broadcast to this one.
            reportState(false, "Ya hay un arranque VPN en curso.", requestId = requestId)
        }
        return Service.START_STICKY
    }

    override fun onDestroy() {
        serviceShuttingDown = true
        lifecycleGate.beginClosing()
        unregisterUnderlyingNetworkCallback()
        feedRefresh.shutdownNow()
        integrityMonitor.shutdownNow()
        worker.shutdownNow()
        // Serialize destruction with TUN establishment and native lifecycle
        // calls; stale work cannot start or stop a later service's worker.
        val shutdownConfirmed = lifecycleGate.close {
            val nativeStopped = stopNativeWorkerUnchecked()
            tunnelStarted = false
            val interfaceClosed = try {
                vpnInterface?.close()
                true
            } catch (exception: Exception) {
                Log.e("AuraVPN", "No se pudo cerrar la interfaz VPN.", exception)
                false
            }
            vpnInterface = null
            nativeStopped && interfaceClosed
        }
        if (activeService === this) {
            lastShutdownConfirmed = shutdownConfirmed
            activeService = null
        }
        notificationHandler.removeCallbacksAndMessages(null)
        underlyingNetwork = null
        stopService(android.content.Intent(this, AuraNotificationService::class.java))
        super.onDestroy()
    }

    override fun onRevoke() {
        // Revocation can arrive while a worker is still starting. Refuse new
        // native work immediately; teardown is only confirmed in onDestroy.
        serviceShuttingDown = true
        lifecycleGate.beginClosing()
        tunnelStarted = false
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

    /**
     * Request native shutdown even if `tunnelStarted` is stale, then verify both
     * the JNI result and the observable worker state. A false result is never
     * presented to the user as confirmed forwarding shutdown.
     */
    private fun stopNativeWorker(): Boolean =
        lifecycleGate.runIfOpen { stopNativeWorkerUnchecked() } ?: false

    // Only call inside lifecycleGate, including its close action.
    private fun stopNativeWorkerUnchecked(): Boolean {
        return try {
            val stopAccepted = TProxyService.TProxyStopService()
            val workerStopped = !TProxyService.TProxyIsRunning()
            if (!stopAccepted || !workerStopped) {
                Log.e("AuraVPN", "El motor nativo no confirmó su detención.")
                false
            } else {
                true
            }
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo cerrar el worker VPN nativo.", exception)
            false
        } catch (error: LinkageError) {
            Log.e("AuraVPN", "No se pudo verificar el motor VPN nativo.", error)
            false
        }
    }

    private fun restartNativeWorker(configPath: String, tun: ParcelFileDescriptor): Boolean {
        return try {
            lifecycleGate.runIfOpen {
                if (vpnInterface !== tun || !tun.fileDescriptor.valid() || !stopNativeWorkerUnchecked()) {
                    false
                } else {
                    tunnelStarted = false
                    TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
                    TProxyService.TProxyStartService(configPath, tun.fd)
                }
            } ?: false
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo reanudar el worker VPN nativo.", exception)
            false
        } catch (error: LinkageError) {
            Log.e("AuraVPN", "El motor VPN nativo no está disponible para reanudarse.", error)
            false
        }
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
        val stopConfirmed = stopNativeWorker()
        tunnelStarted = false
        reportState(
            false,
            if (stopConfirmed) {
                "Túnel detenido por fallo de integridad."
            } else {
                "Fallo de integridad; el cierre del motor nativo no está confirmado."
            },
        )
        stopSelf()
        return false
    }

    private fun startTunnel(requestId: String?) {
        var established: ParcelFileDescriptor? = null
        try {
            underlyingNetwork = findUnderlyingNetwork()
                ?: throw IOException("No se encontró una red física de salida para el túnel.")

            // El túnel no debe depender de que un feed remoto esté disponible al arrancar.
            // La lista se carga en segundo plano y se aplica cuando el motor ya está activo.
            val tun = lifecycleGate.runIfOpen {
                val descriptor = createVpnBuilder().establish()
                    ?: throw IOException("Android no estableció la interfaz VPN.")
                vpnInterface = descriptor
                descriptor
            } ?: throw IOException("El servicio VPN está cerrándose.")
            established = tun

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
                  port: $LOCAL_SOCKS5_PORT
                  address: $LOCAL_SOCKS5_HOST
                  udp: 'tcp'
                misc:
                  log-level: error
                mapdns:
                  address: 10.0.0.3
                  port: 53
                  network: 100.64.0.0
                  netmask: 255.192.0.0
                  cache-size: 8192
                """.trimIndent(),
            )

            val started = lifecycleGate.runIfOpen {
                if (vpnInterface !== tun || !tun.fileDescriptor.valid()) {
                    false
                } else {
                    TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
                    TProxyService.TProxyStartService(configFile.absolutePath, tun.fd)
                }
            } ?: false
            if (!started) throw IOException("El motor tun2socks no pudo iniciar.")
            verifyLocalSocks5Ready()
            for (endpoint in AuraBlocklistService.knownEncryptedDnsEndpoints()) {
                val applied = lifecycleGate.runIfOpen {
                    TProxyService.TProxyAddDynamicSniRule(endpoint)
                } ?: false
                if (!applied) {
                    throw IOException("El firewall SNI no confirmó el bloqueo de $endpoint.")
                }
            }
            val ready = lifecycleGate.runIfOpen {
                if (!TProxyService.TProxyIsRunning()) false else {
                    tunnelStarted = true
                    true
                }
            } ?: false
            if (!ready) throw IOException("El motor VPN se detuvo durante el arranque.")
            scheduleFeedRefresh()
            reportState(
                true,
                "Túnel VPN iniciado; las fuentes de reputación IP se están actualizando.",
                requestId = requestId,
            )
            updateForegroundNotification()
            Log.i("AuraVPN", "Hev tun2socks conectado al proxy SOCKS5.")
        } catch (e: Exception) {
            handleTunnelStartFailure(e, established, requestId)
        } catch (error: LinkageError) {
            // JNI can fail before the native worker is created (missing ABI/library
            // or an unresolved native symbol). Treat that as a failed startup and
            // run the same descriptor/worker cleanup instead of crashing the service.
            handleTunnelStartFailure(error, established, requestId)
        }
    }

    private fun handleTunnelStartFailure(
        error: Throwable,
        established: ParcelFileDescriptor?,
        requestId: String?,
    ) {
        Log.e("AuraVPN", "No se pudo iniciar el escudo VPN.", error)
        val stopConfirmed = stopNativeWorker()
        tunnelStarted = false
        lifecycleGate.runIfOpen {
            try {
                established?.close()
                if (vpnInterface === established) vpnInterface = null
            } catch (closeError: Exception) {
                // Keep the descriptor for the destruction path to retry.
                Log.e("AuraVPN", "No se pudo cerrar la interfaz tras fallar el arranque.", closeError)
            }
            true
        }
        underlyingNetwork = null
        startRequested.set(false)
        val failureMessage = error.message ?: "No se pudo iniciar el túnel."
        reportState(
            false,
            if (stopConfirmed) {
                failureMessage
            } else {
                "$failureMessage El cierre del motor nativo no está confirmado."
            },
            requestId = requestId,
        )
        updateForegroundNotification()
        stopSelf()
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
            if (!stopNativeWorker()) {
                getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                    .edit()
                    .putBoolean(PANIC_ISOLATION_KEY, false)
                    .commit()
                return false
            }
            tunnelStarted = false
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

        return try {
            val tun = vpnInterface
                ?: throw IOException("La interfaz VPN no está disponible para reanudar el forwarding.")
            val configFile = File(filesDir, "aura-hev-socks5.yml")
            if (!configFile.isFile) {
                throw IOException("No existe la configuración del túnel para reanudarlo.")
            }

            // Reconcile native state and restart as one lifecycle operation.
            if (!restartNativeWorker(configFile.absolutePath, tun)) {
                throw IOException("El motor VPN no pudo iniciar durante la reanudación.")
            }
            verifyLocalSocks5Ready()

            val resumed = lifecycleGate.runIfOpen {
                val cleared = TProxyService.TProxyIsRunning() &&
                    getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                        .edit().putBoolean(PANIC_ISOLATION_KEY, false).commit()
                if (cleared) {
                    panicIsolationActive = false
                    tunnelStarted = true
                    startRequested.set(true)
                }
                cleared
            } ?: false
            if (!resumed) {
                throw IOException("No se pudo confirmar la salida del aislamiento de emergencia.")
            }
            scheduleFeedRefresh()
            reportState(true, "Forwarding del túnel VPN restablecido.")
            updateForegroundNotification()
            true
        } catch (exception: Exception) {
            handleResumeFailure(exception)
        } catch (error: LinkageError) {
            handleResumeFailure(error)
        }
    }

    private fun handleResumeFailure(error: Throwable): Boolean {
        val stopConfirmed = stopNativeWorker()
        tunnelStarted = false
        Log.e("AuraVPN", "No se pudo reanudar el forwarding del túnel.", error)
        reportState(
            false,
            if (stopConfirmed) {
                "No se pudo reanudar el túnel; el forwarding permanece detenido."
            } else {
                "No se pudo reanudar el túnel; el cierre nativo no está confirmado."
            },
        )
        updateForegroundNotification()
        return false
    }

    private fun establishPanicIsolationInterface() {
        var established: ParcelFileDescriptor? = null
        try {
            established = lifecycleGate.runIfOpen {
                val descriptor = createVpnBuilder().establish()
                    ?: throw IOException("Android no restableció la interfaz VPN aislada.")
                vpnInterface = descriptor
                descriptor
            } ?: throw IOException("El servicio VPN está cerrándose.")
            reportState(false, "Aislamiento de emergencia activo; tráfico en descarte.")
            updateForegroundNotification()
        } catch (exception: Exception) {
            handlePanicInterfaceFailure(exception, established)
        } catch (error: LinkageError) {
            handlePanicInterfaceFailure(error, established)
        }
    }

    private fun handlePanicInterfaceFailure(
        error: Throwable,
        established: ParcelFileDescriptor?,
    ) {
        Log.e("AuraVPN", "No se pudo restablecer la interfaz aislada.", error)
        lifecycleGate.runIfOpen {
            try {
                established?.close()
                if (vpnInterface === established) vpnInterface = null
            } catch (closeError: Exception) {
                Log.e("AuraVPN", "No se pudo cerrar la interfaz aislada.", closeError)
            }
            true
        }
        startRequested.set(false)
        reportState(false, error.message ?: "Falló el aislamiento de red.")
    }

    private fun createVpnBuilder(): Builder = Builder()
        .setSession("Aura Mobile Defens")
        .setMtu(1500)
        .setUnderlyingNetworks(underlyingNetwork?.let { arrayOf(it) })
        .addAddress("10.0.0.2", 24)
        .addAddress("fd00::2", 64)
        // Full routes capture TCP and UDP on both IP families for tunnel inspection.
        .addRoute("0.0.0.0", 0)
        .addRoute("::", 0)
        .addDnsServer("10.0.0.3")

    private fun registerUnderlyingNetworkCallback() {
        val connectivity = getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        try {
            connectivity.registerNetworkCallback(request, underlyingNetworkCallback)
            networkCallbackRegistered = true
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo registrar el seguimiento de la red física.", exception)
        }
    }

    private fun unregisterUnderlyingNetworkCallback() {
        if (!networkCallbackRegistered) return
        val connectivity = getSystemService(ConnectivityManager::class.java) ?: return
        try {
            connectivity.unregisterNetworkCallback(underlyingNetworkCallback)
        } catch (exception: Exception) {
            Log.w("AuraVPN", "No se pudo retirar el callback de red.", exception)
        } finally {
            networkCallbackRegistered = false
        }
    }

    private fun enqueueUnderlyingNetworkRefresh(excludedNetwork: Network? = null) {
        if (worker.isShutdown) return
        try {
            worker.execute { refreshUnderlyingNetwork(excludedNetwork) }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // Service teardown won the race with a final connectivity callback.
        }
    }

    @Synchronized
    private fun refreshUnderlyingNetwork(excludedNetwork: Network? = null) {
        if (serviceShuttingDown) return
        val previous = underlyingNetwork
        val selected = findUnderlyingNetwork(excludedNetwork)
        if (selected == previous) return

        underlyingNetwork = selected
        val underlayUpdated = try {
            // Keep Android's VPN routing metadata aligned with the physical network.
            // An empty array explicitly means there is currently no usable underlay.
            setUnderlyingNetworks(selected?.let { arrayOf(it) } ?: emptyArray())
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo actualizar la red subyacente de la VPN.", exception)
            false
        }

        if (!underlayUpdated) {
            // Keep the full-route TUN installed and stop native forwarding. Traffic
            // must not silently bypass Aura when underlay synchronization fails.
            stopTunnelForwardingForNetworkFailure(
                "No se pudo sincronizar la red física; forwarding detenido por seguridad.",
            )
            return
        }

        if (selected == null) {
            Log.w("AuraVPN", "Se perdió la red física; forwarding detenido hasta recuperar salida.")
            stopTunnelForwardingForNetworkFailure(
                "Sin red física disponible; tráfico retenido en la interfaz VPN.",
            )
        } else if (vpnInterface != null && !panicIsolationActive) {
            // Restart even when the previous underlay loss already stopped the worker.
            recoverTunnelAfterNetworkChange()
        }
    }

    /**
     * Stop native forwarding but retain the Android TUN interface. Its full IPv4
     * and IPv6 routes remain installed, preventing silent physical-network bypass.
     */
    private fun stopTunnelForwardingForNetworkFailure(message: String) {
        var stopConfirmed = false
        try {
            stopConfirmed = stopNativeWorker()
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo detener el forwarding tras perder la red.", exception)
        } finally {
            tunnelStarted = false
            reportState(
                false,
                if (stopConfirmed) {
                    message
                } else {
                    "$message El cierre del motor nativo no está confirmado."
                },
            )
            updateForegroundNotification()
        }
    }

    /**
     * A running tun2socks instance may retain upstream sockets created on the
     * previous physical network. Updating Android's underlying-network metadata
     * alone does not migrate those sockets. Restart the native worker against the
     * same TUN descriptor so new protected sockets use the selected underlay.
     */
    private fun recoverTunnelAfterNetworkChange() {
        val tun = vpnInterface
        if (tun == null || !tun.fileDescriptor.valid()) {
            tunnelStarted = false
            reportState(false, "La red cambió, pero la interfaz VPN ya no está disponible.")
            return
        }

        try {
            if (!restartNativeWorker(File(filesDir, "aura-hev-socks5.yml").absolutePath, tun)) {
                throw IOException("El motor VPN no pudo reiniciarse en la nueva red.")
            }
            verifyLocalSocks5Ready()
            for (endpoint in AuraBlocklistService.knownEncryptedDnsEndpoints()) {
                val applied = lifecycleGate.runIfOpen {
                    TProxyService.TProxyAddDynamicSniRule(endpoint)
                } ?: false
                if (!applied) {
                    throw IOException("No se pudo restaurar una regla SNI tras cambiar de red.")
                }
            }
            val ready = lifecycleGate.runIfOpen {
                if (!TProxyService.TProxyIsRunning()) false else {
                    tunnelStarted = true
                    true
                }
            } ?: false
            if (!ready) throw IOException("El motor VPN se detuvo durante la recuperación.")
            reportState(
                true,
                "Red física cambiada; motor VPN reiniciado y proxy SOCKS5 verificado.",
            )
            Log.i("AuraVPN", "Motor tun2socks recuperado tras cambiar la red física.")
        } catch (exception: Exception) {
            val stopConfirmed = stopNativeWorker()
            tunnelStarted = false
            Log.e("AuraVPN", "No se pudo recuperar el túnel tras cambiar de red.", exception)
            reportState(
                false,
                if (stopConfirmed) {
                    "La red cambió y el túnel no pudo recuperarse. Reactiva la protección."
                } else {
                    "La red cambió; la recuperación y el cierre nativo no están confirmados."
                },
            )
        }
    }

    private fun findUnderlyingNetwork(excludedNetwork: Network? = null): Network? {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val candidates = connectivity.allNetworks.mapNotNull { network ->
            if (network == excludedNetwork) return@mapNotNull null
            val capabilities = connectivity.getNetworkCapabilities(network) ?: return@mapNotNull null
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            ) {
                null
            } else {
                network to capabilities
            }
        }
        return candidates.firstOrNull {
            it.second.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        }?.first ?: candidates.firstOrNull()?.first
    }

    /**
     * Native tun2socks creates upstream sockets before connecting them. Protecting
     * alone only excludes a socket from this VPN; it does not pin it to the
     * physical Network selected by Aura. Bind it explicitly so a handover cannot
     * send the proxy socket through a different default network (or back into
     * the VPN routing path).
     */
    private fun protectAndBindSocket(socketFd: Int): Boolean {
        val network = underlyingNetwork ?: return false
        if (!protect(socketFd)) return false
        return try {
            network.bindSocket(socketFd)
            true
        } catch (exception: Exception) {
            Log.w(
                "AuraVPN",
                "No se pudo fijar el socket nativo a la red física seleccionada.",
                exception,
            )
            false
        }
    }

    private fun resolveHostOnUnderlyingNetwork(hostname: String): String? {
        val normalized = hostname.trim().trimEnd('.')
        if (normalized.isBlank() || normalized.length > 253 ||
            normalized.any { it.isWhitespace() || it == '/' }
        ) return null

        val network = underlyingNetwork ?: return null
        return try {
            network.getAllByName(normalized).firstOrNull()?.hostAddress?.substringBefore('%')
        } catch (_: Exception) {
            Log.w("AuraVPN", "No se pudo resolver el destino en la red física.")
            null
        }
    }

    private fun verifyLocalSocks5Ready() {
        val deadline = android.os.SystemClock.elapsedRealtime() + 5000
        var lastFailure: Exception? = null
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            try {
                Socket().use { socket ->
                    socket.connect(
                        InetSocketAddress(LOCAL_SOCKS5_HOST, LOCAL_SOCKS5_PORT),
                        250,
                    )
                    socket.soTimeout = 500
                    socket.getOutputStream().write(byteArrayOf(5, 1, 0))
                    socket.getOutputStream().flush()
                    val response = ByteArray(2)
                    var offset = 0
                    while (offset < response.size) {
                        val count = socket.getInputStream().read(
                            response,
                            offset,
                            response.size - offset,
                        )
                        if (count < 0) throw IOException("El proxy SOCKS5 local cerró el saludo.")
                        offset += count
                    }
                    if (response[0].toInt() != 5 || response[1].toInt() != 0) {
                        throw IOException("El proxy SOCKS5 local rechazó la negociación.")
                    }
                }
                if (!TProxyService.TProxyIsRunning()) {
                    throw IOException("El proxy respondió, pero el motor VPN ya no está activo.")
                }
                return
            } catch (exception: Exception) {
                lastFailure = exception
                Thread.sleep(100)
            }
        }
        throw IOException("El proxy SOCKS5 local no quedó listo; túnel detenido.", lastFailure)
    }

    private fun downloadThreatFeed(): Set<String> {
        val connection = URL(THREAT_FEED_URL).openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 15000
        connection.useCaches = false
        // Threat intelligence must never be accepted after an HTTPS-to-HTTP redirect.
        connection.instanceFollowRedirects = false

        try {
            if (!connection.url.protocol.equals("https", ignoreCase = true)) {
                throw IOException("El feed de amenazas debe permanecer en HTTPS.")
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw IOException("El feed de amenazas devolvió HTTP ${connection.responseCode}.")
            }
            val declaredLength = connection.contentLengthLong
            if (declaredLength > MAX_THREAT_FEED_BYTES) {
                throw IOException("El feed de amenazas supera el límite de tamaño permitido.")
            }

            val feedBytes = connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > MAX_THREAT_FEED_BYTES) {
                        throw IOException("El feed de amenazas supera el límite de tamaño permitido.")
                    }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }

            return feedBytes.toString(Charsets.UTF_8).lineSequence()
                .map { it.substringBefore('#').trim() }
                .filter(::isIpAddress)
                .take(MAX_BLOCKED_IPS)
                .toCollection(HashSet())
                .also {
                    if (it.isEmpty()) {
                        throw IOException("El feed no contiene direcciones IP válidas.")
                    }
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

    private fun replaceBlockedIps(updated: Set<String>) {
        synchronized(blockedIps) {
            blockedIps.clear()
            blockedIps.addAll(updated)
        }
    }

    private fun blockedIpSnapshot(): Array<String> = synchronized(blockedIps) {
        blockedIps.toTypedArray()
    }

    private fun scheduleFeedRefresh() {
        if (feedRefreshScheduled) return
        feedRefreshScheduled = true

        // Primera descarga inmediata pero asíncrona: no bloquea el consentimiento ni
        // el establecimiento del túnel cuando el teléfono está offline o el feed cae.
        feedRefresh.execute { refreshThreatFeed() }
        feedRefresh.scheduleWithFixedDelay(
            { refreshThreatFeed() },
            60,
            60,
            TimeUnit.MINUTES,
        )
    }

    private fun refreshThreatFeed() {
        try {
            val updated = downloadThreatFeed()
            replaceBlockedIps(updated)
            lifecycleGate.runIfOpen {
                if (tunnelStarted && TProxyService.TProxyIsRunning()) {
                    TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
                }
                true
            }
            if (shieldStatus()["forwarding_active"] == true) {
                reportState(true, "Túnel activo; feed de reputación IP actualizado.")
            }
        } catch (e: Exception) {
            Log.w(
                "AuraVPN",
                "No se pudo actualizar el feed; se conserva la lista IP verificada anterior.",
                e,
            )
            if (shieldStatus()["forwarding_active"] == true && blockedIpSnapshot().isEmpty()) {
                reportState(
                    true,
                    "Túnel activo con cobertura reducida: feed de reputación IP no disponible.",
                )
            }
        } catch (error: LinkageError) {
            Log.e(
                "AuraVPN",
                "El motor nativo no está disponible para aplicar el feed IP; se conserva la lista anterior.",
                error,
            )
        }
    }

    private fun reportState(
        started: Boolean,
        message: String,
        revoked: Boolean = false,
        requestId: String? = null,
    ) {
        val stateIntent = android.content.Intent(ACTION_STATE)
            .setPackage(packageName)
            .putExtra("started", started)
            .putExtra("message", message)
            .putExtra("revoked", revoked)
        if (requestId != null) stateIntent.putExtra(EXTRA_START_REQUEST_ID, requestId)
        sendBroadcast(stateIntent, "$packageName.permission.VPN_STATE")
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
        val nativeRunning = try {
            TProxyService.TProxyIsRunning()
        } catch (_: Exception) {
            false
        } catch (_: LinkageError) {
            false
        }
        if (panicIsolationActive) {
            "AISLAMIENTO ACTIVO · forwarding detenido"
        } else if (!tunnelStarted || !nativeRunning ||
            vpnInterface?.fileDescriptor?.valid() != true
        ) {
            "Motor VPN sin forwarding confirmado"
        } else if (auditedDnsRequests == 0L) {
            "Túnel activo · esperando eventos DNS"
        } else {
            // The native event is emitted before the response is sent, so this
            // is a rule match count, not proof of delivery or traffic blocking.
            "DNS $auditedDnsRequests · coincidencias de bloqueo $blockedDnsRequests"
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
            .setContentTitle("Aura Centinela")
            // Show the actual service state and DNS summary instead of a fixed
            // "active" claim while the tunnel may be degraded or isolated.
            .setContentText(contentText)
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
