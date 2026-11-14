package com.ciberdefensa.aura

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Observes the device default network and reports the physical transport.
 * Once the VPN is up, the default network is often the tunnel itself; that
 * case is unwrapped to Wi-Fi or mobile data instead of being shown as the VPN.
 */
internal object AuraUnderlyingNetwork {
    private val listeners = CopyOnWriteArrayList<(Map<String, String>) -> Unit>()
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            publish()
        }

        override fun onLost(network: Network) {
            publish()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            publish()
        }
    }

    @Volatile private var appContext: Context? = null
    @Volatile private var callbackRegistered = false
    @Volatile private var latest: Map<String, String> = disconnected()

    fun addListener(listener: (Map<String, String>) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    fun removeListener(listener: (Map<String, String>) -> Unit) {
        listeners.remove(listener)
    }

    fun snapshot(): Map<String, String> = latest

    fun ensureStarted(context: Context) {
        val application = context.applicationContext
        appContext = application
        val connectivity = application.getSystemService(ConnectivityManager::class.java)
        if (connectivity == null) {
            publishDisconnected()
            return
        }
        if (!callbackRegistered) {
            try {
                connectivity.registerDefaultNetworkCallback(callback)
                callbackRegistered = true
            } catch (exception: Exception) {
                Log.w("AuraVPN", "No se pudo observar la red predeterminada.", exception)
            }
        }
        publish()
    }

    fun publish() {
        val connectivity = appContext?.getSystemService(ConnectivityManager::class.java)
        latest = if (connectivity == null) disconnected() else readSnapshot(connectivity)
        for (listener in listeners) {
            try {
                listener(latest)
            } catch (exception: Exception) {
                Log.w("AuraVPN", "No se pudo informar el tipo de red.", exception)
            }
        }
    }

    private fun publishDisconnected() {
        latest = disconnected()
        for (listener in listeners) {
            try {
                listener(latest)
            } catch (_: Exception) {
            }
        }
    }

    private fun readSnapshot(connectivity: ConnectivityManager): Map<String, String> {
        val network = connectivity.activeNetwork
        val capabilities = network?.let { connectivity.getNetworkCapabilities(it) }
        val others = connectivity.allNetworks.mapNotNull { candidate ->
            connectivity.getNetworkCapabilities(candidate)?.let(::factsOf)
        }
        val kind = UnderlyingNetworkKind.kindFor(
            capabilities?.let(::factsOf),
            others,
        )
        return mapOf(
            "kind" to kind,
            "label" to UnderlyingNetworkKind.label(kind),
        )
    }

    private fun factsOf(capabilities: NetworkCapabilities): PublicNetworkFacts {
        val vpn = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        val notVpn = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        return PublicNetworkFacts(
            isVpn = vpn || !notVpn,
            notVpn = notVpn,
            wifi = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
            cellular = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
            internet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
            validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
        )
    }

    private fun disconnected(): Map<String, String> = mapOf(
        "kind" to UnderlyingNetworkKind.NONE,
        "label" to UnderlyingNetworkKind.label(UnderlyingNetworkKind.NONE),
    )
}
