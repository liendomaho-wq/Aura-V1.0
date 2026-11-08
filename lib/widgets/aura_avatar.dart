import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Activity states for Aura's abstract, non-human identity mark.
enum AuraAvatarMode {
  available,
  listening,
  analyzing,
  protecting,
  warning,
  alert,
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
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
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    label: switch (widget.effectiveMode) {
      AuraAvatarMode.available => 'Aura está disponible',
      AuraAvatarMode.listening => 'Aura está escuchando',
      AuraAvatarMode.analyzing => 'Aura está analizando',
      AuraAvatarMode.protecting => 'Aura está protegiendo el dispositivo',
      AuraAvatarMode.warning => 'Aura detectó señales que requieren atención',
      AuraAvatarMode.alert => 'Aura detectó una alerta de seguridad',
    },
    image: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _AuraCorePainter(
            phase: _controller.value,
            mode: widget.effectiveMode,
          ),
        ),
      ),
    ),
  );
}

/// Aura's own geometric A-core: luminous rails, data nodes and circuit traces.
/// It deliberately avoids human faces, shields, flowers and radar imagery.
class _AuraCorePainter extends CustomPainter {
  const _AuraCorePainter({required this.phase, required this.mode});

  final double phase;
  final AuraAvatarMode mode;

  Color get _primary => switch (mode) {
    AuraAvatarMode.available => const Color(0xFF39D9FF),
    AuraAvatarMode.listening => const Color(0xFFB36BFF),
    AuraAvatarMode.analyzing => const Color(0xFF40BFFF),
    AuraAvatarMode.protecting => const Color(0xFF39E6B0),
    AuraAvatarMode.warning => const Color(0xFFFFC45E),
    AuraAvatarMode.alert => const Color(0xFFFF557A),
  };

  Color get _secondary => mode == AuraAvatarMode.alert
      ? const Color(0xFFFF9BAE)
      : const Color(0xFF925BFF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final unit = size.shortestSide;
    final radius = unit * 0.30;
    final angle = phase * math.pi * 2;
    final pulse = 0.97 + 0.03 * math.sin(angle);
    final primary = _primary;
    final secondary = _secondary;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.28),
          secondary.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: unit * 0.49));
    canvas.drawCircle(center, unit * 0.49, glow);

    final trace = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, unit * 0.006)
      ..color = primary.withValues(alpha: 0.24);
    final outer = radius * 1.72;
    canvas.drawCircle(center, outer, trace);
    canvas.drawCircle(
      center,
      outer * 0.87,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, unit * 0.005)
        ..color = secondary.withValues(alpha: 0.24),
    );

    for (var i = 0; i < 12; i++) {
      final a = math.pi * 2 * i / 12 + angle * 0.035;
      final start = Offset(
        center.dx + math.cos(a) * outer * 1.03,
        center.dy + math.sin(a) * outer * 1.03,
      );
      final end = Offset(
        center.dx + math.cos(a) * outer * 1.22,
        center.dy + math.sin(a) * outer * 1.22,
      );
      canvas.drawLine(start, end, trace);
      canvas.drawCircle(
        end,
        unit * 0.012,
        Paint()..color = primary.withValues(alpha: 0.72),
      );
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      ring
        ..strokeWidth = math.max(1, unit * (0.012 - i * 0.002))
        ..color = (i.isEven ? primary : secondary).withValues(
          alpha: 0.72 - i * 0.14,
        );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * (1.32 + i * 0.19)),
        angle * (i.isEven ? 0.035 : -0.025) + i,
        math.pi * 1.42,
        false,
        ring,
      );
    }

    // Angular A monogram, built from luminous rails rather than a character.
    final r = radius * pulse;
    final left = Offset(center.dx - r * 0.72, center.dy + r * 0.62);
    final peak = Offset(center.dx, center.dy - r * 0.92);
    final right = Offset(center.dx + r * 0.72, center.dy + r * 0.62);
    final mark = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(peak.dx, peak.dy)
      ..lineTo(right.dx, right.dy);

    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = primary.withValues(alpha: 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.05);
    canvas.drawPath(mark, halo);

    final rails = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.064
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [primary, const Color(0xFFEAFBFF), secondary],
      ).createShader(Rect.fromPoints(left, right));
    canvas.drawPath(mark, rails);

    final crossbar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.052
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEAFBFF);
    canvas.drawLine(
      Offset(center.dx - r * 0.22, center.dy + r * 0.20),
      Offset(center.dx + r * 0.22, center.dy + r * 0.20),
      crossbar,
    );

    final dataAngle = angle * 0.22;
    final dataPoint = Offset(
      center.dx + math.cos(dataAngle) * outer * 1.12,
      center.dy + math.sin(dataAngle) * outer * 1.12,
    );
    canvas.drawCircle(
      dataPoint,
      unit * 0.022,
      Paint()
        ..color = primary
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.025),
    );
    canvas.drawCircle(dataPoint, unit * 0.009, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _AuraCorePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.mode != mode;
}
