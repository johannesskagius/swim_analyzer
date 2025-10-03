import 'package:flutter/material.dart';
import 'race_model.dart';

class ResultsPage extends StatelessWidget {
  final Map<CheckPoint, Duration> recordedTimes;
  final Map<CheckPoint, LapData> lapData;
  final Event event;

  const ResultsPage({
    super.key,
    required this.recordedTimes,
    required this.lapData,
    required this.event,
  });

  // Helper to format duration into a stopwatch-style string (e.g., "5.35s")
  String _formatDuration(Duration d) {
    final double seconds = d.inMilliseconds / 1000.0;
    return '${seconds.toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final startTime = recordedTimes[CheckPoint.start] ?? Duration.zero;
    final List<DataRow> rows = [];
    Duration previousTime = Duration.zero;

    // Use event.checkPoints as the source of truth for the order
    for (final checkPoint in event.checkPoints) {
      // Only show rows for checkpoints that have actually been recorded.
      if (recordedTimes.containsKey(checkPoint)) {
        final recordedTime = recordedTimes[checkPoint]!;
        final normalizedTime = recordedTime - startTime;
        final split = normalizedTime - previousTime;

        // --- Attribute and Frequency Logic ---
        final currentLapData = lapData[checkPoint];
        String strokeCount = '-';
        String breathCount = '-';
        String dolphinKickCount = '-';
        String strokeFrequency = '-';

        // Check if there is lap data for the checkpoint that ends this split
        if (currentLapData != null && split > Duration.zero) {
          strokeCount = currentLapData.strokeCount.toString();
          breathCount = currentLapData.breathCount.toString();
          dolphinKickCount = currentLapData.dolphinKickCount.toString();

          // Calculate Stroke Frequency (Strokes per Minute)
          if (currentLapData.strokeCount > 0) {
            final double splitInSeconds = split.inMilliseconds / 1000.0;
            final double strokesPerMinute =
                (currentLapData.strokeCount / splitInSeconds) * 60;
            strokeFrequency = strokesPerMinute.toStringAsFixed(1);
          }
        }
        // --- End Logic ---

        rows.add(DataRow(cells: [
          DataCell(Text(checkPoint.displayName)),
          DataCell(Text(_formatDuration(normalizedTime))),
          DataCell(Text(_formatDuration(split))),
          DataCell(Text(strokeCount)),
          DataCell(Text(breathCount)),
          DataCell(Text(dolphinKickCount)),
          DataCell(Text(strokeFrequency)),
        ]));

        previousTime = normalizedTime;
      }
    }

    return Scaffold(
      appBar: AppBar(
        // Use the event name in the title for better context
        title: Text('${event.name} Results'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(
                  label: Text('Checkpoint',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text('Time',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true),
              DataColumn(
                  label: Text('Split',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true),
              DataColumn(
                  label: Text('Strokes',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true),
              DataColumn(
                  label: Text('Breaths',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true),
              DataColumn(
                  label: Text('Dolphin Kicks',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true),
              DataColumn(
                  label: Text('Stroke Freq.',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true),
            ],
            rows: rows,
          ),
        ),
      ),
    );
  }
}