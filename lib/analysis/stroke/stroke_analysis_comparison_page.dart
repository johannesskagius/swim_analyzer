import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis.dart';

class StrokeAnalysisComparisonPage extends StatelessWidget {
  final List<StrokeAnalysis> analyses;

  const StrokeAnalysisComparisonPage({super.key, required this.analyses});

  @override
  Widget build(BuildContext context) {
    if (analyses.length < 3) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analysis Comparison')),
        body: const Center(
          child: Text('At least 3 analyses with different intensities are required.'),
        ),
      );
    }

    final sorted = List.of(analyses)
      ..sort((a, b) => a.intensity.index.compareTo(b.intensity.index));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stroke Analysis Comparison'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Show chart info',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // -----------------------------------
          // PERFORMANCE CHART
          // -----------------------------------
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildPerformanceChart(sorted),
                ),
              ),
            ),
          ),
          const Divider(),

          // -----------------------------------
          // DATA TABLE
          // -----------------------------------
          Expanded(
            flex: 3,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(16.0),
                  child: DataTable(
                    columnSpacing: 24,
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                    columns: [
                      const DataColumn(label: Text('Metric')),
                      ...sorted.map(
                            (r) => DataColumn(label: Text(r.intensity.name)),
                      ),
                    ],
                    rows: [
                      _createRow('Stroke', (r) => r.stroke.name, sorted),
                      _createRow('Speed (m/s)',
                              (r) => (r.averageSpeed ?? 0).toStringAsFixed(2), sorted),
                      _createRow('Stroke Frequency (Hz)',
                              (r) => r.strokeFrequency.toStringAsFixed(2), sorted),
                      _createRow('Stroke Length (m/st)',
                              (r) => r.strokeLength.toStringAsFixed(2), sorted),
                      _createRow('Efficiency Index',
                              (r) => r.efficiencyIndex.toStringAsFixed(2), sorted),
                      _createRow('Underwater Distance (m)',
                              (r) => r.underwaterDistance.toStringAsFixed(2), sorted),
                      _createRow('Underwater Time (s)',
                              (r) => r.underwaterTime.toStringAsFixed(2), sorted),
                      _createRow('Underwater Velocity (m/s)',
                              (r) => r.underwaterVelocity.toStringAsFixed(2), sorted),
                      _createRow('Cycle Time (s)',
                              (r) => r.cycleTime.toStringAsFixed(2), sorted),
                      _createRow('Stroke Count',
                              (r) => r.strokeTimestamps.length.toString(), sorted),
                      _createRow('Start Reaction (s)',
                              (r) => r.startReaction.toStringAsFixed(2), sorted),
                      _createRow('Turn Time (s)',
                              (r) => r.turnTime.toStringAsFixed(2), sorted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // CHART
  // --------------------------------------------------
  Widget _buildPerformanceChart(List<StrokeAnalysis> sorted) {
    final intensities = sorted.map((r) => r.intensity.name).toList();

    final speeds = sorted.map((r) => r.averageSpeed ?? 0).toList();
    final freqs = sorted.map((r) => r.strokeFrequency).toList();
    final lengths = sorted.map((r) => r.strokeLength).toList();
    final efficiency = sorted.map((r) => r.efficiencyIndex).toList();

    final maxSpeed = speeds.reduce(math.max);
    final minSpeed = speeds.reduce(math.min);

    // Scale all secondary metrics into same Y range as speed for readability
    double scaleToSpeed(double value, double metricMax, double metricMin) {
      if ((metricMax - metricMin).abs() < 1e-6) return speeds.first;
      return minSpeed +
          ((value - metricMin) / (metricMax - metricMin)) *
              (maxSpeed - minSpeed);
    }

    final scaledFreqs = _scaleList(freqs, minSpeed, maxSpeed);
    final scaledLengths = _scaleList(lengths, minSpeed, maxSpeed);
    final scaledEff = _scaleList(efficiency, minSpeed, maxSpeed);

    return LineChart(
      LineChartData(
        minY: minSpeed * 0.95,
        maxY: maxSpeed * 1.05,
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text("Speed (m/s)"),
            axisNameSize: 20,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (val, _) =>
                  Text(val.toStringAsFixed(2), style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (x, _) {
                final i = x.toInt();
                return (i >= 0 && i < intensities.length)
                    ? Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(intensities[i],
                      style: const TextStyle(fontSize: 10)),
                )
                    : const SizedBox();
              },
            ),
          ),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 8,
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              return LineTooltipItem(
                "${intensities[i]}\n"
                    "Speed: ${speeds[i].toStringAsFixed(2)} m/s\n"
                    "Freq: ${freqs[i].toStringAsFixed(2)} Hz\n"
                    "Length: ${lengths[i].toStringAsFixed(2)} m/st\n"
                    "Eff.: ${efficiency[i].toStringAsFixed(2)}",
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          _buildLine(speeds, Colors.green, width: 4),
          _buildLine(scaledFreqs, Colors.orange, width: 3, dashArray: [6, 4]),
          _buildLine(scaledLengths, Colors.blue, width: 3, dashArray: [2, 4]),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // UTILITIES
  // --------------------------------------------------
  List<double> _scaleList(List<double> list, double minY, double maxY) {
    if (list.isEmpty) return [];
    final minVal = list.reduce(math.min);
    final maxVal = list.reduce(math.max);
    if ((maxVal - minVal).abs() < 1e-6) {
      return List.filled(list.length, (minY + maxY) / 2);
    }
    return list
        .map((v) => minY + ((v - minVal) / (maxVal - minVal)) * (maxY - minY))
        .toList();
  }

  LineChartBarData _buildLine(List<double> values, Color color,
      {double width = 3, List<int>? dashArray}) {
    return LineChartBarData(
      isCurved: true,
      color: color,
      barWidth: width,
      dashArray: dashArray,
      isStrokeCapRound: true,
      dotData: FlDotData(show: true),
      belowBarData: BarAreaData(show: false),
      spots: [
        for (int i = 0; i < values.length; i++)
          FlSpot(i.toDouble(), values[i]),
      ],
    );
  }

  DataRow _createRow(
      String title, String Function(StrokeAnalysis) getValue, List<StrokeAnalysis> data) {
    return DataRow(
      cells: [
        DataCell(Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
        ...data.map((r) {
          final value = getValue(r);
          return DataCell(Text(value.isEmpty ? '-' : value));
        }),
      ],
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Chart Information"),
        content: const Text(
          "This chart shows Speed (m/s) on the Y-axis.\n\n"
              "Stroke Frequency, Stroke Length, and Efficiency Index "
              "are rescaled to fit the same axis range for visual comparison.\n\n"
              "Green = Speed, Orange = Frequency, Blue = Stroke Length.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
