package com.ciberdefensa.aura

import org.junit.Test

class VpnStartRequestGateTest {
    @Test
    fun rejectsUnrelatedAndStaleBroadcasts() {
        val gate = VpnStartRequestGate()
        check(gate.begin())
        check(gate.beginServiceRequest("first"))
        check(!gate.matchesServiceResponse(null))
        check(!gate.matchesServiceResponse("feed-update"))
        check(gate.matchesServiceResponse("first"))
        gate.finish()
        check(!gate.matchesServiceResponse("first"))
        check(gate.begin())
        check(gate.beginServiceRequest("second"))
        check(!gate.matchesServiceResponse("first"))
        check(gate.matchesServiceResponse("second"))
    }

    @Test
    fun onlyOneRequestCanBeActive() {
        val gate = VpnStartRequestGate()
        check(gate.begin())
        check(!gate.begin())
        check(!gate.beginServiceRequest(""))
        check(gate.beginServiceRequest("one"))
        check(!gate.beginServiceRequest("two"))
        check(!gate.beginConsent())
        gate.finish()
        check(gate.begin())
    }

    @Test
    fun cancelledConsentCannotStartOrResolveANewRequest() {
        val gate = VpnStartRequestGate()
        check(gate.begin())
        check(gate.beginConsent())
        check(gate.matchesConsent())
        check(!gate.beginServiceRequest("one"))
        gate.finish() // Consent timeout or explicit cancellation.
        check(!gate.matchesConsent())
        check(!gate.begin()) // The system dialog is still outstanding.
        check(!gate.consumeConsentResult())
        check(!gate.consumeConsentResult())
        check(gate.begin())
        check(gate.beginServiceRequest("two"))
        check(!gate.matchesServiceResponse("one"))
        check(gate.matchesServiceResponse("two"))
    }

    @Test
    fun acceptedConsentIsConsumedOnce() {
        val gate = VpnStartRequestGate()
        check(!gate.consumeConsentResult())
        check(gate.begin())
        check(gate.beginConsent())
        check(!gate.beginConsent())
        check(gate.consumeConsentResult())
        check(!gate.consumeConsentResult())
        check(gate.beginServiceRequest("one"))
        check(gate.matchesServiceResponse("one"))
    }

    @Test
    fun failedPermissionLaunchDoesNotBlockRetry() {
        val gate = VpnStartRequestGate()
        check(gate.begin())
        check(gate.beginConsent())
        gate.abandonConsent()
        gate.finish()
        check(gate.begin())
        check(gate.beginServiceRequest("retry"))
        check(gate.matchesServiceResponse("retry"))
    }
}

// Allows running the same assertions on a host JVM without an Android SDK.
fun main() {
    val tests = VpnStartRequestGateTest()
    tests.rejectsUnrelatedAndStaleBroadcasts()
    tests.onlyOneRequestCanBeActive()
    tests.cancelledConsentCannotStartOrResolveANewRequest()
    tests.acceptedConsentIsConsumedOnce()
    tests.failedPermissionLaunchDoesNotBlockRetry()
    println("PASS: 5 VPN start request gate tests")
}
