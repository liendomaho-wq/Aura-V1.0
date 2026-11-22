package com.ciberdefensa.aura

/**
 * Extra packages that leave the tunnel directly. They are not filtered and
 * they are not blocked. Aura itself is always excluded by a separate,
 * unconditional call so its sockets cannot re-enter the TUN. Android rejects
 * mixing that exclusion with an allow-list, so this plan never calls
 * addAllowedApplication.
 */
object AuraFirewallPlan {
    enum class Mode { NORMAL, ESTRICTO }

    data class Policy(
        val mode: Mode = Mode.NORMAL,
        val bypass: Set<String> = emptySet(),
    )

    private val packagePattern =
        Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")

    const val MAX_PACKAGES = 64

    fun isPackageName(value: String): Boolean = packagePattern.matches(value)

    /** Packages besides Aura that Normal lets around the tunnel. Estricto returns none. */
    fun extraDisallowed(selfPackage: String, policy: Policy): List<String> {
        if (!isPackageName(selfPackage)) {
            throw IllegalArgumentException("El paquete de Aura no es válido.")
        }
        if (policy.mode != Mode.NORMAL) return emptyList()
        val seen = LinkedHashSet<String>()
        for (packageName in policy.bypass) {
            if (packageName == selfPackage || !isPackageName(packageName)) continue
            seen.add(packageName)
        }
        return seen.toList()
    }

    fun parse(raw: Map<*, *>): Policy {
        val mode = when (raw["mode"]) {
            "normal" -> Mode.NORMAL
            "estricto" -> Mode.ESTRICTO
            "paranoico" -> throw IllegalArgumentException(
                "Paranoico no se aplica: Android no permite una lista blanca y, a la vez, dejar a Aura fuera del túnel.",
            )
            else -> throw IllegalArgumentException("Modo de firewall desconocido.")
        }
        return Policy(mode = mode, bypass = stringSet(raw["bypass"]))
    }

    private fun stringSet(raw: Any?): Set<String> {
        if (raw == null) return emptySet()
        if (raw !is List<*>) throw IllegalArgumentException("La lista de apps no es válida.")
        if (raw.size > MAX_PACKAGES) {
            throw IllegalArgumentException("Hay demasiadas apps en la política.")
        }
        return raw.map { value ->
            if (value !is String || !isPackageName(value)) {
                throw IllegalArgumentException("Nombre de paquete no válido.")
            }
            value
        }.toSet()
    }
}
