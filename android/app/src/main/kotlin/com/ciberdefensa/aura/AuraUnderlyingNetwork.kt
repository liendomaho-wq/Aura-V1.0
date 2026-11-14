package com.ciberdefensa.aura

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Reports the physical network the user should see.
 *
 * Aura's own process is excluded from its tunnel, so the default network here
 * is already the physical one. While the tunnel is up, the label uses the
 * network AuraVpnService actually passed to setUnderlyingNetworks.
 */
internal object AuraUnderlyingNetwork {
    private val listeners = CopyOnWriteArrayList<(Map<String, String>) -> Unit>()
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val capabilities = appContext
                ?.getSystemService(ConnectivityManager::class.java)
                ?.getNetworkCapabilities(network)
            if (capabilities != null) defaultFacts = networkFacts(capabilities)
            publish()
        }

        override fun onLost(network: Network) {
            defaultFacts = null
            publish()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            defaultFacts = networkFacts(networkCapabilities)
            publish()
        }
    }

    @Volatile private var appContext: Context? = null
    @Volatile private var callbackRegistered = false
    @Volatile private var defaultFacts: PublicNetworkFacts? = null
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
        latest = labelFor(
            factsForLabel(
                tunnelUp = AuraVpnService.isTunnelInterfaceUp(),
                applied = AuraVpnService.appliedUnderlyingFacts(),
                fallback = defaultFacts,
            ),
        )
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

    private fun labelFor(facts: PublicNetworkFacts?): Map<String, String> {
        val kind = UnderlyingNetworkKind.kindFor(facts, emptyList())
        return mapOf(
            "kind" to kind,
            "label" to UnderlyingNetworkKind.label(kind),
        )
    }

    private fun disconnected(): Map<String, String> = mapOf(
        "kind" to UnderlyingNetworkKind.NONE,
        "label" to UnderlyingNetworkKind.label(UnderlyingNetworkKind.NONE),
    )
}

internal fun networkFacts(capabilities: NetworkCapabilities): PublicNetworkFacts {
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
