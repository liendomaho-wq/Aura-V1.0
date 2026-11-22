package com.ciberdefensa.aura

/**
 * Decides which packages Android's VPN builder will allow or exclude.
 *
 * An excluded app is not filtered and is not blocked: its traffic leaves
 * directly. An allow-list app is the only traffic that enters the tunnel.
 * Android rejects mixing both calls on one builder, so a mode uses only one.
 * Aura itself stays outside the tunnel whenever the builder uses exclusions,
 * so its own sockets cannot loop back into the TUN.
 */
object AuraFirewallPlan {
    enum class Mode { NORMAL, ESTRICTO, PARANOICO }

    data class Policy(
        val mode: Mode = Mode.NORMAL,
        val bypass: Set<String> = emptySet(),
        val tunnelOnly: Set<String> = emptySet(),
    )

    data class Decision(
        val disallowed: List<String>,
        val allowed: List<String>,
    )

    private val packagePattern =
        Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")

    const val MAX_PACKAGES = 64

    fun isPackageName(value: String): Boolean = packagePattern.matches(value)

    fun decide(selfPackage: String, policy: Policy): Decision {
        if (!isPackageName(selfPackage)) {
            throw IllegalArgumentException("El paquete de Aura no es válido.")
        }
        return when (policy.mode) {
            Mode.NORMAL -> Decision(
                disallowed = distinctValid(listOf(selfPackage) + policy.bypass, selfPackage, keepSelf = true),
                allowed = emptyList(),
            )
            Mode.ESTRICTO -> Decision(
                disallowed = listOf(selfPackage),
                allowed = emptyList(),
            )
            Mode.PARANOICO -> {
                val allowed = distinctValid(policy.tunnelOnly.toList(), selfPackage, keepSelf = false)
                if (allowed.isEmpty()) {
                    throw IllegalArgumentException(
                        "Paranoico necesita al menos una app que entre al túnel.",
                    )
                }
                Decision(disallowed = emptyList(), allowed = allowed)
            }
        }
    }

    fun parse(raw: Map<*, *>): Policy {
        val mode = when (raw["mode"]) {
            "normal" -> Mode.NORMAL
            "estricto" -> Mode.ESTRICTO
            "paranoico" -> Mode.PARANOICO
            else -> throw IllegalArgumentException("Modo de firewall desconocido.")
        }
        return Policy(
            mode = mode,
            bypass = stringSet(raw["bypass"]),
            tunnelOnly = stringSet(raw["tunnelOnly"]),
        )
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

    private fun distinctValid(
        packages: List<String>,
        selfPackage: String,
        keepSelf: Boolean,
    ): List<String> {
        val seen = LinkedHashSet<String>()
        for (packageName in packages) {
            if (!isPackageName(packageName)) continue
            if (!keepSelf && packageName == selfPackage) continue
            seen.add(packageName)
        }
        if (keepSelf) seen.add(selfPackage)
        return seen.toList()
    }
}
