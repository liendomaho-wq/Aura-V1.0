package com.ciberdefensa.aura

/**
 * One network as seen through public NetworkCapabilities flags.
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
     * Same order used by the VPN underlay and by the on-screen label.
     * Validated Wi-Fi, then validated cellular, then any physical network.
     * A VPN transport is never selected.
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
