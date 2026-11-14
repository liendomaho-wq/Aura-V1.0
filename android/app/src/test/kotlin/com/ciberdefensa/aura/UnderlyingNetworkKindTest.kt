package com.ciberdefensa.aura

import org.junit.Assert.assertEquals
import org.junit.Test

class UnderlyingNetworkKindTest {
    private fun physical(
        isVpn: Boolean = false,
        notVpn: Boolean? = null,
        wifi: Boolean = false,
        cellular: Boolean = false,
        internet: Boolean = true,
        validated: Boolean = false,
    ) = PublicNetworkFacts(
        isVpn,
        notVpn ?: !isVpn,
        wifi,
        cellular,
        internet,
        validated,
    )

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
    fun vpnWithoutAPhysicalNetworkIsDisconnected() {
        val vpn = physical(isVpn = true, notVpn = false, internet = true, validated = true)
        assertEquals(UnderlyingNetworkKind.NONE, UnderlyingNetworkKind.kindFor(vpn, emptyList()))
        assertEquals(null, UnderlyingNetworkKind.choosePhysical(listOf(vpn)))
    }

    @Test
    fun validatedCellularBeatsUnvalidatedWifi() {
        val wifi = physical(wifi = true, validated = false)
        val cellular = physical(cellular = true, validated = true)
        val chosen = UnderlyingNetworkKind.choosePhysical(listOf(wifi, cellular))
        assertEquals(cellular, chosen)
        assertEquals(
            UnderlyingNetworkKind.CELLULAR,
            UnderlyingNetworkKind.fromTransports(
                isVpn = false,
                hasWifi = chosen!!.wifi,
                hasCellular = chosen.cellular,
                hasInternet = chosen.internet,
            ),
        )
    }

    @Test
    fun validatedWifiAndCellularPickWifiForTunnelAndLabel() {
        val wifi = physical(wifi = true, validated = true)
        val cellular = physical(cellular = true, validated = true)
        val chosen = UnderlyingNetworkKind.choosePhysical(listOf(cellular, wifi))
        assertEquals(wifi, chosen)
        assertEquals(
            UnderlyingNetworkKind.WIFI,
            UnderlyingNetworkKind.fromTransports(
                isVpn = false,
                hasWifi = true,
                hasCellular = false,
                hasInternet = true,
            ),
        )
    }

    @Test
    fun activeNonVpnNetworkIsLabeledAsItself() {
        val cellular = physical(cellular = true, validated = true)
        val wifi = physical(wifi = true, validated = true)
        assertEquals(
            UnderlyingNetworkKind.CELLULAR,
            UnderlyingNetworkKind.kindFor(cellular, listOf(wifi)),
        )
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
