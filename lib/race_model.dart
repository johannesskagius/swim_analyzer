library race_model;

enum Stroke {
  freestyle,
  backstroke,
  breaststroke,
  butterfly;

  String get displayName {
    switch (this) {
      case Stroke.freestyle:
        return 'Freestyle';
      case Stroke.backstroke:
        return 'Backstroke';
      case Stroke.breaststroke:
        return 'Breaststroke';
      case Stroke.butterfly:
        return 'Butterfly';
    }
  }
}

/// A class to hold the attributes for a single interval between checkpoints.
class IntervalAttributes {
  int dolphinKickCount = 0;
  int strokeCount = 0;
  int breathCount = 0;
}


/// Represents a single recorded moment in a race.
class RaceSegment {
  final CheckPoint checkPoint;
  final Duration time;

  RaceSegment({required this.checkPoint, required this.time});
}

enum CheckPoint {
  start,
  offTheBlock,
  breakOut,
  fifteenMeterMark,
  turn,
  finish,
}

abstract class Event {
  final Stroke stroke;

  const Event({required this.stroke});

  String get name;
  int get distance;
  int get poolLength;
  List<CheckPoint> get checkPoints;
}

class FiftyMeterRace extends Event {
  const FiftyMeterRace({required super.stroke});

  @override
  String get name => '50m ${stroke.displayName}';
  @override
  int get distance => 50;
  @override
  int get poolLength => 25;

  @override
  List<CheckPoint> get checkPoints => [
        CheckPoint.start,
        CheckPoint.offTheBlock,
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.turn,
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.finish,
      ];
}

class HundredMetersRace extends Event {
  const HundredMetersRace({required super.stroke});

  @override
  String get name => '100m ${stroke.displayName}';
  @override
  int get distance => 100;
  @override
  int get poolLength => 25;

  @override
  List<CheckPoint> get checkPoints => [
        CheckPoint.start,
        CheckPoint.offTheBlock,
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.turn, // 25m
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.turn, // 50m
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.turn, // 75m
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.finish, // 100m
      ];
}

/// Represents a single segment of a race with all its calculated metrics.
class AnalyzedSegment {
  final int sequence;
  final String checkPoint;
  final double distanceMeters;
  final int totalTimeMillis;
  final int splitTimeMillis;
  final int? dolphinKicks;
  final int? strokes;
  final int? breaths;
  final double? strokeFrequency;
  final double? strokeLengthMeters;

  AnalyzedSegment({
    required this.sequence,
    required this.checkPoint,
    required this.distanceMeters,
    required this.totalTimeMillis,
    required this.splitTimeMillis,
    this.dolphinKicks,
    this.strokes,
    this.breaths,
    this.strokeFrequency,
    this.strokeLengthMeters,
  });

  /// Converts this object into a Map for Firestore.
  Map<String, dynamic> toJson() {
    return {
      'sequence': sequence,
      'checkPoint': checkPoint,
      'distanceMeters': distanceMeters,
      'totalTimeMillis': totalTimeMillis,
      'splitTimeMillis': splitTimeMillis,
      'dolphinKicks': dolphinKicks,
      'strokes': strokes,
      'breaths': breaths,
      'strokeFrequency': strokeFrequency,
      'strokeLengthMeters': strokeLengthMeters,
    };
  }
}

/// Represents a full race analysis, ready to be stored in Firestore.
class Race {
  final String eventName;
  final int poolLength;
  final String stroke;
  final int distance;
  final String? coachId;
  final String? swimmerId;
  final List<AnalyzedSegment> segments;

  Race({
    required this.eventName,
    required this.poolLength,
    required this.stroke,
    required this.distance,
    required this.segments,
    this.coachId,
    this.swimmerId,
  });

  /// Converts this object into a Map for Firestore.
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'eventName': eventName,
      'poolLength': poolLength,
      'stroke': stroke,
      'distance': distance,
      'segments': segments.map((s) => s.toJson()).toList(),
    };

    if (coachId != null) {
      data['coachId'] = coachId;
    }
    if (swimmerId != null) {
      data['swimmerId'] = swimmerId;
    }

    return data;
  }
}
