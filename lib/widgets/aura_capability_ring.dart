import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/aura_tokens.dart';

enum AuraCapabilityState { ready, preparing, unavailable }

/// Three real capability arcs around Aura's avatar: model, classifier and
/// defense. Each arc reflects a verified state; nothing here is decorative.
class AuraCapabilityRing extends StatefulWidget {
  const AuraCapabilityRing({
    super.key,
    required this.size,
    required this.model,
    required this.classifier,
    required this.defense,
    required this.child,
  });

  final double size;
  final AuraCapabilityState model;
  final AuraCapabilityState classifier;
  final AuraCapabilityState defense;
  final Widget child;

  @override
  State<AuraCapabilityRing> createState() => _AuraCapabilityRingState();
}

class _AuraCapabilityRingState extends State<AuraCapabilityRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _preparing =>
      widget.model == AuraCapabilityState.preparing ||
      widget.classifier == AuraCapabilityState.preparing ||
      widget.defense == AuraCapabilityState.preparing;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (_preparing) _controller.repeat();
  }

  @override
  void didUpdateWidget(AuraCapabilityRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preparing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_preparing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _CapabilityRingPainter(
            model: widget.model,
            classifier: widget.classifier,
            defense: widget.defense,
            rotation: reduceMotion ? 0 : _controller.value * math.pi * 2,
          ),
          child: child,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _CapabilityRingPainter extends CustomPainter {
  _CapabilityRingPainter({
    required this.model,
    required this.classifier,
    required this.defense,
    required this.rotation,
  });

  final AuraCapabilityState model;
  final AuraCapabilityState classifier;
  final AuraCapabilityState defense;
  final double rotation;

  static const double _span = math.pi * 0.44;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    _arc(
      canvas,
      center,
      base - 3.2,
      model,
      AuraTokens.accentViolet,
      -math.pi / 2,
    );
    _arc(
      canvas,
      center,
      base - 8.6,
      classifier,
      AuraTokens.accent,
      math.pi / 6,
    );
    _arc(
      canvas,
      center,
      base - 14.0,
      defense,
      AuraTokens.success,
      math.pi * 5 / 6,
    );
  }

  void _arc(
    Canvas canvas,
    Offset center,
    double radius,
    AuraCapabilityState state,
    Color color,
    double centerAngle,
  ) {
    if (radius <= 0) return;
    final start = centerAngle - _span / 2 + rotation * _speed(state);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = state == AuraCapabilityState.ready ? 2.6 : 1.8
      ..color = switch (state) {
        AuraCapabilityState.ready => color,
        AuraCapabilityState.preparing => color.withValues(alpha: 0.95),
        AuraCapabilityState.unavailable => color.withValues(alpha: 0.22),
      };
    if (state == AuraCapabilityState.unavailable) {
      _dashedArc(canvas, center, radius, start, _span, paint, 2, 5);
    } else if (state == AuraCapabilityState.preparing) {
      _dashedArc(canvas, center, radius, start, _span, paint, 7, 5);
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        _span,
        false,
        paint,
      );
    }
  }

  double _speed(AuraCapabilityState state) =>
      state == AuraCapabilityState.preparing ? 1 : 0;

  void _dashedArc(
    Canvas canvas,
    Offset center,
    double radius,
    double start,
    double span,
    Paint paint,
    double dashRadians,
    double gapRadians,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    var cursor = start;
    final end = start + span;
    while (cursor < end) {
      final segment = math.min(dashRadians, end - cursor);
      canvas.drawArc(rect, cursor, segment, false, paint);
      cursor += dashRadians + gapRadians;
    }
  }

  @override
  bool shouldRepaint(_CapabilityRingPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.classifier != classifier ||
      oldDelegate.defense != defense ||
      oldDelegate.rotation != rotation;
}
