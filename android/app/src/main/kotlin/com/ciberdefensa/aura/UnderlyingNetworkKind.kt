package com.ciberdefensa.aura

/**
 * Physical transport under the VPN, never the tunnel itself.
 * Wi-Fi wins when both radios are reported together.
 */
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
}
