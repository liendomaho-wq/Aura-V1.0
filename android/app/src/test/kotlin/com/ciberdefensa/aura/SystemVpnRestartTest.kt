package com.ciberdefensa.aura

import org.junit.Assert.assertEquals
import org.junit.Test

class SystemVpnRestartTest {
    @Test
    fun ordinaryRestartStaysStopped() {
        assertEquals(
            SystemVpnRestart.Action.TEAR_DOWN,
            SystemVpnRestart.decide(alwaysOn = false, lockdown = false),
        )
    }

    @Test
    fun lockdownStartsInsteadOfSilentlyStopping() {
        assertEquals(
            SystemVpnRestart.Action.START_BECAUSE_LOCKDOWN,
            SystemVpnRestart.decide(alwaysOn = true, lockdown = true),
        )
        assertEquals(
            SystemVpnRestart.Action.START_BECAUSE_LOCKDOWN,
            SystemVpnRestart.decide(alwaysOn = false, lockdown = true),
        )
    }

    @Test
    fun alwaysOnWithoutLockdownNotifiesAndStaysDown() {
        assertEquals(
            SystemVpnRestart.Action.NOTIFY_AND_STAY_DOWN,
            SystemVpnRestart.decide(alwaysOn = true, lockdown = false),
        )
    }

    @Test
    fun explicitStopDuringLockdownWarnsAndKeepsTheShield() {
        assertEquals(
            SystemVpnRestart.ExplicitStop.WARN_AND_KEEP_RUNNING,
            SystemVpnRestart.decideExplicitStop(lockdown = true),
        )
        assertEquals(
            SystemVpnRestart.ExplicitStop.PERFORM_STOP,
            SystemVpnRestart.decideExplicitStop(lockdown = false),
        )
    }
}
