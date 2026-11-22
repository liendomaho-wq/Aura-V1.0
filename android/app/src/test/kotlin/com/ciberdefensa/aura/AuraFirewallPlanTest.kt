package com.ciberdefensa.aura

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AuraFirewallPlanTest {
    private val self = "com.ciberdefensa.aura"

    @Test
    fun normalBypassesChosenAppsButNeverTreatsAuraAsOptional() {
        assertEquals(
            listOf("com.example.browser"),
            AuraFirewallPlan.extraDisallowed(
                self,
                AuraFirewallPlan.Policy(
                    mode = AuraFirewallPlan.Mode.NORMAL,
                    bypass = setOf("com.example.browser", self, "not a package"),
                ),
            ),
        )
    }

    @Test
    fun estrictoIgnoresTheBypassList() {
        assertEquals(
            emptyList<String>(),
            AuraFirewallPlan.extraDisallowed(
                self,
                AuraFirewallPlan.Policy(
                    mode = AuraFirewallPlan.Mode.ESTRICTO,
                    bypass = setOf("com.example.browser"),
                ),
            ),
        )
    }

    @Test
    fun paranoicoIsRejectedBecauseAuraMustStayOutsideTheTunnel() {
        assertThrows(IllegalArgumentException::class.java) {
            AuraFirewallPlan.parse(mapOf("mode" to "paranoico"))
        }
    }
}
