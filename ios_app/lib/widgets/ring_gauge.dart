import 'dart:math' as math;
import 'package:flutter/material.dart';

class RingGaugeWidget extends StatelessWidget {
  final double value; // 0.0 to 100.0
  final String title; // "CPU" or "RAM"
  final double size;
  final bool isDark;

  const RingGaugeWidget({
    super.key,
    required this.value,
    required this.title,
    this.size = 38.0,
    this.isDark = true,
  });

  Color _getArcColor() {
    if (value >= 85) return const Color(0xFFF87171); // Danger Red
    if (value >= 70) return const Color(0xFFFBBF24); // Warning Amber
    if (title.toUpperCase() == 'CPU') {
      return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7); // Sky Blue
    } else {
      return isDark ? const Color(0xFF34D399) : const Color(0xFF059669); // Emerald Green
    }
  }

  @override
  Widget build(BuildContext context) {
    final arcColor = _getArcColor();
    final clampedVal = value.clamp(0.0, 100.0);
    final valInt = clampedVal.toInt();

    // Responsive font sizing based on 100% vs 2 digits
    final fontSize = valInt >= 100 ? (size * 0.22) : (size * 0.27);
    final textColor = (valInt >= 70) ? arcColor : (isDark ? Colors.white : const Color(0xFF0F172A));

    return Tooltip(
      message: '$title: $valInt%',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                percent: clampedVal / 100.0,
                arcColor: arcColor,
                trackColor: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.black.withOpacity(0.08),
                strokeWidth: 2.8,
              ),
            ),
            // Bold centered percentage (CPU/RAM text omitted for maximum space)
            Text(
              '$valInt%',
              style: TextStyle(
                fontFamily: 'SF Pro Display',
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color arcColor;
  final Color trackColor;
  final double strokeWidth;

  _RingPainter({
    required this.percent,
    required this.arcColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    if (percent > 0) {
      final arcPaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * percent;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.arcColor != arcColor ||
        oldDelegate.trackColor != trackColor;
  }
}
