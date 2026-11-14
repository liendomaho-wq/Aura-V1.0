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
    fun vpnDefaultUsesThePhysicalNetworkInstead() {
        val vpn = PublicNetworkFacts(
            isVpn = true,
            notVpn = false,
            wifi = false,
            cellular = false,
            internet = true,
            validated = true,
        )
        val wifi = PublicNetworkFacts(
            isVpn = false,
            notVpn = true,
            wifi = true,
            cellular = false,
            internet = true,
            validated = true,
        )
        assertEquals(
            UnderlyingNetworkKind.WIFI,
            UnderlyingNetworkKind.kindFor(vpn, listOf(vpn, wifi)),
        )
        assertEquals("WiFi", UnderlyingNetworkKind.label(UnderlyingNetworkKind.WIFI))
    }

    @Test
    fun noNetworkIsSinConexion() {
        assertEquals(
            UnderlyingNetworkKind.NONE,
            UnderlyingNetworkKind.kindFor(null, emptyList()),
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
