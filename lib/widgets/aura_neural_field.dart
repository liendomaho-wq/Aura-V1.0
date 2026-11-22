import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

/// The ambient state of Aura's local intelligence.
enum AuraNeuralMode { idle, listening, thinking, guarding, warning, alert }

/// Deep-space backdrop: a few stars, no grid and no radar.
///
/// Motion stops when the platform asks for reduced motion. Covered routes
/// pause it through [TickerMode].
class AuraNeuralField extends StatefulWidget {
  const AuraNeuralField({super.key, this.mode = AuraNeuralMode.idle});

  final AuraNeuralMode mode;

  @override
  State<AuraNeuralField> createState() => _AuraNeuralFieldState();
}

class _AuraNeuralFieldState extends State<AuraNeuralField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _StarfieldPainter(
            phase: _reduceMotion ? 0 : _controller.value,
            mode: widget.mode,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter({required this.phase, required this.mode});

  final double phase;
  final AuraNeuralMode mode;

  Color get _tint => switch (mode) {
    AuraNeuralMode.idle || AuraNeuralMode.guarding => AuraTokens.accent,
    AuraNeuralMode.listening ||
    AuraNeuralMode.thinking => AuraTokens.accentViolet,
    AuraNeuralMode.warning => AuraTokens.gold,
    AuraNeuralMode.alert => AuraTokens.alert,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.15,
          colors: [Color(0xFF10182E), Color(0xFF03050C)],
        ).createShader(rect),
    );
    final paint = Paint();
    const count = 28;
    for (var index = 0; index < count; index++) {
      final seed = index * 97.3;
      final x = (math.sin(seed) * 0.5 + 0.5) * size.width;
      final y = (math.cos(seed * 1.7) * 0.5 + 0.5) * size.height;
      final twinkle =
          0.15 + 0.45 * (0.5 + 0.5 * math.sin(phase * math.pi * 2 + index));
      paint.color = (index % 5 == 0 ? _tint : AuraTokens.chrome).withValues(
        alpha: twinkle * 0.55,
      );
      canvas.drawCircle(Offset(x, y), index.isEven ? 1.1 : 0.7, paint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.mode != mode;
  }
}
