import 'package:flutter/foundation.dart';

/// The different types of checkpoints in a race.
enum CheckPoint {
  start,
  offTheBlock,
  breakOut,
  fifteenMeterMark,
  turn,
  finish;

  /// A more readable name for UI display.
  String get displayName {
    // A simple way to capitalize the first letter of the enum name.
    return name[0].toUpperCase() + name.substring(1);
  }
}

enum SwimAttribute {
  /// The number of strokes taken in a length.
  strokeCount,

  /// The number of underwater dolphin kicks after a start or turn.
  dolphinKickCount,

  /// The number of breaths taken in a length.
  breathCount;

  /// A more readable name for UI display.
  String get displayName {
    switch (this) {
      case SwimAttribute.strokeCount:
        return 'Stroke Count';
      case SwimAttribute.dolphinKickCount:
        return 'Dolphin Kicks';
      case SwimAttribute.breathCount:
        return 'Breaths';
    }
  }
}

/// A data class to hold the tracked attributes for a single lap.
class LapData {
  int strokeCount;
  int dolphinKickCount;
  int breathCount;

  LapData({
    this.strokeCount = 0,
    this.dolphinKickCount = 0,
    this.breathCount = 0,
  });

  /// Creates a copy of this LapData object, which is useful for resetting.
  LapData copy() {
    return LapData(
      strokeCount: strokeCount,
      dolphinKickCount: dolphinKickCount,
      breathCount: breathCount,
    );
  }
}


/// Abstract class representing a generic swimming event.
@immutable
abstract class Event {
  const Event();

  /// The name of the event, e.g., "50m Freestyle".
  String get name;

  /// The sequence of checkpoints for this event.
  List<CheckPoint> get checkPoints;
}

/// A concrete implementation for a 50-meter race.
@immutable
class FiftyMeterRace extends Event {
  const FiftyMeterRace();

  @override
  String get name => '50m Race';

  @override
  List<CheckPoint> get checkPoints => [
        CheckPoint.start,
        CheckPoint.offTheBlock,
        CheckPoint.breakOut,
        CheckPoint.fifteenMeterMark,
        CheckPoint.turn,
        CheckPoint.finish,
      ];
}

/// A concrete implementation for a 100-meter race.
@immutable
class HundredMetersRace extends Event {
  const HundredMetersRace();

  @override
  String get name => '100m Race';

  @override
  List<CheckPoint> get checkPoints => [
        CheckPoint.start,
        CheckPoint.turn, // 25m
        CheckPoint.turn, // 50m
        CheckPoint.turn, // 75m
        CheckPoint.finish,
      ];
}
