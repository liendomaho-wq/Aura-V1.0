import 'package:flutter/material.dart';

import '../voice_engine.dart';
import 'aura_neural_core.dart';

/// Activity states for Aura's abstract, non-human identity mark.
enum AuraAvatarMode {
  available,
  listening,
  analyzing,
  protecting,
  warning,
  alert,
}

/// Maps the avatar's real activity onto the neural-core motion.
AuraCoreVisualState auraCoreStateForAvatar({
  required AuraAvatarMode mode,
  required bool speaking,
}) {
  if (speaking) return AuraCoreVisualState.speaking;
  return switch (mode) {
    AuraAvatarMode.available ||
    AuraAvatarMode.protecting => AuraCoreVisualState.calm,
    AuraAvatarMode.listening => AuraCoreVisualState.speaking,
    AuraAvatarMode.analyzing => AuraCoreVisualState.scanning,
    AuraAvatarMode.warning || AuraAvatarMode.alert => AuraCoreVisualState.alert,
  };
}

class AuraAvatar extends StatefulWidget {
  const AuraAvatar({
    super.key,
    this.size = 112,
    this.isThinking = false,
    this.mode = AuraAvatarMode.available,
  });

  final double size;
  final bool isThinking;
  final AuraAvatarMode mode;

  AuraAvatarMode get effectiveMode =>
      isThinking ? AuraAvatarMode.analyzing : mode;

  @override
  State<AuraAvatar> createState() => _AuraAvatarState();
}

class _AuraAvatarState extends State<AuraAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
    AuraVoiceEngine.speaking.addListener(_onSpeaking);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncMotion();
  }

  @override
  void didUpdateWidget(AuraAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.isThinking != widget.isThinking) {
      _syncMotion();
    }
  }

  void _onSpeaking() {
    if (mounted) _syncMotion();
  }

  void _syncMotion() {
    final visual = auraCoreStateForAvatar(
      mode: widget.effectiveMode,
      speaking: AuraVoiceEngine.speaking.value,
    );
    final duration = switch (visual) {
      AuraCoreVisualState.calm => const Duration(milliseconds: 4200),
      AuraCoreVisualState.alert => const Duration(milliseconds: 1100),
      AuraCoreVisualState.speaking => const Duration(milliseconds: 780),
      AuraCoreVisualState.scanning => const Duration(milliseconds: 2400),
    };
    if (_controller.duration != duration) {
      _controller.duration = duration;
      if (_controller.isAnimating) {
        _controller
          ..stop()
          ..repeat();
      }
    }
    if (_reducedMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    AuraVoiceEngine.speaking.removeListener(_onSpeaking);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuraVoiceEngine.speaking,
      builder: (context, speaking, _) {
        final visual = auraCoreStateForAvatar(
          mode: widget.effectiveMode,
          speaking: speaking,
        );
        final count = auraCoreParticleBudget(
          size: widget.size,
          reducedMotion: _reducedMotion,
        );
        return Semantics(
          container: true,
          excludeSemantics: true,
          label: switch (widget.effectiveMode) {
            AuraAvatarMode.available => 'Aura está disponible',
            AuraAvatarMode.listening => 'Aura está escuchando',
            AuraAvatarMode.analyzing => 'Aura está analizando',
            AuraAvatarMode.protecting => 'Aura está protegiendo el dispositivo',
            AuraAvatarMode.warning =>
              'Aura detectó señales que requieren atención',
            AuraAvatarMode.alert => 'Aura detectó una alerta de seguridad',
          },
          image: true,
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: AuraCorePainter(
                  phase: _reducedMotion ? 0 : _controller.value,
                  state: visual,
                  assemble: 1,
                  particles: count,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
