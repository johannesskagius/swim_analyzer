import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/race_model.dart';
import 'package:swim_analyzer/race_repository.dart';

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

  Future<void> _saveRaceToFirestore(BuildContext context) async {
    if (recordedSegments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to save.')),
      );
      return;
    }

    final startTime = recordedSegments[0].time;
    final List<AnalyzedSegment> analyzedSegments = [];

    for (int i = 0; i < recordedSegments.length; i++) {
      final segment = recordedSegments[i];
      final attributes = i > 0 ? intervalAttributes[i - 1] : null;

      final totalTime = segment.time - startTime;
      final splitTime =
          (i > 0) ? (segment.time - recordedSegments[i - 1].time) : Duration.zero;
      
      final strokeFreqStr = _getStrokeFrequency(i);
      final strokeLengthStr = _getStrokeLength(i);

      analyzedSegments.add(AnalyzedSegment(
        sequence: i,
        checkPoint: segment.checkPoint.toString().split('.').last,
        distanceMeters: _getDistanceAsDouble(segment, i),
        totalTimeMillis: totalTime.inMilliseconds,
        splitTimeMillis: splitTime.inMilliseconds,
        dolphinKicks: attributes?.dolphinKickCount,
        strokes: attributes?.strokeCount,
        breaths: attributes?.breathCount,
        strokeFrequency: strokeFreqStr == '-' ? null : double.tryParse(strokeFreqStr),
        strokeLengthMeters: strokeLengthStr == '-' ? null : double.tryParse(strokeLengthStr.replaceAll('m', '')),
      ));
    }

    final newRace = Race(
      eventName: event.name,
      poolLength: event.poolLength,
      stroke: event.stroke.toString().split('.').last,
      distance: event.distance,
      segments: analyzedSegments,
    );

    try {
      final raceRepository = Provider.of<RaceRepository>(context, listen: false);
      await raceRepository.addRace(newRace);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Race analysis saved successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving race: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isBreaststroke = event.stroke == Stroke.breaststroke;
    final hasRecordedData = recordedSegments.isNotEmpty;

    final List<DataColumn> columns = [
      const DataColumn(label: Text('Distance')),
      const DataColumn(label: Text('Time')),
      if (!isBreaststroke) const DataColumn(label: Text('Dolphin Kicks')),
      const DataColumn(label: Text('Strokes')),
      if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
      const DataColumn(label: Text('Stroke Freq.')),
      const DataColumn(label: Text('Stroke Len.')),
    ];

    final breakoutEstimate = _getBreakoutEstimate();
    final startTime =
        hasRecordedData ? recordedSegments[0].time : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: Text('${event.name} - Results'),
        actions: [
          if (hasRecordedData)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () => _saveRaceToFirestore(context),
            ),
        ],
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
                          final totalTime =
                              _formatDuration(segment.time - startTime);
                          final splitTime = _getSplitTime(index);
                          final strokeFreq = _getStrokeFrequency(index);
                          final strokeLength = _getStrokeLength(index);

                          final attributes = index > 0
                              ? intervalAttributes[index - 1]
                              : null;

                          return DataRow(
                            cells: <DataCell>[
                              DataCell(Text(_getDistance(segment, index))),
                              DataCell(
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        totalTime,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        splitTime,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isBreaststroke)
                                DataCell(Text(attributes?.dolphinKickCount
                                        .toString() ??
                                    '')),
                              DataCell(
                                  Text(attributes?.strokeCount.toString() ?? '')),
                              if (!isBreaststroke)
                                DataCell(Text(
                                    attributes?.breathCount.toString() ?? '')),
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
          final lapStartSegment = recordedSegments.take(index).lastWhere(
              (s) =>
                  s.checkPoint == CheckPoint.start ||
                  s.checkPoint == CheckPoint.turn);
          final lapStartIndex =
              recordedSegments.lastIndexOf(lapStartSegment, index);

          final lapStartDistance =
              _getDistanceAsDouble(lapStartSegment, lapStartIndex);

          RaceSegment? fifteenMeterMarkInLap;
          for (int i = lapStartIndex + 1; i < recordedSegments.length; i++) {
            final currentSegment = recordedSegments[i];
            if (currentSegment.checkPoint == CheckPoint.fifteenMeterMark) {
              fifteenMeterMarkInLap = currentSegment;
              break;
            }
            if (currentSegment.checkPoint == CheckPoint.turn ||
                currentSegment.checkPoint == CheckPoint.finish) {
              break;
            }
          }

          if (fifteenMeterMarkInLap != null) {
            final timeTo15m =
                fifteenMeterMarkInLap.time - lapStartSegment.time;
            if (timeTo15m.inMilliseconds > 0) {
              final double durationTo15m = timeTo15m.inMilliseconds / 1000.0;
              final avgSpeed = 15.0 / durationTo15m;
              final timeToBreakout = segment.time - lapStartSegment.time;
              final double durationToBreakout =
                  timeToBreakout.inMilliseconds / 1000.0;
              final estimatedBreakoutDistanceFromWall =
                  avgSpeed * durationToBreakout;
              return lapStartDistance + estimatedBreakoutDistanceFromWall;
            }
          }
          return lapStartDistance + 7.5; // Fallback
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
    if (d.inMilliseconds < 0) return '0:00.00';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2)}';
  }

  String _getSplitTime(int index) {
    if (index == 0) return '-';
    final current = recordedSegments[index].time;
    final previous = recordedSegments[index - 1].time;
    return _formatDuration(current - previous);
  }

  String _getStrokeFrequency(int index) {
    if (index == 0) return '-';

    final currentAttributes = intervalAttributes[index - 1];
    if (currentAttributes.strokeCount == 0) return '-';

    final startSegment = recordedSegments[index - 1];
    final endSegment = recordedSegments[index];

    final isSwimmingSegment = (startSegment.checkPoint ==
                CheckPoint.breakOut ||
            startSegment.checkPoint == CheckPoint.fifteenMeterMark) &&
        (endSegment.checkPoint == CheckPoint.turn ||
            endSegment.checkPoint == CheckPoint.finish ||
            endSegment.checkPoint == CheckPoint.fifteenMeterMark);

    if (!isSwimmingSegment) return '-';

    final duration = endSegment.time - startSegment.time;
    if (duration.inMilliseconds > 0) {
      final double durationInSeconds = duration.inMilliseconds / 1000.0;
      final double strokesPerMinute =
          (currentAttributes.strokeCount / durationInSeconds) * 60;
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

    final isSwimmingSegment = (startSegment.checkPoint ==
                CheckPoint.breakOut ||
            startSegment.checkPoint == CheckPoint.fifteenMeterMark) &&
        (endSegment.checkPoint == CheckPoint.turn ||
            endSegment.checkPoint == CheckPoint.finish ||
            endSegment.checkPoint == CheckPoint.fifteenMeterMark);

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
