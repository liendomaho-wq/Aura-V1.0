import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

/// A transparent signal header. It carries the three controls that must remain
/// reachable at all times without becoming a toolbar panel.
class AuraSignalHeader extends StatelessWidget {
  const AuraSignalHeader({
    super.key,
    required this.compact,
    required this.showCoverageAudit,
    required this.onTelemetry,
    required this.onCoverageAudit,
    required this.isAuthenticated,
    required this.isShieldBusy,
    required this.shieldStatusKnown,
    required this.shieldServiceActive,
    required this.vpnActive,
    required this.onToggleShield,
  });

  final bool compact;
  final bool showCoverageAudit;
  final VoidCallback onTelemetry;
  final VoidCallback onCoverageAudit;
  final bool isAuthenticated;
  final bool isShieldBusy;
  final bool shieldStatusKnown;
  final bool shieldServiceActive;
  final bool vpnActive;
  final VoidCallback onToggleShield;

  @override
  Widget build(BuildContext context) {
    final vpnLabel = !shieldStatusKnown
        ? 'DEFENSA: ?'
        : vpnActive
        ? 'DEFENSA: ON'
        : shieldServiceActive
        ? 'DEFENSA: SIN FLUJO'
        : 'DEFENSA: OFF';
    final vpnColor = vpnActive
        ? AuraTokens.success
        : shieldStatusKnown
        ? AuraTokens.textMuted
        : AuraTokens.warning;

    return Padding(
      padding: EdgeInsets.fromLTRB(8, compact ? 2 : 6, 10, 2),
      child: Row(
        children: [
          _HeaderGlyph(
            icon: Icons.graphic_eq_rounded,
            label: 'Telemetría local',
            onTap: onTelemetry,
          ),
          _HeaderGlyph(
            key: const ValueKey<String>('coverage-audit-toggle'),
            icon: Icons.fact_check_outlined,
            label: 'Auditoría de cobertura',
            onTap: onCoverageAudit,
            highlighted: showCoverageAudit,
          ),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AURA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AuraTokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 6,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'NÚCLEO DE INTELIGENCIA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AuraTokens.accent,
                    fontSize: 6.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey<String>('vpn-toggle'),
            onPressed: isAuthenticated && !isShieldBusy && shieldStatusKnown
                ? onToggleShield
                : null,
            style: TextButton.styleFrom(
              foregroundColor: vpnColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isShieldBusy
                ? const SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: vpnColor.withValues(alpha: 0.9),
                          boxShadow: vpnActive
                              ? [
                                  BoxShadow(
                                    color: vpnColor.withValues(alpha: 0.45),
                                    blurRadius: 7,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        vpnLabel,
                        style: TextStyle(
                          color: vpnColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.55,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderGlyph extends StatelessWidget {
  const _HeaderGlyph({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      icon: Icon(icon, size: 17),
      color: highlighted ? AuraTokens.accent : AuraTokens.textMuted,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      splashRadius: 18,
    );
  }
}
