package com.ciberdefensa.aura

import org.junit.Assert.assertEquals
import org.junit.Test

class UnderlyingNetworkKindTest {
    @Test
    fun wifiIsReportedAheadOfCellular() {
        assertEquals(
            UnderlyingNetworkKind.WIFI,
            UnderlyingNetworkKind.fromTransports(
                isVpn = false,
                hasWifi = true,
                hasCellular = true,
                hasInternet = true,
            ),
        )
        assertEquals("WiFi", UnderlyingNetworkKind.label(UnderlyingNetworkKind.WIFI))
    }

    @Test
    fun cellularIsDatosMoviles() {
        assertEquals(
            UnderlyingNetworkKind.CELLULAR,
            UnderlyingNetworkKind.fromTransports(
                isVpn = false,
                hasWifi = false,
                hasCellular = true,
                hasInternet = true,
            ),
        )
        assertEquals(
            "Datos móviles",
            UnderlyingNetworkKind.label(UnderlyingNetworkKind.CELLULAR),
        )
    }

    @Test
    fun vpnTransportIsNotShownAsTheUserNetwork() {
        assertEquals(
            UnderlyingNetworkKind.NONE,
            UnderlyingNetworkKind.fromTransports(
                isVpn = true,
                hasWifi = true,
                hasCellular = false,
                hasInternet = true,
            ),
        )
        assertEquals("Sin conexión", UnderlyingNetworkKind.label(UnderlyingNetworkKind.NONE))
    }

    @Test
    fun noTransportIsDisconnected() {
        assertEquals(
            UnderlyingNetworkKind.NONE,
            UnderlyingNetworkKind.fromTransports(
                isVpn = false,
                hasWifi = false,
                hasCellular = false,
                hasInternet = false,
            ),
        )
    }
}
