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

  /// Returns the distance marker string for a given checkpoint and its index.
  String _getDistance(CheckPoint checkPoint, int index) {
    if (checkPoint == CheckPoint.start) return '0m';

    if (checkPoint == CheckPoint.breakOut) {
      final startTime = recordedTimes[CheckPoint.start] ?? Duration.zero;
      final fifteenMeterTime = recordedTimes[CheckPoint.fifteenMeterMark];
      // Note: For multi-lap races, this will use the time from the LAST recorded breakout.
      final breakOutTime = recordedTimes[CheckPoint.breakOut];

      // This calculation is only accurate for the first breakout in a race
      // due to the current data model limitations for multi-lap races.
      final turnIndex = event.checkPoints.indexOf(CheckPoint.turn);
      bool isAfterTurn = turnIndex != -1 && index > turnIndex;

      if (isAfterTurn) {
        // We cannot accurately calculate breakouts after a turn with the current data structure.
        return 'Breakout';
      }

      if (fifteenMeterTime != null && breakOutTime != null) {
        final double durationTo15m = (fifteenMeterTime - startTime).inMilliseconds / 1000.0;
        if (durationTo15m <= 0) return 'Breakout'; // Avoid division by zero or nonsensical data.

        // Average speed to 15m (distance/time) -> m/s
        final double avgSpeed = 15.0 / durationTo15m;

        // Time from start to breakout
        final double durationToBreakout = (breakOutTime - startTime).inMilliseconds / 1000.0;

        // Estimated breakout distance = speed * time
        final double breakoutDistance = avgSpeed * durationToBreakout;

        return '~${breakoutDistance.toStringAsFixed(1)}m';
      }
      return 'Breakout'; // Fallback text if times are not available
    }


    // Logic for 100m Race (assumes 25m pool)
    if (event.name.startsWith('100m')) {
      switch (checkPoint) {
        case CheckPoint.turn:
          // This logic is flawed due to the data model. It can't distinguish between turns.
          // The best we can do is show a generic label. A better data model is needed.
          return 'Turn';
        case CheckPoint.finish:
          return '100m';
        case CheckPoint.fifteenMeterMark:
          // Differentiate 15m mark before and after the 50m turn.
          final turnIndex = event.checkPoints.indexOf(CheckPoint.turn);
          if (turnIndex != -1 && index > turnIndex) {
            return '65m'; // Assumption for 100m race
          }
          return '15m';
        default:
          return '-';
      }
    }

    // Default logic for 50m Race, as per your request.
    switch (checkPoint) {
      case CheckPoint.fifteenMeterMark:
        return '15m';
      case CheckPoint.turn:
        return '25m';
      case CheckPoint.finish:
        return '50m';
      default:
        return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final startTime = recordedTimes[CheckPoint.start] ?? Duration.zero;
    final List<DataRow> rows = [];
    Duration previousTime = Duration.zero;

    // Determine which columns to show based on the stroke
    final bool isBreaststroke = event.stroke == Stroke.breaststroke;

    // Dynamically build columns
    final List<DataColumn> columns = [
      const DataColumn(
          label: Text('Distance', style: TextStyle(fontWeight: FontWeight.bold))),
      const DataColumn(
          label: Text('Checkpoint', style: TextStyle(fontWeight: FontWeight.bold))),
      const DataColumn(
          label: Text('Time', style: TextStyle(fontWeight: FontWeight.bold)),
          numeric: true),
      const DataColumn(
          label: Text('Split', style: TextStyle(fontWeight: FontWeight.bold)),
          numeric: true),
      const DataColumn(
          label: Text('Strokes', style: TextStyle(fontWeight: FontWeight.bold)),
          numeric: true),
    ];

    if (!isBreaststroke) {
      columns.addAll([
        const DataColumn(
            label: Text('Breaths', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
        const DataColumn(
            label: Text('Dolphin Kicks', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true),
      ]);
    }
    columns.add(
      const DataColumn(
          label: Text('Stroke Freq.', style: TextStyle(fontWeight: FontWeight.bold)),
          numeric: true),
    );


    // Use a for-loop with an index to correctly calculate distances for all checkpoints.
    for (int i = 0; i < event.checkPoints.length; i++) {
      final checkPoint = event.checkPoints[i];

      // This is the core of the problem for 100m races. The map only contains one entry for CheckPoint.turn.
      if (recordedTimes.containsKey(checkPoint)) {
        final recordedTime = recordedTimes[checkPoint]!;
        final normalizedTime = recordedTime - startTime;
        final split = normalizedTime - previousTime;
        final distance = _getDistance(checkPoint, i);

        // --- Attribute and Frequency Logic ---
        final currentLapData = lapData[checkPoint];
        String strokeCount = '-';
        String breathCount = '-';
        String dolphinKickCount = '-';
        String strokeFrequency = '-';

        if (currentLapData != null && split > Duration.zero) {
          strokeCount = currentLapData.strokeCount.toString();
          if (!isBreaststroke) {
            breathCount = currentLapData.breathCount.toString();
            dolphinKickCount = currentLapData.dolphinKickCount.toString();
          }

          if (currentLapData.strokeCount > 0) {
            final double splitInSeconds = split.inMilliseconds / 1000.0;
            final double strokesPerMinute =
                (currentLapData.strokeCount / splitInSeconds) * 60;
            strokeFrequency = strokesPerMinute.toStringAsFixed(1);
          }
        }

        // Dynamically build cells for the row
        final List<DataCell> cells = [
          DataCell(Text(distance)),
          DataCell(Text(checkPoint.displayName)),
          DataCell(Text(_formatDuration(normalizedTime))),
          DataCell(Text(_formatDuration(split))),
          DataCell(Text(strokeCount)),
        ];

        if (!isBreaststroke) {
          cells.addAll([
            DataCell(Text(breathCount)),
            DataCell(Text(dolphinKickCount)),
          ]);
        }
        cells.add(DataCell(Text(strokeFrequency)));

        rows.add(DataRow(cells: cells));

        previousTime = normalizedTime;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${event.name} Results'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: columns,
            rows: rows,
          ),
        ),
      ),
    );
  }
}
