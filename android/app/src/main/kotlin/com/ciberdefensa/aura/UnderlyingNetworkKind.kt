package com.ciberdefensa.aura

/**
 * Physical transport under the VPN, never the tunnel itself.
 * Wi-Fi wins when both radios are reported together.
 */
/**
 * One network as seen through public [android.net.NetworkCapabilities] flags.
 * [isVpn] is true when the transport is VPN or the network lacks NOT_VPN.
 */
internal data class PublicNetworkFacts(
    val isVpn: Boolean,
    val notVpn: Boolean,
    val wifi: Boolean,
    val cellular: Boolean,
    val internet: Boolean,
    val validated: Boolean,
)

internal object UnderlyingNetworkKind {
    const val WIFI = "wifi"
    const val CELLULAR = "cellular"
    const val NONE = "none"
    const val OTHER = "other"

    fun fromTransports(
        isVpn: Boolean,
        hasWifi: Boolean,
        hasCellular: Boolean,
        hasInternet: Boolean,
    ): String {
        if (isVpn) return NONE
        if (hasWifi) return WIFI
        if (hasCellular) return CELLULAR
        if (hasInternet) return OTHER
        return NONE
    }

    fun label(kind: String): String = when (kind) {
        WIFI -> "WiFi"
        CELLULAR -> "Datos móviles"
        OTHER -> "Otra red"
        else -> "Sin conexión"
    }

    /**
     * Picks the physical network using only public capability flags.
     * A VPN transport is never shown as the user's Wi-Fi or mobile data.
     * Among physical networks, validated Wi-Fi wins, then validated cellular.
     */
    fun choosePhysical(candidates: List<PublicNetworkFacts>): PublicNetworkFacts? {
        val physical = candidates.filter { !it.isVpn && it.notVpn && it.internet }
        return physical.firstOrNull { it.wifi && it.validated }
            ?: physical.firstOrNull { it.cellular && it.validated }
            ?: physical.firstOrNull { it.wifi }
            ?: physical.firstOrNull { it.cellular }
            ?: physical.firstOrNull()
    }

    fun kindFor(active: PublicNetworkFacts?, others: List<PublicNetworkFacts>): String {
        if (active == null) return NONE
        val chosen = if (active.isVpn || !active.notVpn) {
            choosePhysical(others)
        } else {
            active
        } ?: return NONE
        return fromTransports(
            isVpn = false,
            hasWifi = chosen.wifi,
            hasCellular = chosen.cellular,
            hasInternet = chosen.internet,
        )
    }
}
