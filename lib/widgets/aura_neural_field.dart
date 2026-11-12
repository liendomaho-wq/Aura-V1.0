import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

/// The ambient state of Aura's local intelligence.
enum AuraNeuralMode { idle, listening, thinking, guarding, warning, alert }

/// A living neural field behind the whole interface.
///
/// It is intentionally not a panel or a grid: nodes, synapses and travelling
/// pulses represent the local model and the classifier working on-device. The
/// animation stops completely when the platform asks for reduced motion.
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
      duration: const Duration(seconds: 26),
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
    } else {
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
          painter: _NeuralFieldPainter(
            phase: _reduceMotion ? 0 : _controller.value,
            mode: widget.mode,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _NeuralFieldPainter extends CustomPainter {
  const _NeuralFieldPainter({required this.phase, required this.mode});

  final double phase;
  final AuraNeuralMode mode;

  Color get _primary => switch (mode) {
    AuraNeuralMode.idle => AuraTokens.accent,
    AuraNeuralMode.listening => AuraTokens.accentViolet,
    AuraNeuralMode.thinking => AuraTokens.accent,
    AuraNeuralMode.guarding => AuraTokens.success,
    AuraNeuralMode.warning => AuraTokens.warning,
    AuraNeuralMode.alert => AuraTokens.danger,
  };

  Color get _secondary => switch (mode) {
    AuraNeuralMode.idle => AuraTokens.accentViolet,
    AuraNeuralMode.listening => AuraTokens.accent,
    AuraNeuralMode.thinking => const Color(0xFFEAFBFF),
    AuraNeuralMode.guarding => AuraTokens.accent,
    AuraNeuralMode.warning => AuraTokens.danger,
    AuraNeuralMode.alert => AuraTokens.warning,
  };

  double get _energy => switch (mode) {
    AuraNeuralMode.idle => 0.55,
    AuraNeuralMode.listening => 1.15,
    AuraNeuralMode.thinking => 1.35,
    AuraNeuralMode.guarding => 0.8,
    AuraNeuralMode.warning => 1.0,
    AuraNeuralMode.alert => 1.5,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final center = Offset(size.width * 0.5, size.height * 0.34);

    final backdrop = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.5),
        radius: 1.25,
        colors: [
          _primary.withValues(alpha: 0.09 * _energy),
          _secondary.withValues(alpha: 0.035),
          AuraTokens.bg,
          const Color(0xFF02040A),
        ],
        stops: const [0, 0.38, 0.72, 1],
      ).createShader(rect);
    canvas.drawRect(rect, backdrop);

    final halo = Paint()
      ..shader =
          RadialGradient(
            colors: [
              _primary.withValues(alpha: 0.10 * _energy),
              _secondary.withValues(alpha: 0.05),
              Colors.transparent,
            ],
            stops: const [0, 0.5, 1],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.62),
          );
    canvas.drawCircle(center, size.shortestSide * 0.62, halo);

    _paintThreads(canvas, size, rect);
    _paintSynapses(canvas, size);
  }

  void _paintThreads(Canvas canvas, Size size, Rect rect) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _primary.withValues(alpha: 0.055);

    for (var i = 0; i < 4; i++) {
      final drift = math.sin(phase * math.pi * 2 + i * 1.4) * 22;
      final path = Path()
        ..moveTo(-20, size.height * (0.18 + i * 0.19))
        ..cubicTo(
          size.width * 0.28,
          size.height * (0.12 + i * 0.19) + drift,
          size.width * 0.68,
          size.height * (0.26 + i * 0.19) - drift,
          size.width + 20,
          size.height * (0.16 + i * 0.19),
        );
      canvas.drawPath(path, line);
    }

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _secondary.withValues(alpha: 0.06);
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.82, size.height * 0.1),
        radius: size.width * 0.34,
      ),
      math.pi * 0.35,
      math.pi * 1.15,
      false,
      arc,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.14, size.height * 0.82),
        radius: size.width * 0.3,
      ),
      math.pi * 1.1,
      math.pi * 0.9,
      false,
      arc,
    );
  }

  void _paintSynapses(Canvas canvas, Size size) {
    const count = 30;
    final nodes = <Offset>[];
    for (var i = 0; i < count; i++) {
      final base = i * 2.399963229728653;
      final speed = i.isEven ? 0.35 : -0.28;
      final angle = base + phase * math.pi * 2 * speed * 0.08;
      final radial = 0.22 + ((i * 41) % 100) / 100 * 0.62;
      final x = size.width * 0.5 + math.cos(angle) * size.width * 0.47 * radial;
      final y =
          size.height * 0.36 +
          math.sin(angle * 1.17 + phase * 0.6) * size.height * 0.5 * radial;
      if (x >= -8 && x <= size.width + 8 && y >= -8 && y <= size.height + 8) {
        nodes.add(Offset(x, y));
      }
    }

    if (nodes.isEmpty) return;

    final link = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = _primary.withValues(alpha: 0.075);
    final node = Paint()..color = _primary.withValues(alpha: 0.3);
    final bright = Paint()
      ..color = _secondary.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        if ((nodes[i] - nodes[j]).distance < 118) {
          canvas.drawLine(nodes[i], nodes[j], link);
        }
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      final pulse = 0.75 + 0.25 * math.sin(phase * math.pi * 6 + i);
      canvas.drawCircle(nodes[i], i % 7 == 0 ? 2.0 : 1.1, node);
      if (i % 7 == 0) {
        canvas.drawCircle(nodes[i], 2.4 * pulse, bright);
      }
    }

    final pulsePaint = Paint()
      ..color = _secondary.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);
    for (var i = 0; i < 5; i++) {
      final progress = (phase * 2 + i * 0.21) % 1;
      final from = nodes[(i * 5) % nodes.length];
      final to = nodes[(i * 5 + 3) % nodes.length];
      final point = Offset.lerp(from, to, progress);
      if (point != null) canvas.drawCircle(point, 1.9, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(_NeuralFieldPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.mode != mode;
}
