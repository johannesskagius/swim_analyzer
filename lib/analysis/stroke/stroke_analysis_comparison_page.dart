
import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis_data.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class StrokeAnalysisComparisonPage extends StatelessWidget {
  final List<StrokeAnalysisData> analysisResults;

  const StrokeAnalysisComparisonPage({super.key, required this.analysisResults});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Comparison'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Metric')),
            ...analysisResults.map((res) => DataColumn(label: Text(res.intensity.name))),
          ],
          rows: [
            _createRow('Stroke', (data) => data.stroke.name),
            _createRow('Stroke Frequency', (data) => data.strokeFrequency.toStringAsFixed(1)),
            _createRow('Stroke Count', (data) => data.strokeTimestamps.length.toString()),
            // Add more rows for other metrics as needed
          ],
        ),
      ),
    );
  }

  DataRow _createRow(String title, String Function(StrokeAnalysisData) getValue) {
    return DataRow(
      cells: [
        DataCell(Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
        ...analysisResults.map((data) => DataCell(Text(getValue(data)))),
      ],
    );
  }
}
