/// Per-app VPN policy. The native plan in AuraFirewallPlan.kt is what the
/// tunnel applies; this copy is the value stored in SecureVault and shown
/// in the UI, with the same limits.
enum AuraFirewallMode { normal, estricto, paranoico }

class AuraFirewallPolicy {
  const AuraFirewallPolicy({
    this.mode = AuraFirewallMode.normal,
    this.bypass = const <String>[],
    this.tunnelOnly = const <String>[],
  });

  static const int maxPackages = 64;
  static final RegExp packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  final AuraFirewallMode mode;
  final List<String> bypass;
  final List<String> tunnelOnly;

  static bool isPackageName(String value) => packagePattern.hasMatch(value);

  Map<String, Object> toJson() => <String, Object>{
    'mode': mode.name,
    'bypass': bypass,
    'tunnelOnly': tunnelOnly,
  };

  static AuraFirewallPolicy parse(Map<String, dynamic> raw) {
    final mode = switch (raw['mode']) {
      'normal' => AuraFirewallMode.normal,
      'estricto' => AuraFirewallMode.estricto,
      'paranoico' => AuraFirewallMode.paranoico,
      _ => throw const FormatException('Modo de firewall desconocido.'),
    };
    return AuraFirewallPolicy(
      mode: mode,
      bypass: _names(raw['bypass']),
      tunnelOnly: _names(raw['tunnelOnly']),
    );
  }

  /// What Android will actually do. An empty paranoid list is refused.
  AuraFirewallDecision decide(String selfPackage) {
    if (!isPackageName(selfPackage)) {
      throw const FormatException('El paquete de Aura no es válido.');
    }
    switch (mode) {
      case AuraFirewallMode.normal:
        return AuraFirewallDecision(
          disallowed: _distinct(
            <String>[selfPackage, ...bypass],
            selfPackage,
            true,
          ),
          allowed: const <String>[],
        );
      case AuraFirewallMode.estricto:
        return AuraFirewallDecision(
          disallowed: <String>[selfPackage],
          allowed: const <String>[],
        );
      case AuraFirewallMode.paranoico:
        final allowed = _distinct(tunnelOnly, selfPackage, false);
        if (allowed.isEmpty) {
          throw const FormatException(
            'Paranoico necesita al menos una app que entre al túnel.',
          );
        }
        return AuraFirewallDecision(
          disallowed: const <String>[],
          allowed: allowed,
        );
    }
  }

  static List<String> _names(Object? raw) {
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw const FormatException('La lista de apps no es válida.');
    }
    if (raw.length > maxPackages) {
      throw const FormatException('Hay demasiadas apps en la política.');
    }
    return <String>[
      for (final value in raw)
        if (value is String && isPackageName(value)) value,
    ];
  }

  static List<String> _distinct(
    List<String> packages,
    String selfPackage,
    bool keepSelf,
  ) {
    final seen = <String>[];
    for (final packageName in packages) {
      if (!isPackageName(packageName)) continue;
      if (!keepSelf && packageName == selfPackage) continue;
      if (!seen.contains(packageName)) seen.add(packageName);
    }
    if (keepSelf && !seen.contains(selfPackage)) seen.insert(0, selfPackage);
    return seen;
  }
}

class AuraFirewallDecision {
  const AuraFirewallDecision({required this.disallowed, required this.allowed});

  final List<String> disallowed;
  final List<String> allowed;
}

String auraFirewallModeTitle(AuraFirewallMode mode) => switch (mode) {
  AuraFirewallMode.normal => 'Normal',
  AuraFirewallMode.estricto => 'Estricto',
  AuraFirewallMode.paranoico => 'Paranoico',
};

String auraFirewallModeDetail(AuraFirewallMode mode) => switch (mode) {
  AuraFirewallMode.normal =>
    'Casi todo entra al túnel y Aura lo filtra. Las apps que marques salen directas: no se filtran y tampoco se bloquean. Aura siempre queda fuera, para no enredar su propio tráfico.',
  AuraFirewallMode.estricto =>
    'Todo entra al túnel, salvo Aura. No se deja ninguna otra app fuera. Esto no apaga apps: las filtra.',
  AuraFirewallMode.paranoico =>
    'Solo las apps que marques entran al túnel y se filtran. Las demás no quedan bloqueadas: salen directas, sin Aura. Android no deja filtrar unas y cortar el resto a la vez.',
};
