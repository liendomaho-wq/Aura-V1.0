package com.ciberdefensa.aura

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AuraFirewallPlanTest {
    private val self = "com.ciberdefensa.aura"

    @Test
    fun normalExcludesAuraAndChosenAppsButDoesNotAllowList() {
        val decision = AuraFirewallPlan.decide(
            self,
            AuraFirewallPlan.Policy(
                mode = AuraFirewallPlan.Mode.NORMAL,
                bypass = setOf("com.example.browser", self, "not a package"),
            ),
        )
        assertEquals(listOf(self, "com.example.browser"), decision.disallowed)
        assertEquals(emptyList<String>(), decision.allowed)
    }

    @Test
    fun estrictoIgnoresTheBypassList() {
        val decision = AuraFirewallPlan.decide(
            self,
            AuraFirewallPlan.Policy(
                mode = AuraFirewallPlan.Mode.ESTRICTO,
                bypass = setOf("com.example.browser"),
            ),
        )
        assertEquals(listOf(self), decision.disallowed)
        assertEquals(emptyList<String>(), decision.allowed)
    }

    @Test
    fun paranoicoAllowsOnlyChosenAppsAndNeverAura() {
        val decision = AuraFirewallPlan.decide(
            self,
            AuraFirewallPlan.Policy(
                mode = AuraFirewallPlan.Mode.PARANOICO,
                tunnelOnly = setOf("com.example.mail", self),
            ),
        )
        assertEquals(emptyList<String>(), decision.disallowed)
        assertEquals(listOf("com.example.mail"), decision.allowed)
    }

    @Test
    fun paranoicoWithoutAppsIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            AuraFirewallPlan.decide(
                self,
                AuraFirewallPlan.Policy(mode = AuraFirewallPlan.Mode.PARANOICO),
            )
        }
    }

    @Test
    fun parseRejectsAnUnknownMode() {
        assertThrows(IllegalArgumentException::class.java) {
            AuraFirewallPlan.parse(mapOf("mode" to "bloqueo"))
        }
    }
}
