import 'package:flutter/material.dart';

/// --- Custom Painter for the Audio Waveform ---
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double totalWidth;
  final Paint wavePaint;

  WaveformPainter({
    required this.waveformData,
    required this.totalWidth,
  }) : wavePaint = Paint()
    ..color = Colors.lightBlueAccent.withAlpha(90)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty || totalWidth <= 0) return;

    final middleY = size.height / 2;
    final samplesPerPixel = waveformData.length / totalWidth;
    final int width = size.width.toInt();

    // PERFORMANCE OPTIMIZATION: Pre-calculate min/max values for each pixel column.
    // This avoids creating sublists and iterating multiple times over the same data.
    final List<double> minValues = List.filled(width, 1.0);
    final List<double> maxValues = List.filled(width, -1.0);

    for (int i = 0; i < waveformData.length; i++) {
      final pixelIndex = (i / samplesPerPixel).floor();
      if (pixelIndex >= width) break;

      final sample = waveformData[i];
      if (sample < minValues[pixelIndex]) {
        minValues[pixelIndex] = sample;
      }
      if (sample > maxValues[pixelIndex]) {
        maxValues[pixelIndex] = sample;
      }
    }

    // Now, draw the lines based on the pre-calculated min/max values.
    for (int i = 0; i < width; i++) {
      final maxVal = maxValues[i];
      final minVal = minValues[i];

      if (minVal <= maxVal) {
        // Ensure there's a valid range to draw.
        final yMax = middleY - (maxVal * middleY);
        final yMin = middleY - (minVal * middleY);
        canvas.drawLine(
            Offset(i.toDouble(), yMin), Offset(i.toDouble(), yMax), wavePaint);
      }
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // PERFORMANCE OPTIMIZATION: Only repaint if the waveform data or width changes.
    // Using identity check for waveformData is fast and effective if the list is replaced, not mutated.
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.totalWidth != totalWidth;
  }
}