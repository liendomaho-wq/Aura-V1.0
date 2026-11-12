import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

/// The only persistent input surface: a single filament between the operator
/// and the local model. No filled bars, no rounded command box.
class AuraCommandFilament extends StatefulWidget {
  const AuraCommandFilament({
    super.key,
    required this.controller,
    required this.isListening,
    required this.isProcessing,
    required this.onSubmitted,
    required this.onVoice,
  });

  final TextEditingController controller;
  final bool isListening;
  final bool isProcessing;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onVoice;

  @override
  State<AuraCommandFilament> createState() => _AuraCommandFilamentState();
}

class _AuraCommandFilamentState extends State<AuraCommandFilament>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isListening || widget.isProcessing;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AuraTokens.bg.withValues(alpha: 0),
            AuraTokens.bg.withValues(alpha: 0.86),
            AuraTokens.bg,
          ],
          stops: const [0, 0.35, 1],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        14,
        10 + MediaQuery.paddingOf(context).bottom * 0.25,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AuraTokens.accent.withValues(alpha: 0.04),
                  AuraTokens.accent.withValues(alpha: active ? 0.5 : 0.22),
                  AuraTokens.accentViolet.withValues(alpha: 0.06),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _SignalPulse(
                animation: _pulse,
                active: active,
                listening: widget.isListening,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('aura-instruction-field'),
                  controller: widget.controller,
                  enabled: !widget.isProcessing,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) {
                    if (value.trim().isEmpty) return;
                    widget.controller.clear();
                    widget.onSubmitted(value.trim());
                  },
                  style: const TextStyle(
                    color: AuraTokens.textPrimary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.isListening
                        ? 'Te escucho…'
                        : 'Pedile algo a Aura…',
                    hintStyle: const TextStyle(
                      color: AuraTokens.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey<String>('voice-input-button'),
                onPressed: widget.isProcessing ? null : widget.onVoice,
                tooltip: widget.isListening
                    ? 'Detener micrófono'
                    : 'Hablar con Aura',
                icon: Icon(
                  widget.isListening
                      ? Icons.stop_circle_outlined
                      : Icons.graphic_eq_rounded,
                  color: widget.isListening
                      ? AuraTokens.accentViolet
                      : AuraTokens.textMuted,
                  size: 20,
                ),
              ),
              IconButton(
                key: const ValueKey<String>('send-instruction-button'),
                onPressed: widget.isProcessing
                    ? null
                    : () {
                        final value = widget.controller.text.trim();
                        if (value.isEmpty) return;
                        widget.controller.clear();
                        widget.onSubmitted(value);
                      },
                tooltip: 'Enviar a Aura',
                icon: const Icon(
                  Icons.arrow_upward_rounded,
                  color: AuraTokens.bg,
                  size: 18,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AuraTokens.accent,
                  minimumSize: const Size(38, 38),
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 18),
              child: Text(
                'AURA PROCESA EN TU DISPOSITIVO · TU CONSULTA NO SE ENVÍA',
                style: TextStyle(
                  color: AuraTokens.textMuted,
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.05,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPulse extends StatelessWidget {
  const _SignalPulse({
    required this.animation,
    required this.active,
    required this.listening,
  });

  final Animation<double> animation;
  final bool active;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = listening ? AuraTokens.accentViolet : AuraTokens.accent;
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final beat = reduceMotion || !active
              ? 0.72
              : 0.55 + 0.45 * (0.5 + 0.5 * _wave(animation.value));
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 18 * beat,
                height: 18 * beat,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28 * beat),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: active ? 0.95 : 0.45),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _wave(double t) {
    if (listening) {
      return (0.5 +
              0.5 * (0.6 * math.sin(t * 6) + 0.4 * math.sin(t * 11 + 0.7)))
          .clamp(0.0, 1.0);
    }
    return (0.5 + 0.5 * math.sin(t * 3)).clamp(0.0, 1.0);
  }
}
