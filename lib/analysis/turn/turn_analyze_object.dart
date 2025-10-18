import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:swim_analyzer/analysis/turn/turn_event.dart';

/// Represents a single analyzed turn, including timestamps and calculated metrics.
class TurnAnalyzeObject {
  final Map<TurnEvent, Duration> markedTimestamps;

  // --- Derived metrics ---
  final Duration? wallToFeet;
  final Duration? to5m;
  final Duration? to10m;
  final Duration? to15m;
  final Duration? totalUnderwaterTime;

  final double? avgSpeed5m;
  final double? avgSpeed10m;
  final double? avgSpeed15m;

  TurnAnalyzeObject({
    required this.markedTimestamps,
    this.wallToFeet,
    this.to5m,
    this.to10m,
    this.to15m,
    this.totalUnderwaterTime,
    this.avgSpeed5m,
    this.avgSpeed10m,
    this.avgSpeed15m,
  });

  /// Factory to compute metrics from raw timestamps.
  factory TurnAnalyzeObject.fromTimestamps(
      Map<TurnEvent, Duration> timestamps) {
    Duration? _delta(TurnEvent start, TurnEvent end) {
      final t1 = timestamps[start];
      final t2 = timestamps[end];
      if (t1 == null || t2 == null) return null;
      return t2 - t1;
    }

    final wallToFeet =
        _delta(TurnEvent.wallContactOrFlipStart, TurnEvent.feetLeaveWall);
    final to5m = _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout5m);
    final to10m = _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout10m);
    final to15m = _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout15m);
    final totalUnderwater = to15m;

    double? _avgSpeed(double meters, Duration? duration) {
      if (duration == null || duration.inMilliseconds <= 0) return null;
      return meters / (duration.inMilliseconds / 1000.0);
    }

    return TurnAnalyzeObject(
      markedTimestamps: timestamps,
      wallToFeet: wallToFeet,
      to5m: to5m,
      to10m: to10m,
      to15m: to15m,
      totalUnderwaterTime: totalUnderwater,
      avgSpeed5m: _avgSpeed(5, to5m),
      avgSpeed10m: _avgSpeed(10, to10m),
      avgSpeed15m: _avgSpeed(15, to15m),
    );
  }

  /// Converts to a serializable map for Firestore or JSON.
  Map<String, dynamic> toJson() {
    return {
      'timestamps':
          markedTimestamps.map((k, v) => MapEntry(k.name, v.inMilliseconds)),
      'wallToFeet_ms': wallToFeet?.inMilliseconds,
      'to5m_ms': to5m?.inMilliseconds,
      'to10m_ms': to10m?.inMilliseconds,
      'to15m_ms': to15m?.inMilliseconds,
      'totalUnderwater_ms': totalUnderwaterTime?.inMilliseconds,
      'avgSpeed5m': avgSpeed5m,
      'avgSpeed10m': avgSpeed10m,
      'avgSpeed15m': avgSpeed15m,
      'createdAt': Timestamp.now(),
    };
  }

  /// Builds from a Firestore or JSON map.
  factory TurnAnalyzeObject.fromJson(Map<String, dynamic> json) {
    Duration? _msToDuration(dynamic value) {
      if (value == null) return null;
      return Duration(
          milliseconds:
              value is int ? value : int.tryParse(value.toString()) ?? 0);
    }

    final rawTimestamps =
        (json['timestamps'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(
                  TurnEvent.values.firstWhere(
                    (e) => e.name == k,
                    orElse: () => TurnEvent.approach5m,
                  ),
                  Duration(milliseconds: v as int),
                )) ??
            {};

    return TurnAnalyzeObject(
      markedTimestamps: rawTimestamps,
      wallToFeet: _msToDuration(json['wallToFeet_ms']),
      to5m: _msToDuration(json['to5m_ms']),
      to10m: _msToDuration(json['to10m_ms']),
      to15m: _msToDuration(json['to15m_ms']),
      totalUnderwaterTime: _msToDuration(json['totalUnderwater_ms']),
      avgSpeed5m: (json['avgSpeed5m'] as num?)?.toDouble(),
      avgSpeed10m: (json['avgSpeed10m'] as num?)?.toDouble(),
      avgSpeed15m: (json['avgSpeed15m'] as num?)?.toDouble(),
    );
  }
}
