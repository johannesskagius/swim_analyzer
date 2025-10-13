import 'package:swim_apps_shared/swim_apps_shared.dart';

class RaceDataAnalyzer {
  final List<RaceSegment> recordedSegments;
  late List<double> editableStrokeCounts;
  PoolLength poolLength;
  Event event;

  RaceDataAnalyzer(
      {required this.recordedSegments,
      required this.poolLength,
      required this.event,
      required this.editableStrokeCounts});

  String getSplitTime(int index) {
    if (index == 0) return '-';
    final split = recordedSegments[index].splitTimeOfTotalRace -
        recordedSegments[index - 1].splitTimeOfTotalRace;
    return '+${formatDuration(split)}';
  }

  String formatDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2)}';
  }

  double getDistanceAsDouble(RaceSegment segment, int index) {
    final int poolLengthValue = poolLength.distance;

    switch (segment.checkPoint) {
      case CheckPoint.start:
        return 0.0;
      case CheckPoint.finish:
        return event.distance.toDouble();
      case CheckPoint.turn:
        final turnCount = recordedSegments
            .sublist(0, index + 1)
            .where((s) => s.checkPoint == CheckPoint.turn)
            .length;
        return (turnCount * poolLengthValue).toDouble();
      case CheckPoint.fifteenMeterMark:
        final previousTurnCount = recordedSegments
            .sublist(0, index)
            .where((s) => s.checkPoint == CheckPoint.turn)
            .length;
        return (previousTurnCount * poolLengthValue) + 15.0;
      case CheckPoint.breakOut:
        // Find the distance of the last wall (start or turn) before this breakout
        final lapStartIndex = recordedSegments.lastIndexWhere(
          (s) =>
              s.checkPoint == CheckPoint.start ||
              s.checkPoint == CheckPoint.turn,
          index - 1,
        );
        if (lapStartIndex == -1)
          return 0.0; // Should not happen in a valid race

        final lastWallDistance =
            getDistanceAsDouble(recordedSegments[lapStartIndex], lapStartIndex);

        // Calculate the breakout distance for this specific lap (distance from the wall)
        final breakoutDistFromWall = getBreakoutDistanceForLap(index);

        // The cumulative distance is the wall's distance + the breakout distance
        return lastWallDistance + (breakoutDistFromWall ?? 0.0);
      default:
        // Handles any other unexpected checkpoint types
        return 0.0;
    }
  }

  String getDistance(RaceSegment segment, int index) {
    // For breakout rows, display the calculated breakout distance from the wall.
    if (segment.checkPoint == CheckPoint.breakOut) {
      final breakoutDist = getBreakoutDistanceForLap(index);
      // Prefix with '*' to indicate it's a special, non-cumulative value.
      return '*${breakoutDist?.toStringAsFixed(1) ?? 'N/A'}m';
    }

    final dist = getDistanceAsDouble(segment, index);
    if (dist == 0 && segment.checkPoint != CheckPoint.start) {
      return segment.checkPoint.toString().split('.').last;
    }
    return '${dist.toInt()}m';
  }

  double? getStrokeFrequencyAsDouble(int index) {
    if (index == 0) return null;
    final strokeCount = editableStrokeCounts[index - 1];
    if (strokeCount == 0) return null;

    final splitTime = (recordedSegments[index].splitTimeOfTotalRace -
            recordedSegments[index - 1].splitTimeOfTotalRace)
        .inMilliseconds;
    if (splitTime == 0) return null;

    return strokeCount / (splitTime / 1000 / 60);
  }

  double? getStrokeFrequency(int index, {required bool asStrokesPerMinute}) {
    double? freq = getStrokeFrequencyAsDouble(index);
    if(freq != null && asStrokesPerMinute){
      freq *= 60;
    }
    return freq;
  }

  double? getAverageSpeed(int segmentIndex) {
    final speed = getAverageSpeedAsDouble(segmentIndex);
    if (speed != null) {
      return speed;
    }
    return null; // Return null if speed cannot be calculated
  }
  /// Calculates the average speed (m/s) for a given race segment index.
  double? getAverageSpeedAsDouble(int segmentIndex) {
    if (segmentIndex <= 0 || segmentIndex >= recordedSegments.length) {
      return null; // Cannot calculate for the first segment or out of bounds.
    }

    final currentSegment = recordedSegments[segmentIndex];
    final previousSegment = recordedSegments[segmentIndex - 1];

    // Calculate the time duration of this specific segment.
    final Duration segmentDuration =
        currentSegment.splitTimeOfTotalRace - previousSegment.splitTimeOfTotalRace;

    // Avoid division by zero if timestamps are identical.
    if (segmentDuration.inMilliseconds <= 0) {
      return null;
    }

    // Determine the distance of the segment.
    final double segmentDistance =
        getDistanceAsDouble(currentSegment, segmentIndex) -
            getDistanceAsDouble(previousSegment, segmentIndex - 1);

    // If the distance is zero (e.g., between 'start' and 'off the block'),
    // speed is not meaningful.
    if (segmentDistance <= 0) {
      return null;
    }

    // Calculate speed: Speed = Distance / Time
    final double speed =
        segmentDistance / (segmentDuration.inMilliseconds / 1000.0);

    return speed;
  }

  double? getBreakoutDistanceForLap(int segmentIndex) {
    final currentSegment = recordedSegments[segmentIndex];
    if (currentSegment.checkPoint != CheckPoint.breakOut) return null;

    final lapStartIndex = recordedSegments.lastIndexWhere(
      (s) =>
          s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn,
      segmentIndex - 1,
    );

    if (lapStartIndex == -1) return null;

    final lapStartSegment = recordedSegments[lapStartIndex];
    final timeToBreakout = currentSegment.splitTimeOfTotalRace -
        lapStartSegment.splitTimeOfTotalRace;
    if (timeToBreakout <= Duration.zero) return null;

    // Find 15m mark for this specific lap to calculate speed
    final nextTurnIndex = recordedSegments.indexWhere(
      (s) =>
          s.checkPoint == CheckPoint.turn || s.checkPoint == CheckPoint.finish,
      lapStartIndex + 1,
    );

    final endOfLapIndex =
        nextTurnIndex == -1 ? recordedSegments.length : nextTurnIndex + 1;

    final fifteenMeterMarkIndex =
        recordedSegments.sublist(lapStartIndex, endOfLapIndex).indexWhere(
              (s) => s.checkPoint == CheckPoint.fifteenMeterMark,
            );

    double avgUnderwaterSpeed = 2.0; // Fallback speed

    if (fifteenMeterMarkIndex != -1) {
      final fifteenMeterSegment =
          recordedSegments[lapStartIndex + fifteenMeterMarkIndex];
      final timeTo15m = fifteenMeterSegment.splitTimeOfTotalRace -
          lapStartSegment.splitTimeOfTotalRace;
      if (timeTo15m > Duration.zero) {
        avgUnderwaterSpeed = 15.0 / (timeTo15m.inMilliseconds / 1000.0);
      }
    }

    return avgUnderwaterSpeed * (timeToBreakout.inMilliseconds / 1000.0);
  }

  double? getStrokeLengthAsDouble(int index) {
    if (index == 0) return null;
    final strokeCount = editableStrokeCounts[index - 1];
    if (strokeCount <= 0) return null;

    // Get the correct cumulative distance for the previous and current points.
    // The new _getDistanceAsDouble now correctly calculates the distance for ALL checkpoints.
    final prevDist =
        getDistanceAsDouble(recordedSegments[index - 1], index - 1);
    final currentDist = getDistanceAsDouble(recordedSegments[index], index);

    final distanceCovered = currentDist - prevDist;

    if (distanceCovered <= 0) return null;

    // The logic is now simple and correct for all segments because the
    // distance calculation itself is correct.
    return distanceCovered / strokeCount;
  }

  String getStrokeLength(int index) {
    final length = getStrokeLengthAsDouble(index);
    return length != null ? '${length.toStringAsFixed(2)}m' : '-';
  }

  String? getBreakoutEstimate() {
    final breakOutSegment = recordedSegments
        .where((s) => s.checkPoint == CheckPoint.breakOut)
        .firstOrNull;
    if (breakOutSegment == null) return null;

    final breakoutIndex = recordedSegments.indexOf(breakOutSegment);
    final distance = getBreakoutDistanceForLap(breakoutIndex);

    if (distance == null) return null;

    return '* Breakout distance estimate: ${distance.toStringAsFixed(1)}m';
  }
}
