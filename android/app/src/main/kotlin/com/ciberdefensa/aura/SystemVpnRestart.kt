package com.ciberdefensa.aura

/**
 * What to do when Android starts the VPN service again after the user
 * already stopped the shield.
 *
 * [TEAR_DOWN] is an ordinary sticky restart: stay stopped.
 * [START_BECAUSE_LOCKDOWN] must start. Lockdown with the VPN down leaves
 * the phone without a network and without an explanation.
 * [NOTIFY_AND_STAY_DOWN] is always-on without lockdown: do not silently
 * tear the tunnel down, and do not start it again without saying why.
 */
internal object SystemVpnRestart {
    enum class Action {
        TEAR_DOWN,
        START_BECAUSE_LOCKDOWN,
        NOTIFY_AND_STAY_DOWN,
    }

    fun decide(alwaysOn: Boolean, lockdown: Boolean): Action = when {
        lockdown -> Action.START_BECAUSE_LOCKDOWN
        alwaysOn -> Action.NOTIFY_AND_STAY_DOWN
        else -> Action.TEAR_DOWN
    }
}
