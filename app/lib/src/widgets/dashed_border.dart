import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/app_shapes.dart';

/// Draws a dashed rounded-rectangle outline over [child] when [dashed] is true.
///
/// The outline is state shown by shape, not by colour or fading: it keeps the
/// child at full opacity, so its text keeps its contrast. The painter is
/// foreground-only and takes no layout space.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.dashed,
    required this.color,
    required this.child,
    this.radius = AppShapes.radiusMedium,
    this.strokeWidth = 2,
  });

  final bool dashed;
  final Color color;
  final double radius;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!dashed) return child;
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final inset = strokeWidth / 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );
    final dash = strokeWidth * 3;
    final gap = strokeWidth * 2;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}
