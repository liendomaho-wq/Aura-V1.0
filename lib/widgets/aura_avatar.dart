import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Visual states are driven by real application state, never by a decorative
/// timer pretending that a security operation is running.
enum AuraAvatarMode { available, listening, analyzing, protecting, alert }

/// A lightweight animated identity for Aura. It is intentionally local:
/// no remote image, network request, or additional package is required.
class AuraAvatar extends StatefulWidget {
  const AuraAvatar({
    super.key,
    this.size = 112,
    this.isThinking = false,
    this.mode = AuraAvatarMode.available,
  });

  final double size;

  /// Backwards-compatible shorthand used by older screens and tests.
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
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
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: switch (widget.effectiveMode) {
        AuraAvatarMode.available => 'Aura está disponible',
        AuraAvatarMode.listening => 'Aura está escuchando',
        AuraAvatarMode.analyzing => 'Aura está analizando',
        AuraAvatarMode.protecting => 'Aura está protegiendo el dispositivo',
        AuraAvatarMode.alert => 'Aura detectó una alerta de seguridad',
      },
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _AuraAvatarPainter(
              phase: _controller.value,
              mode: widget.effectiveMode,
            ),
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  fontSize: widget.size * 0.38,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -3,
                  color: Colors.white.withValues(alpha: 0.96),
                  shadows: const [
                    Shadow(color: Color(0xFF00D9FF), blurRadius: 18),
                    Shadow(color: Color(0xFF765BFF), blurRadius: 28),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuraAvatarPainter extends CustomPainter {
  const _AuraAvatarPainter({required this.phase, required this.mode});

  final double phase;
  final AuraAvatarMode mode;

  Color get _primaryColor => switch (mode) {
        AuraAvatarMode.available => const Color(0xFF63E9FF),
        AuraAvatarMode.listening => const Color(0xFF8B70FF),
        AuraAvatarMode.analyzing => const Color(0xFF55DFFF),
        AuraAvatarMode.protecting => const Color(0xFF4ADEA5),
        AuraAvatarMode.alert => const Color(0xFFFF647C),
      };

  double get _motionMultiplier => switch (mode) {
        AuraAvatarMode.available => 0.55,
        AuraAvatarMode.listening => 0.9,
        AuraAvatarMode.analyzing => 1.8,
        AuraAvatarMode.protecting => 1.15,
        AuraAvatarMode.alert => 1.45,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.34;
    final pulseDepth = mode == AuraAvatarMode.alert ? 0.13 : 0.08;
    final pulse = 0.92 + pulseDepth * math.sin(phase * math.pi * 2);
    final rotation = phase * math.pi * 2;
    final primary = _primaryColor;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: mode == AuraAvatarMode.alert ? 0.32 : 0.24),
          const Color(0xFF6857FF).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 2.1));
    canvas.drawCircle(center, radius * 2.1, glow);

    final orb = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF182D58), Color(0xFF07182B), Color(0xFF30205E)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * pulse, orb);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = primary.withValues(alpha: 0.62);
    canvas.drawCircle(center, radius * (1.25 + 0.04 * math.sin(rotation)), ringPaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = (mode == AuraAvatarMode.alert
          ? const Color(0xFFFF9AA9)
          : const Color(0xFF9A80FF)).withValues(alpha: 0.72);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * _motionMultiplier);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: radius * 2.8, height: radius * 0.85),
      orbitPaint,
    );
    canvas.restore();

    final nodePaint = Paint()
      ..color = primary
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final nodeAngle = rotation * _motionMultiplier;
    final node = Offset(
      center.dx + math.cos(nodeAngle) * radius * 1.4,
      center.dy + math.sin(nodeAngle) * radius * 0.42,
    );
    canvas.drawCircle(node, size.shortestSide * 0.035, nodePaint);
  }

  @override
  bool shouldRepaint(covariant _AuraAvatarPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.mode != mode;
}
