import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';
import 'aura_avatar.dart';
import 'aura_capability_ring.dart';

/// The center of the interface: Aura as a presence, not a dashboard card.
///
/// The avatar, its real capability arcs and the local-model state form one
/// continuous composition. Everything around it is either a live signal or a
/// controllable intent, never a square tile.
class AuraPresence extends StatelessWidget {
  const AuraPresence({
    super.key,
    required this.compact,
    required this.avatarMode,
    required this.model,
    required this.classifier,
    required this.defense,
    required this.statusLine,
    required this.aiStatusLabel,
    required this.aiStatusReady,
    required this.onAiStatusTap,
    required this.metrics,
  });

  final bool compact;
  final AuraAvatarMode avatarMode;
  final AuraCapabilityState model;
  final AuraCapabilityState classifier;
  final AuraCapabilityState defense;
  final String statusLine;
  final String aiStatusLabel;
  final bool aiStatusReady;
  final VoidCallback? onAiStatusTap;
  final List<String> metrics;

  @override
  Widget build(BuildContext context) {
    final ringSize = compact ? 118.0 : 168.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: ringSize + 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: ringSize * 1.72,
                height: ringSize * 1.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AuraTokens.accent.withValues(alpha: 0.12),
                      AuraTokens.accentViolet.withValues(alpha: 0.055),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.52, 1],
                  ),
                ),
              ),
              AuraCapabilityRing(
                size: ringSize,
                model: model,
                classifier: classifier,
                defense: defense,
                child: AuraAvatar(size: ringSize * 0.78, mode: avatarMode),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 10 : 18),
        const Text(
          'Hola, soy Aura.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AuraTokens.textPrimary,
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 7),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Text(
            statusLine,
            key: ValueKey<String>(statusLine),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AuraTokens.accent,
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          key: const ValueKey<String>('aura-ai-status'),
          onPressed: onAiStatusTap,
          style: TextButton.styleFrom(
            foregroundColor: aiStatusReady
                ? AuraTokens.success
                : AuraTokens.accentViolet,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 26),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            aiStatusReady ? Icons.verified_rounded : Icons.memory_rounded,
            size: 12,
          ),
          label: Text(
            aiStatusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.35,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 5,
          children: [
            _CapabilityGlyph(label: 'MODELO', state: model),
            _CapabilityGlyph(label: 'CLASIFICADOR', state: classifier),
            _CapabilityGlyph(label: 'ESCUDO', state: defense),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          metrics.join('   ·   '),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AuraTokens.textMuted,
            fontSize: 9.5,
            height: 1.5,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _CapabilityGlyph extends StatelessWidget {
  const _CapabilityGlyph({required this.label, required this.state});

  final String label;
  final AuraCapabilityState state;

  Color get _color => switch (state) {
    AuraCapabilityState.ready => AuraTokens.success,
    AuraCapabilityState.preparing => AuraTokens.warning,
    AuraCapabilityState.unavailable => AuraTokens.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _color.withValues(
              alpha: state == AuraCapabilityState.unavailable ? 0.45 : 0.95,
            ),
            boxShadow: state == AuraCapabilityState.ready
                ? [
                    BoxShadow(
                      color: _color.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: _color,
            fontSize: 7.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
