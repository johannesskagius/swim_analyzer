import 'package:flutter/material.dart';
import 'race_model.dart';

class ResultsPage extends StatelessWidget {
  final List<RaceSegment> recordedSegments;
  final List<IntervalAttributes> intervalAttributes;
  final Event event;

  const ResultsPage({
    super.key,
    required this.recordedSegments,
    required this.intervalAttributes,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    final bool isBreaststroke = event.stroke == Stroke.breaststroke;
    final hasRecordedData = recordedSegments.isNotEmpty;

    // Define columns dynamically based on stroke.
    final List<DataColumn> columns = [
      const DataColumn(label: Text('Distance')),
      const DataColumn(label: Text('Split Time')),
      const DataColumn(label: Text('Lap Time')),
      if (!isBreaststroke) const DataColumn(label: Text('Dolphin Kicks')),
      const DataColumn(label: Text('Strokes')),
      if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
      const DataColumn(label: Text('Stroke Freq.')),
      const DataColumn(label: Text('Stroke Len.')),
    ];

    final breakoutEstimate = _getBreakoutEstimate();

    return Scaffold(
      appBar: AppBar(
        title: Text('${event.name} - Results'),
      ),
      body: hasRecordedData
          ? SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: columns,
                      rows: List<DataRow>.generate(
                        recordedSegments.length,
                        (index) {
                          final segment = recordedSegments[index];
                          final splitTime = _getSplitTime(index);
                          final lapTime = _getLapTime(index);
                          final strokeFreq = _getStrokeFrequency(index);
                          final strokeLength = _getStrokeLength(index);

                          // Attributes are for the interval ending at this segment.
                          final attributes = index > 0 ? intervalAttributes[index - 1] : null;

                          return DataRow(
                            cells: <DataCell>[
                              DataCell(Text(_getDistance(segment, index))),
                              DataCell(Text(splitTime)),
                              DataCell(Text(lapTime)),
                              if (!isBreaststroke)
                                DataCell(Text(attributes?.dolphinKickCount.toString() ?? '')),
                              DataCell(Text(attributes?.strokeCount.toString() ?? '')),
                              if (!isBreaststroke)
                                DataCell(Text(attributes?.breathCount.toString() ?? '')),
                              DataCell(Text(strokeFreq)),
                              DataCell(Text(strokeLength)),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (breakoutEstimate != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(breakoutEstimate),
                    ),
                ],
              ),
            )
          : const Center(child: Text('No results to display.')),
    );
  }

  String? _getBreakoutEstimate() {
    if (recordedSegments.any((s) => s.checkPoint == CheckPoint.breakOut)) {
      return '* Breakout distance is an estimation based on average speed to the 15m mark.';
    }
    return null;
  }

  double _getDistanceAsDouble(RaceSegment segment, int index) {
    final cp = segment.checkPoint;
    int turnCount = recordedSegments
        .take(index)
        .where((s) => s.checkPoint == CheckPoint.turn)
        .length;

    final lapLength = event.poolLength;

    switch (cp) {
      case CheckPoint.start:
      case CheckPoint.offTheBlock:
        return 0.0;
      case CheckPoint.breakOut:
        {
          final lapStartSegment = recordedSegments
              .take(index)
              .lastWhere((s) => s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn);
          final lapStartIndex = recordedSegments.lastIndexOf(lapStartSegment, index);

          RaceSegment? fifteenMeterMarkInLap;
          for (int i = lapStartIndex + 1; i < recordedSegments.length; i++) {
            final currentSegment = recordedSegments[i];
            if (currentSegment.checkPoint == CheckPoint.fifteenMeterMark) {
              fifteenMeterMarkInLap = currentSegment;
              break;
            }
            if (currentSegment.checkPoint == CheckPoint.turn || currentSegment.checkPoint == CheckPoint.finish) {
              break;
            }
          }

          if (fifteenMeterMarkInLap != null) {
            final timeTo15m = fifteenMeterMarkInLap.time - lapStartSegment.time;
            if (timeTo15m.inMilliseconds > 0) {
              final double durationTo15m = timeTo15m.inMilliseconds / 1000.0;
              final avgSpeed = 15.0 / durationTo15m;
              final timeToBreakout = segment.time - lapStartSegment.time;
              final double durationToBreakout =
                  timeToBreakout.inMilliseconds / 1000.0;
              return avgSpeed * durationToBreakout;
            }
          }
          return 7.5; // Fallback
        }
      case CheckPoint.fifteenMeterMark:
        return (turnCount * lapLength + 15).toDouble();
      case CheckPoint.turn:
        return ((turnCount + 1) * lapLength).toDouble();
      case CheckPoint.finish:
        return event.distance.toDouble();
    }
  }


  String _getDistance(RaceSegment segment, int index) {
    final cp = segment.checkPoint;
    int turnCount = recordedSegments
        .take(index)
        .where((s) => s.checkPoint == CheckPoint.turn)
        .length;

    final lapLength = event.poolLength;

    switch (cp) {
      case CheckPoint.start:
        return '0m';
      case CheckPoint.offTheBlock:
        return '0m';
      case CheckPoint.breakOut:
          final distance = _getDistanceAsDouble(segment, index);
          return '~${distance.toStringAsFixed(1)}m*';
      case CheckPoint.fifteenMeterMark:
        return '${turnCount * lapLength + 15}m';
      case CheckPoint.turn:
        return '${(turnCount + 1) * lapLength}m';
      case CheckPoint.finish:
        return '${event.distance}m';
    }
  }

  String _formatDuration(Duration d) {
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2)}';
  }

  String _getSplitTime(int index) {
    if (index == 0) return '-';
    final current = recordedSegments[index].time;
    final previous = recordedSegments[index - 1].time;
    return _formatDuration(current - previous);
  }

  String _getLapTime(int index) {
    final currentSegment = recordedSegments[index];

    if (currentSegment.checkPoint != CheckPoint.turn &&
        currentSegment.checkPoint != CheckPoint.finish) {
      return '-';
    }

    final lapStartSegment = recordedSegments
        .take(index)
        .lastWhere(
          (s) => s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn,
          orElse: () => recordedSegments[0],
        );

    final lapTime = currentSegment.time - lapStartSegment.time;
    return _formatDuration(lapTime);
  }

   String _getStrokeFrequency(int index) {
    if (index == 0) return '-';

    final currentAttributes = intervalAttributes[index - 1];
    if (currentAttributes.strokeCount == 0) return '-';

    final startSegment = recordedSegments[index - 1];
    final endSegment = recordedSegments[index];

    final isSwimmingSegment = (startSegment.checkPoint == CheckPoint.breakOut || startSegment.checkPoint == CheckPoint.fifteenMeterMark) && (endSegment.checkPoint == CheckPoint.turn || endSegment.checkPoint == CheckPoint.finish || endSegment.checkPoint == CheckPoint.fifteenMeterMark);

    if (!isSwimmingSegment) return '-';

    final duration = endSegment.time - startSegment.time;
    if (duration.inMilliseconds > 0) {
      final double durationInSeconds = duration.inMilliseconds / 1000.0;
      final double strokesPerMinute = (currentAttributes.strokeCount / durationInSeconds) * 60;
      return strokesPerMinute.toStringAsFixed(1);
    }
    return '-';
  }

  String _getStrokeLength(int index) {
    if (index == 0) return '-';

    final currentAttributes = intervalAttributes[index - 1];
    if (currentAttributes.strokeCount == 0) return '-';

    final startSegment = recordedSegments[index - 1];
    final endSegment = recordedSegments[index];

    final isSwimmingSegment = (startSegment.checkPoint == CheckPoint.breakOut || startSegment.checkPoint == CheckPoint.fifteenMeterMark) && (endSegment.checkPoint == CheckPoint.turn || endSegment.checkPoint == CheckPoint.finish || endSegment.checkPoint == CheckPoint.fifteenMeterMark);

    if (!isSwimmingSegment) return '-';

    final startDistance = _getDistanceAsDouble(startSegment, index - 1);
    final endDistance = _getDistanceAsDouble(endSegment, index);
    final intervalDistance = endDistance - startDistance;

    if (intervalDistance > 0) {
      final strokeLength = intervalDistance / currentAttributes.strokeCount;
      return '${strokeLength.toStringAsFixed(2)}m';
    }

    return '-';
  }
}
