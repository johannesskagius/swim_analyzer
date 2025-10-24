import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class MeasurementPainter extends CustomPainter {
  final List<Offset> points;
  final int? selectedPointIndex;

  static const double pointRadius = 2.0;
  static const double handleYOffset = 30.0;
  static const double selectedPointRadius = 1.5;
  static const double handleTouchRadius = 20.0; // Increased visual touch area

  MeasurementPainter({required this.points, this.selectedPointIndex});

  static bool isPointHit(Offset position, Offset point) {
    // center of the handle, not the point itself
    final handleCenter = point + const Offset(0, handleYOffset);
    final hitRect =
        Rect.fromCircle(center: handleCenter, radius: handleTouchRadius);
    return hitRect.contains(position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    print(selectedPointIndex);

    final refLinePaint = Paint()
      ..color = Colors.blue.withAlpha(90)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final distLinePaint = Paint()
      ..color = Colors.red.withAlpha(90)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw reference lines (blue)
    if (points.length >= 2) canvas.drawLine(points[0], points[1], refLinePaint);
    if (points.length >= 4) canvas.drawLine(points[2], points[3], refLinePaint);

    // Draw distance line (red)
    if (points.length >= 6)
      canvas.drawLine(points[4], points[5], distLinePaint);

    // Draw points and handles on top
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final isSelected = i == selectedPointIndex;

      // Determine color based on type of point
      Color pointColor;
      if (i < 4) {
        pointColor = isSelected ? Colors.lightBlueAccent : Colors.blue;
      } else {
        pointColor = isSelected ? Colors.yellow : Colors.red;
      }

      final pointPaint = Paint()..color = pointColor;
      final outlinePaint = Paint()
        ..color = Colors.white.withAlpha(80)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final radius = isSelected ? selectedPointRadius : pointRadius;
      canvas.drawCircle(point, radius, pointPaint);
      canvas.drawCircle(point, radius, outlinePaint);

      // --- Handle Drawing ---
      final handleCenter = point + const Offset(0, handleYOffset);

      // Draw the semi-transparent touch area background
      final handleBgPaint = Paint()
        ..color = (isSelected
            ? Colors.yellow.withAlpha(30)
            : Colors.black87.withAlpha(80));
      canvas.drawCircle(handleCenter, handleTouchRadius, handleBgPaint);

      // Draw the icon on top
      final icon = FontAwesomeIcons.crosshairs;
      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            color: isSelected ? Colors.yellow : Colors.white,
            fontSize: 16,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

// Draw the icon
      final textOffset =
          point - Offset(textPainter.width / 2, textPainter.height / 2);
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant MeasurementPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedPointIndex != selectedPointIndex;
  }
}
