import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

/// How the neural core should move, driven by a real app state.
enum AuraCoreVisualState { calm, alert, speaking, scanning }

/// Caps the sphere so a mid-range phone (TECNO POVA 5 class) keeps a steady
/// frame. Reduced motion and the smallest sizes draw fewer points.
int auraCoreParticleBudget({
  required double size,
  required bool reducedMotion,
}) {
  if (reducedMotion) return 12;
  if (size <= 48) return 10;
  if (size <= 96) return 16;
  if (size <= 160) return 24;
  return 36;
}

class _SpherePoint {
  const _SpherePoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

/// Even points on a unit sphere. Computed once, reused every frame.
final List<_SpherePoint> _spherePoints = _fibonacciSphere(36);

List<_SpherePoint> _fibonacciSphere(int count) {
  final phi = math.pi * (3 - math.sqrt(5));
  return List<_SpherePoint>.generate(count, (index) {
    final y = 1 - (index / (count - 1)) * 2;
    final ring = math.sqrt(math.max(0, 1 - y * y));
    final theta = phi * index;
    return _SpherePoint(math.cos(theta) * ring, y, math.sin(theta) * ring);
  }, growable: false);
}

/// Particle sphere, constellation lines and one liquid-chrome ribbon.
///
/// Painted with Flutter, not a video. The ribbon uses a gradient shader.
class AuraCorePainter extends CustomPainter {
  const AuraCorePainter({
    required this.phase,
    required this.state,
    required this.assemble,
    required this.particles,
  });

  final double phase;
  final AuraCoreVisualState state;
  final double assemble;
  final int particles;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final unit = size.shortestSide;
    final gather = assemble.clamp(0.0, 1.0);
    final turn = phase * math.pi * 2;
    final breathe = switch (state) {
      AuraCoreVisualState.calm => 0.96 + 0.045 * math.sin(turn),
      AuraCoreVisualState.alert => 0.70 + 0.028 * math.sin(turn),
      AuraCoreVisualState.speaking => 0.88 + 0.12 * math.sin(turn),
      AuraCoreVisualState.scanning => 0.97 + 0.03 * math.sin(turn * 2),
    };
    final spread = 1 + (1 - gather) * 1.65;
    final radius = unit * 0.30 * breathe * spread;
    final spin = turn * (state == AuraCoreVisualState.scanning ? 1 : 0.28);
    final primary = switch (state) {
      AuraCoreVisualState.calm => AuraTokens.accent,
      AuraCoreVisualState.alert => AuraTokens.alert,
      AuraCoreVisualState.speaking => AuraTokens.gold,
      AuraCoreVisualState.scanning => AuraTokens.accentViolet,
    };
    final secondary = state == AuraCoreVisualState.alert
        ? const Color(0xFFFF7AD4)
        : AuraTokens.accentViolet;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.34 * gather),
          secondary.withValues(alpha: 0.14 * gather),
          const Color(0x0003050C),
        ],
        stops: const [0, 0.42, 1],
      ).createShader(Rect.fromCircle(center: center, radius: unit * 0.48));
    canvas.drawCircle(center, unit * 0.48, glow);

    if (unit >= 96) {
      final starPaint = Paint();
      const stars = <Offset>[
        Offset(-0.42, -0.36),
        Offset(0.40, -0.30),
        Offset(-0.34, 0.28),
        Offset(0.36, 0.34),
        Offset(0.08, -0.46),
        Offset(-0.12, 0.44),
      ];
      for (var index = 0; index < stars.length; index++) {
        final twinkle = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(turn * 2 + index));
        starPaint.color = AuraTokens.chrome.withValues(
          alpha: 0.35 * twinkle * gather,
        );
        canvas.drawCircle(
          center + stars[index] * unit * 0.46,
          unit * (index.isEven ? 0.008 : 0.005),
          starPaint,
        );
      }
    }

    final count = particles.clamp(0, _spherePoints.length);
    final projected = List<_Projected>.generate(count, (index) {
      final point = _spherePoints[index];
      final x = point.x * math.cos(spin) + point.z * math.sin(spin);
      final z = -point.x * math.sin(spin) + point.z * math.cos(spin);
      final offset = Offset(
        center.dx + x * radius,
        center.dy + point.y * radius,
      );
      return _Projected(offset, z, index);
    }, growable: false);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, unit * 0.004)
      ..strokeCap = StrokeCap.round;
    for (final point in projected) {
      final next = projected[(point.index + 1) % count];
      final hop = projected[(point.index + 5) % count];
      for (final other in <_Projected>[next, if (point.index.isEven) hop]) {
        final depth = ((point.z + other.z) / 2).clamp(-1.0, 1.0);
        line.color = Color.lerp(
          primary,
          secondary,
          0.45,
        )!.withValues(alpha: (0.08 + 0.22 * (depth + 1) / 2) * gather);
        canvas.drawLine(point.offset, other.offset, line);
      }
    }

    final ordered = List<_Projected>.of(projected)
      ..sort((a, b) => a.z.compareTo(b.z));
    final dot = Paint();
    for (final point in ordered) {
      final depth = (point.z + 1) / 2;
      final color = Color.lerp(secondary, primary, depth)!;
      dot.color = color.withValues(alpha: (0.35 + 0.65 * depth) * gather);
      canvas.drawCircle(
        point.offset,
        math.max(0.8, unit * (0.008 + 0.008 * depth)),
        dot,
      );
    }

    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          AuraTokens.chrome.withValues(alpha: 0.95 * gather),
          primary.withValues(alpha: 0.9 * gather),
          secondary.withValues(alpha: 0.15 * gather),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.28));
    canvas.drawCircle(center, radius * 0.16, core);

    _paintRibbon(canvas, center, radius, unit, turn, gather, primary);
  }

  void _paintRibbon(
    Canvas canvas,
    Offset center,
    double radius,
    double unit,
    double turn,
    double gather,
    Color primary,
  ) {
    final wave = math.sin(turn);
    final path = Path()
      ..moveTo(center.dx - radius * 1.35, center.dy + radius * 0.42)
      ..cubicTo(
        center.dx - radius * 0.35,
        center.dy - radius * (0.95 + 0.18 * wave),
        center.dx + radius * 0.15,
        center.dy + radius * (1.05 - 0.12 * wave),
        center.dx + radius * 1.45,
        center.dy - radius * 0.22,
      );
    final bounds = Rect.fromCircle(center: center, radius: radius * 1.6);
    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.2, unit * 0.045)
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AuraTokens.chrome.withValues(alpha: 0.15 * gather),
          AuraTokens.chrome.withValues(alpha: 0.92 * gather),
          primary.withValues(alpha: 0.85 * gather),
          AuraTokens.accentViolet.withValues(alpha: 0.7 * gather),
          AuraTokens.chrome.withValues(alpha: 0.2 * gather),
        ],
      ).createShader(bounds);
    canvas.drawPath(path, ribbon);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.8, unit * 0.012)
        ..color = Colors.white.withValues(alpha: 0.55 * gather),
    );
  }

  @override
  bool shouldRepaint(AuraCorePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.state != state ||
        oldDelegate.assemble != assemble ||
        oldDelegate.particles != particles;
  }
}

class _Projected {
  const _Projected(this.offset, this.z, this.index);

  final Offset offset;
  final double z;
  final int index;
}

/// The living core. It breathes, contracts on alert, and pulses while Aura
/// speaks. Animation stops for reduced motion and while the app is paused.
class AuraNeuralCore extends StatefulWidget {
  const AuraNeuralCore({
    super.key,
    required this.state,
    this.size = 220,
    this.assemble = 1,
  });

  final AuraCoreVisualState state;
  final double size;
  final double assemble;

  @override
  State<AuraNeuralCore> createState() => _AuraNeuralCoreState();
}

class _AuraNeuralCoreState extends State<AuraNeuralCore>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _reducedMotion = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this, duration: _period)..repeat();
  }

  Duration get _period => switch (widget.state) {
    AuraCoreVisualState.calm => const Duration(milliseconds: 4200),
    AuraCoreVisualState.alert => const Duration(milliseconds: 1100),
    AuraCoreVisualState.speaking => const Duration(milliseconds: 780),
    AuraCoreVisualState.scanning => const Duration(milliseconds: 2400),
  };

  @override
  void didUpdateWidget(AuraNeuralCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    if (_controller.duration != _period) {
      _controller.duration = _period;
    }
    final freeze = _reducedMotion || _paused;
    if (freeze) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  String get _label => switch (widget.state) {
    AuraCoreVisualState.calm => 'Aura en calma',
    AuraCoreVisualState.alert => 'Aura en alerta',
    AuraCoreVisualState.speaking => 'Aura está hablando',
    AuraCoreVisualState.scanning => 'Aura está escaneando',
  };

  @override
  Widget build(BuildContext context) {
    final count = auraCoreParticleBudget(
      size: widget.size,
      reducedMotion: _reducedMotion,
    );
    return Semantics(
      container: true,
      image: true,
      label: _label,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: AuraCorePainter(
                phase: _reducedMotion ? 0 : _controller.value,
                state: widget.state,
                assemble: widget.assemble,
                particles: count,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
