package com.ciberdefensa.aura

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
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
        const val ACTION_START = "com.ciberdefensa.aura.action.START_VPN"
        const val ACTION_STOP = "com.ciberdefensa.aura.action.STOP_VPN"
        const val EXTRA_START_REQUEST_ID = "com.ciberdefensa.aura.VPN_START_REQUEST_ID"
        private const val USER_STOPPED_KEY = "user_stopped"
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

        /**
         * True while the TUN file descriptor is still open.
         * Internal: the label logic lives in this module.
         */
        internal fun isTunnelInterfaceUp(): Boolean {
            val service = activeService ?: return false
            return service.vpnInterface?.fileDescriptor?.valid() == true
        }

        /**
         * Capabilities of the network last passed to setUnderlyingNetworks,
         * or null when the tunnel interface is not up or no underlay was stored.
         * Internal so this public service does not expose the internal facts type.
         */
        internal fun appliedUnderlyingFacts(): PublicNetworkFacts? {
            val service = activeService ?: return null
            if (!isTunnelInterfaceUp()) return null
            val network = service.underlyingNetwork ?: return null
            val capabilities = service.trackedNetworks[network] ?: return null
            return networkFacts(capabilities)
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
    @Volatile private var userRequestedStop = false
    private val tunnelReleased = AtomicBoolean(false)
    private val stopExecutor = java.util.concurrent.Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "aura-vpn-stop")
    }
    private val stopScheduler = TunnelReleaseScheduler(stopExecutor) { releaseTunnel() }
    private val trackedNetworks = java.util.Collections.synchronizedMap(
        linkedMapOf<Network, NetworkCapabilities>(),
    )
    private val underlyingNetworkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            rememberNetwork(network, null)
            enqueueUnderlyingNetworkRefresh()
        }

        override fun onLost(network: Network) {
            trackedNetworks.remove(network)
            enqueueUnderlyingNetworkRefresh(excludedNetwork = network)
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            rememberNetwork(network, networkCapabilities)
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
    private val recoveryGate = VpnRecoveryGate()
    private val lifecycleGate = VpnLifecycleGate()
    private val notificationHandler = Handler(Looper.getMainLooper())
    private var notificationUpdatePending = false
    @Volatile private var vpnInterface: ParcelFileDescriptor? = null
    private var integrityCheckScheduled = false
    private var feedRefreshScheduled = false
    @Volatile private var panicIsolationActive = false
    @Volatile private var tunnelStarted = false
    @Volatile private var localSocks5Credentials: AuraSocks5Credentials? = null

    override fun onCreate() {
        super.onCreate()
        userRequestedStop = getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
            .getBoolean(USER_STOPPED_KEY, false)
        AuraCrashReporter.install(applicationContext)
        activeService = this
        AuraNetworkStream.setApplicationContext(applicationContext)
        registerUnderlyingNetworkCallback()
        AuraUnderlyingNetwork.ensureStarted(applicationContext)
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
        try {
            ensureNotificationChannel()
            val notification = createNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (exception: Exception) {
            Log.e("AuraVPN", "Android rechazó el servicio VPN en primer plano.", exception)
            reportState(
                false,
                "Android rechazó el servicio VPN en primer plano.",
                requestId = requestId,
            )
            stopSelf()
            return Service.START_NOT_STICKY
        }
        if (intent?.action == ACTION_START && serviceShuttingDown) {
            reportState(
                false,
                "El Escudo se está cerrando. Espera a que termine y vuelve a activarlo.",
                requestId = requestId,
            )
            return Service.START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            val lockdown = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && isLockdownEnabled
            if (SystemVpnRestart.decideExplicitStop(lockdown) ==
                SystemVpnRestart.ExplicitStop.WARN_AND_KEEP_RUNNING
            ) {
                val message =
                    "El Escudo sigue activo porque el bloqueo de Android dejaría el teléfono sin red. " +
                        "Desactiva «Bloquear conexiones sin VPN» en Ajustes → Red → VPN y vuelve a pulsar Detener."
                AuraNotificationService.triggerPersistentAlert(
                    this,
                    "No se apaga el Escudo con el bloqueo activo",
                    message,
                )
                reportState(true, message, requestId = requestId)
                return Service.START_STICKY
            }
            performUserStop("Escudo detenido.")
            return Service.START_NOT_STICKY
        }
        if (userRequestedStop && intent?.action != ACTION_START) {
            when (systemRestartAfterUserStop()) {
                SystemVpnRestart.Action.START_BECAUSE_LOCKDOWN -> {
                    setUserStopped(false)
                    AuraNotificationService.triggerPersistentAlert(
                        this,
                        "El bloqueo de Android exige el Escudo",
                        "Android tiene el bloqueo de VPN activo. Sin el Escudo el teléfono se queda sin red. Se vuelve a iniciar; no se apaga en silencio.",
                    )
                }
                SystemVpnRestart.Action.NOTIFY_AND_STAY_DOWN -> {
                    AuraNotificationService.triggerPersistentAlert(
                        this,
                        "El Escudo sigue apagado",
                        "Android quiere el Escudo siempre activo, pero lo habías detenido. Para dejarlo así, desactiva «VPN siempre activa» en los ajustes del sistema. No se ha cerrado la red en silencio.",
                    )
                    removeForegroundNotification()
                    stopSelf()
                    return Service.START_NOT_STICKY
                }
                SystemVpnRestart.Action.TEAR_DOWN -> {
                    performUserStop("Escudo detenido.")
                    return Service.START_NOT_STICKY
                }
            }
        }
        if (intent?.action == ACTION_START) {
            setUserStopped(false)
        }
        if (!verifyIntegrityOrStop()) {
            val report = try {
                AuraAntiTampering.inspect(this)
            } catch (_: Exception) {
                emptyMap()
            }
            val reason = AuraAntiTampering.failureReason(report).ifBlank {
                "La comprobacion de integridad impidio el arranque."
            }
            Log.e("AuraVPN", reason)
            if (requestId != null) {
                reportState(false, reason, requestId = requestId)
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
        if (shieldStatus()["forwarding_active"] == true) {
            reportState(true, "El Escudo ya estaba activo.", requestId = requestId)
        } else if (shouldRetryTunnelRecovery()) {
            // A stale tunnelStarted flag is not evidence of a live worker. Reuse
            // the retained valid TUN and verify recovery for this exact request.
            requestTunnelRecovery(requestId)
        } else if (vpnInterface != null) {
            reportState(
                false,
                if (startRequested.get()) {
                    "Ya hay un arranque VPN en curso."
                } else {
                    "La interfaz VPN no está disponible para recuperar el forwarding."
                },
                requestId = requestId,
            )
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
        // releaseTunnel() joins the native worker. That join runs on
        // aura-vpn-stop, not on this main-thread callback.
        scheduleTunnelRelease { confirmed ->
            if (activeService === this) {
                lastShutdownConfirmed = confirmed
                activeService = null
            }
        }
        stopExecutor.shutdown()
        removeForegroundNotification()
        notificationHandler.removeCallbacksAndMessages(null)
        underlyingNetwork = null
        stopService(Intent(this, AuraNotificationService::class.java))
        super.onDestroy()
    }

    override fun onRevoke() {
        // Revocation can arrive while a worker is still starting. Refuse new
        // native work, close the TUN, and remember the stop so a sticky
        // restart cannot bring the tunnel back without an explicit start.
        val message =
            "[CRIT] TÚNEL REVOCADO POR ANDROID O POR EL OPERADOR — " +
                "LAS DEFENSAS ESTÁN INACTIVAS. " +
                "Remedio: revise el consentimiento VPN y reactive la defensa."
        AuraNotificationService.triggerPersistentAlert(
            this,
            "Escudo revocado",
            message,
        )
        performUserStop(message, revoked = true)
        super.onRevoke()
    }

    /**
     * Explicit user or system stop. Closes hev-socks5-tunnel, the local SOCKS5
     * listener and the TUN, then removes the foreground notification. A later
     * network callback must not start the tunnel again.
     */
    private fun performUserStop(message: String, revoked: Boolean = false) {
        setUserStopped(true)
        panicIsolationActive = false
        serviceShuttingDown = true
        lifecycleGate.beginClosing()
        tunnelStarted = false
        startRequested.set(false)
        scheduleTunnelRelease { confirmed ->
            reportState(false, message, revoked = revoked)
            removeForegroundNotification()
            if (activeService === this) {
                lastShutdownConfirmed = confirmed
                activeService = null
            }
            stopSelf()
        }
    }

    /**
     * A previous user stop plus a system restart. Lockdown must bring the
     * shield back, because leaving it down black-holes the phone. Always-on
     * without lockdown stays down and says so. Neither path calls
     * [performUserStop] just because the process was started again.
     */
    private fun systemRestartAfterUserStop(): SystemVpnRestart.Action {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return SystemVpnRestart.decide(alwaysOn = false, lockdown = false)
        }
        return SystemVpnRestart.decide(
            alwaysOn = isAlwaysOn,
            lockdown = isLockdownEnabled,
        )
    }

    private fun scheduleTunnelRelease(after: (Boolean) -> Unit = {}) {
        stopScheduler.schedule { confirmed ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                after(confirmed)
            }
        }
    }

    private fun setUserStopped(stopped: Boolean) {
        userRequestedStop = stopped
        getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
            .edit()
            .putBoolean(USER_STOPPED_KEY, stopped)
            .putBoolean(PANIC_ISOLATION_KEY, if (stopped) false else panicIsolationActive)
            .commit()
    }

    private fun releaseTunnel(): Boolean {
        if (!tunnelReleased.compareAndSet(false, true)) return lastShutdownConfirmed
        val confirmed = lifecycleGate.close {
            val nativeStopped = stopNativeWorkerUnchecked()
            val interfaceClosed = try {
                vpnInterface?.close()
                vpnInterface = null
                true
            } catch (exception: Exception) {
                Log.e("AuraVPN", "No se pudo cerrar la interfaz VPN.", exception)
                false
            }
            nativeStopped && interfaceClosed
        }
        discardTunnelConfiguration()
        return confirmed
    }

    private fun removeForegroundNotification() {
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (exception: Exception) {
            Log.w("AuraVPN", "No se pudo retirar la notificación de la VPN.", exception)
        }
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

        Log.e(
            "AuraVPN",
            "Deteniendo el tunel por fallo de integridad: ${AuraAntiTampering.failureReason(report)} " +
                "signatureValid=${report["signatureValid"]} maps=${report["mapsInspectionSucceeded"]} " +
                "frida=${report["fridaDetected"]} debugger=${report["debuggerBlocked"]} " +
                "testSigned=${report["testSignedArtifact"]}.",
        )
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
        if (userRequestedStop || serviceShuttingDown) return
        var established: ParcelFileDescriptor? = null
        try {
            requireUnderlyingNetworkMonitor()
            underlyingNetwork = findUnderlyingNetwork()
                ?: throw IOException("No se encontró una red física de salida para el túnel.")

            // El túnel no debe depender de que un feed remoto esté disponible al arrancar.
            // La lista se carga en segundo plano y se aplica cuando el motor ya está activo.
            val tun = lifecycleGate.runIfOpen {
                val descriptor = establishVpnInterface()
                vpnInterface = descriptor
                descriptor
            } ?: throw IOException("El servicio VPN está cerrándose.")
            established = tun
            if (userRequestedStop || serviceShuttingDown) return

            val (configFile, socks5Credentials) = prepareTunnelConfiguration()

            val started = lifecycleGate.runIfOpen {
                if (vpnInterface !== tun || !tun.fileDescriptor.valid()) {
                    false
                } else {
                    TProxyService.TProxySetBlockedIps(blockedIpSnapshot())
                    TProxyService.TProxyStartService(configFile.absolutePath, tun.fd)
                }
            } ?: false
            if (!started) throw IOException("El motor tun2socks no pudo iniciar.")
            verifyLocalSocks5Ready(socks5Credentials)
            applyOptionalSniRules(AuraBlocklistService.knownEncryptedDnsEndpoints())
            val ready = lifecycleGate.runIfOpen {
                if (!TProxyService.TProxyIsRunning()) false else {
                    tunnelStarted = true
                    true
                }
            } ?: false
            if (!ready) throw IOException("El motor VPN se detuvo durante el arranque.")
            startRequested.set(false)
            scheduleFeedRefresh()
            reportState(
                true,
                "Escudo iniciado; las fuentes de reputación IP se están actualizando.",
                requestId = requestId,
            )
            updateForegroundNotification()
            Log.i("AuraVPN", "Hev tun2socks autenticado con el proxy SOCKS5 local.")
        } catch (error: Throwable) {
            if (userRequestedStop || serviceShuttingDown) return
            // Any failure here (I/O, JNI LinkageError from a missing ABI/library or
            // unresolved symbol, unexpected runtime errors) runs on the worker
            // executor: an escaping Throwable would kill the whole app process
            // while the TUN is up. Report it and clean up instead.
            try {
                handleTunnelStartFailure(error, established, requestId)
            } catch (cleanupError: Throwable) {
                Log.e("AuraVPN", "Falló la limpieza tras el error de arranque.", cleanupError)
                startRequested.set(false)
                try {
                    reportState(false, describeFailure(error), requestId = requestId)
                } catch (_: Throwable) {
                }
                stopSelf()
            }
        }
    }

    /**
     * Optional DoH/SNI hints must never roll back (or crash) an already
     * authenticated tunnel. The native call can throw IllegalStateException or
     * IllegalArgumentException; log and continue.
     */
    private fun applyOptionalSniRules(endpoints: List<String>) {
        for (endpoint in endpoints) {
            val applied = try {
                lifecycleGate.runIfOpen {
                    TProxyService.TProxyAddDynamicSniRule(endpoint)
                } ?: false
            } catch (error: Exception) {
                Log.w("AuraVPN", "Regla SNI opcional rechazada por el motor nativo.", error)
                false
            }
            if (!applied) {
                Log.w(
                    "AuraVPN",
                    "No se pudo aplicar la regla SNI opcional para un resolvedor conocido.",
                )
            }
        }
    }

    private fun describeFailure(error: Throwable): String {
        val message = error.message?.takeIf { it.isNotBlank() }
        return when {
            error is IOException && message != null -> message
            message != null -> "${error.javaClass.simpleName}: $message"
            else -> "No se pudo iniciar el túnel (${error.javaClass.simpleName})."
        }
    }

    private fun handleTunnelStartFailure(
        error: Throwable,
        established: ParcelFileDescriptor?,
        requestId: String?,
    ) {
        Log.e("AuraVPN", "No se pudo iniciar el escudo VPN.", error)
        AuraCrashReporter.recordVpnFailure(this, "startTunnel", error)
        val stopConfirmed = stopNativeWorker()
        if (stopConfirmed) discardTunnelConfiguration()
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
        val failureMessage = describeFailure(error)
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
            discardTunnelConfiguration()
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
            requireUnderlyingNetworkMonitor()
            val tun = vpnInterface
                ?: throw IOException("La interfaz VPN no está disponible para reanudar el forwarding.")
            val (configFile, socks5Credentials) = prepareTunnelConfiguration()

            // Reconcile native state and restart as one lifecycle operation.
            if (!restartNativeWorker(configFile.absolutePath, tun)) {
                throw IOException("El motor VPN no pudo iniciar durante la reanudación.")
            }
            verifyLocalSocks5Ready(socks5Credentials)

            val resumed = lifecycleGate.runIfOpen {
                val cleared = TProxyService.TProxyIsRunning() &&
                    getSharedPreferences(VPN_STATE_PREFERENCES, MODE_PRIVATE)
                        .edit().putBoolean(PANIC_ISOLATION_KEY, false).commit()
                if (cleared) {
                    panicIsolationActive = false
                    tunnelStarted = true
                    startRequested.set(false)
                }
                cleared
            } ?: false
            if (!resumed) {
                throw IOException("No se pudo confirmar la salida del aislamiento de emergencia.")
            }
            scheduleFeedRefresh()
            reportState(true, "Forwarding del Escudo restablecido.")
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
        if (stopConfirmed) discardTunnelConfiguration()
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
                val descriptor = establishVpnInterface(
                    rejectedMessage = "Android no restablecio la interfaz VPN aislada.",
                )
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

    private fun establishVpnInterface(
        rejectedMessage: String = "Android no estableció la interfaz VPN.",
    ): ParcelFileDescriptor {
        val withIpv6 = createVpnBuilder(includeIpv6 = true).establish()
        if (withIpv6 != null) return withIpv6
        Log.w("AuraVPN", "Android rechazo el tunel con IPv6; reintentando solo IPv4.")
        return createVpnBuilder(includeIpv6 = false).establish()
            ?: throw IOException(rejectedMessage)
    }

    private fun createVpnBuilder(includeIpv6: Boolean = true): Builder {
        val builder = Builder()
            .setSession("Aura Mobile Defens")
            .setMtu(1500)
            .setUnderlyingNetworks(underlyingNetwork?.let { arrayOf(it) })
            .addAddress("10.0.0.2", 24)
            // Full routes capture TCP and UDP for tunnel inspection.
            .addRoute("0.0.0.0", 0)
            .addDnsServer("10.0.0.3")
        try {
            // Aura's own sockets (local SOCKS5 relay upstreams, threat feed,
            // DNS on the physical network) must never re-enter its own TUN.
            builder.addDisallowedApplication(packageName)
        } catch (exception: android.content.pm.PackageManager.NameNotFoundException) {
            Log.w("AuraVPN", "No se pudo excluir la propia app del túnel.", exception)
        }
        if (includeIpv6) {
            builder.addAddress("fd00::2", 64)
            builder.addRoute("::", 0)
        }
        return builder
    }

    /**
     * Forwarding sockets are pinned to a physical Network. Without the callback
     * that reports handovers, Aura cannot safely recover those sockets when the
     * selected network disappears or changes; do not start or resume forwarding
     * if Android rejected the monitor registration.
     */
    private fun requireUnderlyingNetworkMonitor() {
        if (!networkCallbackRegistered) {
            throw IOException(
                "No se pudo registrar el seguimiento de la red física; " +
                    "el forwarding no se iniciará sin recuperación de handover."
            )
        }
    }

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
        if (userRequestedStop || worker.isShutdown) return
        try {
            worker.execute { refreshUnderlyingNetwork(excludedNetwork) }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // Service teardown won the race with a final connectivity callback.
        }
    }

    @Synchronized
    private fun refreshUnderlyingNetwork(excludedNetwork: Network? = null) {
        if (serviceShuttingDown) return
        if (userRequestedStop) return
        val previous = underlyingNetwork
        val selected = findUnderlyingNetwork(excludedNetwork)
        if (selected == previous) {
            // A failed recovery can leave the selected underlay unchanged while
            // the TUN remains installed and native forwarding is stopped. A later
            // callback on that same network is still a valid recovery trigger.
            if (selected != null && shouldRetryTunnelRecovery()) {
                requestTunnelRecovery()
            }
            return
        }

        val underlayUpdated = try {
            // Keep Android's VPN routing metadata aligned with the physical network.
            // An empty array explicitly means there is currently no usable underlay.
            setUnderlyingNetworks(selected?.let { arrayOf(it) } ?: emptyArray())
        } catch (exception: Exception) {
            Log.e("AuraVPN", "No se pudo actualizar la red subyacente de la VPN.", exception)
            false
        }

        if (!underlayUpdated) {
            // Keep the full-route TUN installed and stop native forwarding. Retain
            // the previous Network so the next callback retries this handover
            // instead of mistaking the failed candidate for an applied underlay.
            stopTunnelForwardingForNetworkFailure(
                "No se pudo sincronizar la red física; forwarding detenido por seguridad.",
            )
            return
        }

        // Commit the selected Network only after Android confirms the metadata
        // update. If that update failed, a later callback must try it again.
        underlyingNetwork = selected
        AuraUnderlyingNetwork.publish()

        if (selected == null) {
            Log.w("AuraVPN", "Se perdió la red física; forwarding detenido hasta recuperar salida.")
            stopTunnelForwardingForNetworkFailure(
                "Sin red física disponible; tráfico retenido en la interfaz VPN.",
            )
        } else if (vpnInterface != null && !panicIsolationActive) {
            // Restart even when the previous underlay loss already stopped the worker.
            requestTunnelRecovery()
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
            if (stopConfirmed) discardTunnelConfiguration()
            tunnelStarted = false
            startRequested.set(false)
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

    private fun shouldRetryTunnelRecovery(): Boolean =
        recoveryGate.canRetryRetainedTunnel(
            hasValidInterface = vpnInterface?.fileDescriptor?.valid() == true,
            panicIsolationActive = panicIsolationActive,
            forwardingVerified = shieldStatus()["forwarding_active"] == true,
            startInProgress = startRequested.get(),
            closing = serviceShuttingDown || worker.isShutdown || userRequestedStop,
        )

    /**
     * A running tun2socks instance may retain upstream sockets created on the
     * previous physical network. Updating Android's underlying-network metadata
     * alone does not migrate those sockets. Restart the native worker against the
     * same TUN descriptor so new protected sockets use the selected underlay.
     */
    private fun requestTunnelRecovery(requestId: String? = null) {
        if (userRequestedStop) return
        if (worker.isShutdown) {
            if (requestId != null) {
                reportState(false, "El servicio VPN está cerrándose.", requestId = requestId)
            }
            return
        }
        val attempt = recoveryGate.tryBegin(requestId)
        if (attempt == null) {
            if (requestId != null) {
                reportState(false, "La recuperación del túnel ya está en curso.", requestId = requestId)
            }
            return
        }
        try {
            worker.execute {
                try {
                    if (userRequestedStop) return@execute
                    if (serviceShuttingDown || panicIsolationActive) {
                        if (requestId != null) {
                            reportState(
                                false,
                                "La recuperación VPN no está disponible en el estado actual.",
                                requestId = attempt.requestId,
                            )
                        }
                        return@execute
                    }
                    recoverTunnelAfterNetworkChange(attempt.requestId)
                } finally {
                    recoveryGate.finish(attempt)
                }
            }
        } catch (error: java.util.concurrent.RejectedExecutionException) {
            recoveryGate.finish(attempt)
            if (requestId != null) {
                reportState(false, "El servicio VPN está cerrándose.", requestId = requestId)
            }
        }
    }

    private fun recoverTunnelAfterNetworkChange(requestId: String? = null) {
        val tun = vpnInterface
        if (tun == null || !tun.fileDescriptor.valid()) {
            tunnelStarted = false
            reportState(
                false,
                "La red cambió, pero la interfaz VPN ya no está disponible.",
                requestId = requestId,
            )
            return
        }

        try {
            requireUnderlyingNetworkMonitor()
            if (underlyingNetwork == null) {
                throw IOException("No hay una red física disponible para recuperar el forwarding.")
            }
            val (configFile, socks5Credentials) = prepareTunnelConfiguration()
            if (!restartNativeWorker(configFile.absolutePath, tun)) {
                throw IOException("El motor VPN no pudo reiniciarse en la nueva red.")
            }
            verifyLocalSocks5Ready(socks5Credentials)
            // Same optional (non-fatal) SNI hints as the initial start.
            applyOptionalSniRules(AuraBlocklistService.knownEncryptedDnsEndpoints())
            val ready = lifecycleGate.runIfOpen {
                if (!TProxyService.TProxyIsRunning()) false else {
                    tunnelStarted = true
                    true
                }
            } ?: false
            if (!ready) throw IOException("El motor VPN se detuvo durante la recuperación.")
            reportState(
                true,
                "Red física cambiada; motor VPN reiniciado y proxy SOCKS5 autenticado.",
                requestId = requestId,
            )
            Log.i("AuraVPN", "Motor tun2socks recuperado tras cambiar la red física.")
        } catch (exception: Exception) {
            handleNetworkRecoveryFailure(exception, requestId)
        } catch (error: LinkageError) {
            handleNetworkRecoveryFailure(error, requestId)
        }
    }

    private fun handleNetworkRecoveryFailure(error: Throwable, requestId: String? = null) {
        val stopConfirmed = stopNativeWorker()
        if (stopConfirmed) discardTunnelConfiguration()
        tunnelStarted = false
        startRequested.set(false)
        Log.e("AuraVPN", "No se pudo recuperar el túnel tras cambiar de red.", error)
        reportState(
            false,
            if (stopConfirmed) {
                "La red cambió y el túnel no pudo recuperarse. Reactiva la protección."
            } else {
                "La red cambió; la recuperación y el cierre nativo no están confirmados."
            },
            requestId = requestId,
        )
        updateForegroundNotification()
    }

    private fun rememberNetwork(network: Network, capabilities: NetworkCapabilities?) {
        val resolved = capabilities ?: getSystemService(ConnectivityManager::class.java)
            ?.getNetworkCapabilities(network)
        if (resolved == null) return
        trackedNetworks[network] = resolved
    }

    private fun findUnderlyingNetwork(excludedNetwork: Network? = null): Network? {
        val snapshot = synchronized(trackedNetworks) { LinkedHashMap(trackedNetworks) }
        val candidates = snapshot.mapNotNull { (network, capabilities) ->
            if (network == excludedNetwork) return@mapNotNull null
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            ) {
                null
            } else {
                network to networkFacts(capabilities)
            }
        }
        val chosen = UnderlyingNetworkKind.choosePhysical(candidates.map { it.second })
            ?: return null
        return candidates.firstOrNull { it.second == chosen }?.first
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
            // Network.bindSocket accepts FileDescriptor, not the raw JNI int.
            // fromFd duplicates ownership; closing this temporary wrapper must
            // never close the original socket that the native worker owns.
            ParcelFileDescriptor.fromFd(socketFd).use { descriptor ->
                network.bindSocket(descriptor.fileDescriptor)
            }
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

    @Synchronized
    private fun prepareTunnelConfiguration(): Pair<File, AuraSocks5Credentials> {
        if (serviceShuttingDown) throw IOException("El servicio VPN está cerrándose.")
        val credentials = localSocks5Credentials
            ?: AuraSocks5Credentials.generate().also { localSocks5Credentials = it }
        val configFile = File(filesDir, "aura-hev-socks5.yml")
        val config =
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
              username: '${credentials.username}'
              password: '${credentials.password}'
              udp: 'tcp'
            misc:
              log-level: error
            mapdns:
              address: 10.0.0.3
              port: 53
              network: 100.64.0.0
              netmask: 255.192.0.0
              cache-size: 8192
            """.trimIndent()
        configFile.writeText(config, Charsets.UTF_8)
        return configFile to credentials
    }

    @Synchronized
    private fun discardTunnelConfiguration() {
        localSocks5Credentials = null
        val configFile = File(filesDir, "aura-hev-socks5.yml")
        try {
            if (configFile.exists() && !configFile.delete()) {
                Log.w("AuraVPN", "No se pudo borrar la configuración efímera del proxy SOCKS5.")
            }
        } catch (exception: SecurityException) {
            Log.w("AuraVPN", "No se pudo borrar la configuración efímera del proxy SOCKS5.", exception)
        }
    }

    private fun verifyLocalSocks5Ready(credentials: AuraSocks5Credentials) {
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
                    Socks5AuthProtocol.authenticate(
                        socket.getInputStream(),
                        socket.getOutputStream(),
                        credentials,
                    )
                }
                if (!TProxyService.TProxyIsRunning()) {
                    throw IOException("El proxy respondió, pero el motor VPN ya no está activo.")
                }
                return
            } catch (exception: Exception) {
                lastFailure = exception
                if (!TProxyService.TProxyIsRunning()) {
                    throw IOException(
                        "El motor VPN se detuvo antes de dejar listo el proxy local.",
                        exception,
                    )
                }
                Thread.sleep(100)
            }
        }
        throw IOException(
            "El proxy SOCKS5 local autenticado no quedo listo; tunel detenido.",
            lastFailure,
        )
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
        val stopIntent = Intent(this, AuraVpnService::class.java).setAction(ACTION_STOP)
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL)
            .setContentTitle("Aura Centinela")
            // Show the actual service state and DNS summary instead of a fixed
            // "active" claim while the tunnel may be degraded or isolated.
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Detener", stopPending)
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
