import 'package:flutter/material.dart';

/// CustomPainter Timeline Ruler drawing dynamic timestamp ticks (0s, 2s, 4s...)
/// matching the dddd.PNG design mockup.
class TimelineRuler extends StatelessWidget {
  final double totalDurationMs;
  final double zoomScale; // Pixels per ms
  final double width;
  final double paddingLeft;

  const TimelineRuler({
    super.key,
    required this.totalDurationMs,
    required this.zoomScale,
    required this.width,
    this.paddingLeft = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, 28),
      painter: _TimelineRulerPainter(
        totalDurationMs: totalDurationMs,
        zoomScale: zoomScale,
        paddingLeft: paddingLeft,
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  final double totalDurationMs;
  final double zoomScale;
  final double paddingLeft;

  _TimelineRulerPainter({
    required this.totalDurationMs,
    required this.zoomScale,
    required this.paddingLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.0;

    final subTickPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.8;

    double majorIntervalMs = 2000.0; // Every 2s by default matching mockup (0s, 2s, 4s, 6s)
    int subTickCount = 4;

    final pxPerSec = zoomScale * 1000.0;
    if (pxPerSec < 20) {
      majorIntervalMs = 5000.0; // Every 5s
    } else if (pxPerSec < 40) {
      majorIntervalMs = 2000.0; // Every 2s
    } else if (pxPerSec > 150) {
      majorIntervalMs = 1000.0; // Every 1s
    }

    final subIntervalMs = majorIntervalMs / subTickCount;

    for (double timeMs = 0; timeMs <= totalDurationMs; timeMs += subIntervalMs) {
      final x = paddingLeft + (timeMs * zoomScale);
      if (x < 0 || x > size.width) continue;

      final isMajor = (timeMs % majorIntervalMs).abs() < 0.001;

      if (isMajor) {
        // Draw Major Tick
        canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height), linePaint);

        // Draw Timestamp Label (0s, 2s, 4s...)
        final timeText = _formatTimestamp(timeMs);
        final textPainter = TextPainter(
          text: TextSpan(
            text: timeText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - 25));
      } else {
        // Draw Minor Sub-tick
        canvas.drawLine(Offset(x, size.height - 5), Offset(x, size.height), subTickPaint);
      }
    }
  }

  String _formatTimestamp(double timeMs) {
    final seconds = (timeMs / 1000.0).round();
    return '${seconds}s';
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.totalDurationMs != totalDurationMs ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.paddingLeft != paddingLeft;
  }
}
