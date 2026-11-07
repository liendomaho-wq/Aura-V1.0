package com.ciberdefensa.aura

/**
 * Correlates one Activity request with its permission dialog and service reply.
 * All methods are called on the Activity's main thread. Finishing a request
 * does not forget an outstanding Android permission dialog: a new request must
 * wait for that dialog's result, even if the first request was cancelled.
 */
internal class VpnStartRequestGate {
    private var active = false
    private var consentPending = false
    private var requestId: String? = null

    fun begin(): Boolean {
        if (active || consentPending) return false
        active = true
        return true
    }

    fun beginConsent(): Boolean {
        if (!active || consentPending || requestId != null) return false
        consentPending = true
        return true
    }

    fun matchesConsent(): Boolean = active && consentPending && requestId == null

    fun consumeConsentResult(): Boolean {
        if (!consentPending) return false
        consentPending = false
        return active && requestId == null
    }

    fun abandonConsent() {
        consentPending = false
    }

    fun beginServiceRequest(id: String): Boolean {
        if (!active || consentPending || requestId != null || id.isBlank()) return false
        requestId = id
        return true
    }

    fun matchesServiceResponse(id: String?): Boolean =
        active && id != null && id == requestId

    fun finish() {
        active = false
        requestId = null
    }
}
