import 'package:flutter/foundation.dart';

/// Represents a single timed event in a race, like a breakout or a turn.
class RaceSegment {
  final CheckPoint checkPoint;
  final Duration time;

  RaceSegment({required this.checkPoint, required this.time});
}


/// Data holder for attributes of a single lap.
class LapData {
  int strokeCount = 0;
  int breathCount = 0;
  int dolphinKickCount = 0;
}

/// Enum representing the different swimming strokes.
enum Stroke {
  freestyle,
  backstroke,
  breaststroke,
  butterfly;

  String get displayName {
    return name[0].toUpperCase() + name.substring(1);
  }
}

/// Enum for the different checkpoints in a race.
enum CheckPoint {
  start,
  offTheBlock,
  breakOut,
  fifteenMeterMark,
  turn,
  finish,
}

/// Abstract representation of a swimming race event.
abstract class Event {
  String get name;
  int get distance;
  int get poolLength;
  Stroke get stroke;
  List<CheckPoint> get checkPoints;
}

/// A 50-meter race, typically in a 25m pool (short course).
class FiftyMeterRace implements Event {
  @override
  final Stroke stroke;

  FiftyMeterRace({required this.stroke});

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

/// A 100-meter race, typically in a 25m pool (short course).
class HundredMetersRace implements Event {
  @override
  final Stroke stroke;

  HundredMetersRace({required this.stroke});

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