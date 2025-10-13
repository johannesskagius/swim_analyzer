import 'package:flutter/material.dart';

class TimelinePainter extends CustomPainter {
  final Duration totalDuration;
  final double pixelsPerSecond;
  final String Function(Duration) formatDuration;

  TimelinePainter({
    required this.totalDuration,
    required this.pixelsPerSecond,
    required this.formatDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // PERFORMANCE OPTIMIZATION: Calculate total ticks once.
    // Use `size.width` to avoid drawing ticks that are off-screen.
    final maxVisibleSeconds = size.width / pixelsPerSecond;
    final totalTicks = (maxVisibleSeconds * 10).ceil();

    for (int i = 0; i <= totalTicks; i++) {
      final xPos = (i / 10.0) * pixelsPerSecond;
      if (i % 10 == 0) {
        // Every full second
        canvas.drawLine(Offset(xPos, 10), Offset(xPos, size.height), tickPaint);
        textPainter.text = TextSpan(
          text: formatDuration(Duration(seconds: i ~/ 10)),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(xPos - (textPainter.width / 2), -5));
      } else {
        // Every 100 milliseconds
        canvas.drawLine(Offset(xPos, 25), Offset(xPos, size.height), tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) {
    return oldDelegate.totalDuration != totalDuration ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}