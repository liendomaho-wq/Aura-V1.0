import 'dart:math' as math;
import 'package:flutter/material.dart';


/// A lightweight animated identity for Aura. It is intentionally local:
/// no remote image, network request, or additional package is required.
class AuraAvatar extends StatefulWidget {
  const AuraAvatar({
    super.key,
    this.size = 112,
    this.isThinking = false,
  });

  final double size;
  final bool isThinking;

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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.isThinking ? 'Aura está analizando' : 'Aura está disponible',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _AuraAvatarPainter(
            phase: _controller.value,
            thinking: widget.isThinking,
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
  const _AuraAvatarPainter({required this.phase, required this.thinking});

  final double phase;
  final bool thinking;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.34;
    final pulse = 0.92 + 0.08 * math.sin(phase * math.pi * 2);
    final rotation = phase * math.pi * 2;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00D9FF).withValues(alpha: 0.24),
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
      ..color = const Color(0xFF63E9FF).withValues(alpha: 0.55);
    canvas.drawCircle(center, radius * (1.25 + 0.04 * math.sin(rotation)), ringPaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF9A80FF).withValues(alpha: 0.72);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * (thinking ? 1.8 : 0.55));
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: radius * 2.8, height: radius * 0.85),
      orbitPaint,
    );
    canvas.restore();

    final nodePaint = Paint()
      ..color = const Color(0xFF72F5FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final nodeAngle = rotation * (thinking ? 2.0 : 0.7);
    final node = Offset(
      center.dx + math.cos(nodeAngle) * radius * 1.4,
      center.dy + math.sin(nodeAngle) * radius * 0.42,
    );
    canvas.drawCircle(node, size.shortestSide * 0.035, nodePaint);
  }

  @override
  bool shouldRepaint(covariant _AuraAvatarPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.thinking != thinking;
}
