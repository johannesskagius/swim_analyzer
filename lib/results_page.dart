import 'package:flutter/material.dart';
import 'dart:math';

import 'race_model.dart';

class ResultsPage extends StatelessWidget {
  final List<RaceSegment> recordedSegments;
  final List<LapData> lapData;
  final Event event;

  const ResultsPage({
    super.key,
    required this.recordedSegments,
    required this.lapData,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    String breakoutNote = '';
    final rows = <DataRow>[];
    Duration? lastTime;
    int lapIndex = 0;

    // Get the start time for split calculations
    final startTime = recordedSegments
        .firstWhere((s) => s.checkPoint == CheckPoint.start, orElse: () => recordedSegments.first)
        .time;

    for (int i = 0; i < recordedSegments.length; i++) {
      final segment = recordedSegments[i];
      final isBreaststroke = event.stroke == Stroke.breaststroke;

      final distanceData = _getDistance(segment.checkPoint, i, recordedSegments, event);
      if (distanceData.isEstimated) {
        breakoutNote = '* Breakout distance estimated to be ${distanceData.distance}';
      }

      final splitTime = segment.time - startTime;
      final lapTime = lastTime != null ? segment.time - lastTime! : splitTime;

      final lapAttributes = (lapIndex < lapData.length) ? lapData[lapIndex] : null;

      // Build the cells for this row
      final cells = <DataCell>[
        DataCell(Text(distanceData.distance)),
        DataCell(Text(_formatDuration(lapTime))),
        DataCell(Text(_formatDuration(splitTime))),
      ];

      if (lapAttributes != null) {
        final strokeFreq = _calculateStrokeFrequency(lapTime, lapAttributes.strokeCount);
        if (!isBreaststroke) {
          cells.add(DataCell(Text(lapAttributes.dolphinKickCount.toString())));
        }
        cells.add(DataCell(Text(lapAttributes.strokeCount.toString())));
        if (!isBreaststroke) {
          cells.add(DataCell(Text(lapAttributes.breathCount.toString())));
        }
        cells.add(DataCell(Text(strokeFreq)));
      }

      rows.add(DataRow(cells: cells));

      // After a turn or finish, the next checkpoint starts a new lap timing context.
      if (segment.checkPoint == CheckPoint.turn || segment.checkPoint == CheckPoint.finish) {
        lastTime = segment.time;
        lapIndex++;
      }
    }

    final columns = <DataColumn>[
      const DataColumn(label: Text('Distance')),
      const DataColumn(label: Text('Lap Time')),
      const DataColumn(label: Text('Split Time')),
    ];

    if (event.stroke != Stroke.breaststroke) {
      columns.add(const DataColumn(label: Text('Dolphin Kicks')));
    }
    columns.add(const DataColumn(label: Text('Strokes')));
    if (event.stroke != Stroke.breaststroke) {
      columns.add(const DataColumn(label: Text('Breaths')));
    }
    columns.add(const DataColumn(label: Text('Stroke Freq.')));

    return Scaffold(
      appBar: AppBar(
        title: Text('${event.name} Results'),
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: columns,
                  rows: rows,
                ),
              ),
              if (breakoutNote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    breakoutNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    return d.toString().substring(2, 11); // Format as 00:00.000000
  }

  String _calculateStrokeFrequency(Duration lapTime, int strokeCount) {
    if (strokeCount == 0 || lapTime.inMilliseconds == 0) return 'N/A';
    final double strokesPerSecond = strokeCount / lapTime.inSeconds;
    return strokesPerSecond.toStringAsFixed(2);
  }

  _DistanceData _getDistance(CheckPoint cp, int index, List<RaceSegment> segments, Event event) {
    final lapLength = event.poolLength;
    int turnCount = 0;
    for (int i = 0; i < index; i++) {
      if (segments[i].checkPoint == CheckPoint.turn) {
        turnCount++;
      }
    }

    switch (cp) {
      case CheckPoint.start:
        return _DistanceData('0m');
      case CheckPoint.offTheBlock:
        return _DistanceData('Off Block');
      case CheckPoint.fifteenMeterMark:
        return _DistanceData('${turnCount * lapLength + 15}m');
      case CheckPoint.turn:
        return _DistanceData('${(turnCount + 1) * lapLength}m');
      case CheckPoint.finish:
        return _DistanceData('${event.distance}m');
      case CheckPoint.breakOut:
        // Find the start of the current lap
        final lapStartIndex = segments.lastIndexWhere(
            (s) => s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn,
            index);
        final lapStartSegment = (lapStartIndex != -1) ? segments[lapStartIndex] : null;

        // Find the 15m mark for this lap
        final fifteenMeterIndex = segments.indexWhere(
            (s) => s.checkPoint == CheckPoint.fifteenMeterMark, lapStartIndex);
        final fifteenMeterSegment = (fifteenMeterIndex != -1) ? segments[fifteenMeterIndex] : null;

        if (lapStartSegment != null && fifteenMeterSegment != null) {
          final timeTo15m = fifteenMeterSegment.time - lapStartSegment.time;
          if (timeTo15m > Duration.zero) {
            final avgSpeed = 15.0 / timeTo15m.inSeconds;
            final timeToBreakout = segments[index].time - lapStartSegment.time;
            final estimatedDistance = avgSpeed * timeToBreakout.inSeconds;
            return _DistanceData('~${estimatedDistance.toStringAsFixed(1)}m', isEstimated: true);
          }
        }
        return _DistanceData('Breakout*'); // Fallback
    }
  }
}

class _DistanceData {
  final String distance;
  final bool isEstimated;

  _DistanceData(this.distance, {this.isEstimated = false});
}
