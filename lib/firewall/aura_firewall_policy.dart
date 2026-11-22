/// Per-app VPN policy. The native plan in AuraFirewallPlan.kt is what the
/// tunnel applies; this copy is the value stored in SecureVault and shown
/// in the UI, with the same limits.
enum AuraFirewallMode { normal, estricto }

class AuraFirewallPolicy {
  const AuraFirewallPolicy({
    this.mode = AuraFirewallMode.normal,
    this.bypass = const <String>[],
  });

  static const int maxPackages = 64;
  static final RegExp packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  final AuraFirewallMode mode;
  final List<String> bypass;

  static bool isPackageName(String value) => packagePattern.hasMatch(value);

  Map<String, Object> toJson() => <String, Object>{
    'mode': mode.name,
    'bypass': bypass,
  };

  static AuraFirewallPolicy parse(Map<String, dynamic> raw) {
    final mode = switch (raw['mode']) {
      'normal' => AuraFirewallMode.normal,
      'estricto' => AuraFirewallMode.estricto,
      'paranoico' => throw const FormatException(
        'Paranoico no se aplica: Android no permite una lista blanca y, a la vez, dejar a Aura fuera del túnel.',
      ),
      _ => throw const FormatException('Modo de firewall desconocido.'),
    };
    return AuraFirewallPolicy(mode: mode, bypass: _names(raw['bypass']));
  }

  /// Apps besides Aura that leave the tunnel. Estricto returns none.
  List<String> extraDisallowed(String selfPackage) {
    if (!isPackageName(selfPackage)) {
      throw const FormatException('El paquete de Aura no es válido.');
    }
    if (mode != AuraFirewallMode.normal) return const <String>[];
    return _distinct(bypass, selfPackage, false);
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

String auraFirewallModeTitle(AuraFirewallMode mode) => switch (mode) {
  AuraFirewallMode.normal => 'Normal',
  AuraFirewallMode.estricto => 'Estricto',
};

String auraFirewallModeDetail(AuraFirewallMode mode) => switch (mode) {
  AuraFirewallMode.normal =>
    'Casi todo entra al túnel y Aura lo filtra. Las apps que marques salen directas: no se filtran y tampoco se bloquean. Aura siempre queda fuera, para no enredar su propio tráfico.',
  AuraFirewallMode.estricto =>
    'Todo entra al túnel, salvo Aura. No se deja ninguna otra app fuera. Esto no apaga apps: las filtra.',
};
