
import 'package:flutter_test/flutter_test.dart';
import 'package:swim_analyzer/analysis/race/race_data_analyzer.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

void main() {
  // Mock data for a 50m Freestyle race in a 25m pool
  final mockSegments50sc = [
    RaceSegment(checkPoint: CheckPoint.start, splitTimeOfTotalRace: Duration.zero),
    RaceSegment(checkPoint: CheckPoint.breakOut, splitTimeOfTotalRace: const Duration(seconds: 2, milliseconds: 800)),
    RaceSegment(checkPoint: CheckPoint.fifteenMeterMark, splitTimeOfTotalRace: const Duration(seconds: 4, milliseconds: 200)),
    RaceSegment(checkPoint: CheckPoint.turn, splitTimeOfTotalRace: const Duration(seconds: 11, milliseconds: 500)),
    RaceSegment(checkPoint: CheckPoint.breakOut, splitTimeOfTotalRace: const Duration(seconds: 14, milliseconds: 100)),
    RaceSegment(checkPoint: CheckPoint.fifteenMeterMark, splitTimeOfTotalRace: const Duration(seconds: 15, milliseconds: 800)),
    RaceSegment(checkPoint: CheckPoint.finish, splitTimeOfTotalRace: const Duration(seconds: 24, milliseconds: 800)),
  ];
  final mockStrokes50sc = [0.0, 3.0, 7.0, 0.0, 3.0, 9.0];

  group('RaceDataAnalyzer: 50m Freestyle Short Course (25m Pool)', () {
    final analyzer = RaceDataAnalyzer(
      recordedSegments: mockSegments50sc,
      poolLength: PoolLength.m25,
      event: FiftyMeterRace(stroke: Stroke.freestyle),
      editableStrokeCounts: mockStrokes50sc,
    );

    test('getDistanceAsDouble calculates cumulative distances correctly', () {
      // Lap 1: Speed to 15m = 15.0 / 4.2s = 3.57 m/s. Breakout dist = 3.57 * 2.8s = 10.0m
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[0], 0), 0.0);
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[1], 1), closeTo(10.0, 0.01)); // breakout
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[2], 2), 15.0); // 15m mark
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[3], 3), 25.0); // turn

      // Lap 2: Speed to 15m = 15.0 / (15.8s - 11.5s) = 15.0 / 4.3s = 3.48 m/s. Breakout dist = 3.48 * (14.1s - 11.5s) = 3.48 * 2.6s = 9.06m
      final lap2BreakoutCumulative = 25.0 + 9.06;
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[4], 4), closeTo(lap2BreakoutCumulative, 0.01)); // breakout lap 2
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[5], 5), 40.0); // 15m mark lap 2
      expect(analyzer.getDistanceAsDouble(mockSegments50sc[6], 6), 50.0); // finish
    });

    test('getDistance formats distances correctly', () {
      expect(analyzer.getDistance(mockSegments50sc[0], 0), '0m');
      expect(analyzer.getDistance(mockSegments50sc[1], 1), '*10.0m'); // Special breakout format
      expect(analyzer.getDistance(mockSegments50sc[2], 2), '15m');
      expect(analyzer.getDistance(mockSegments50sc[3], 3), '25m');
      expect(analyzer.getDistance(mockSegments50sc[4], 4), '*9.1m'); // Special breakout format
      expect(analyzer.getDistance(mockSegments50sc[5], 5), '40m');
      expect(analyzer.getDistance(mockSegments50sc[6], 6), '50m');
    });

    test('getStrokeLengthAsDouble calculates meters per stroke', () {
      expect(analyzer.getStrokeLengthAsDouble(0), isNull);
      expect(analyzer.getStrokeLengthAsDouble(1), isNull); // 0 strokes
      // From breakout (10.0m) to 15m mark (15.0m) = 5.0m / 3 strokes = 1.67 m/stroke
      expect(analyzer.getStrokeLengthAsDouble(2), closeTo(1.67, 0.01));
      // From 15m (15.0m) to turn (25.0m) = 10.0m / 7 strokes = 1.43 m/stroke
      expect(analyzer.getStrokeLengthAsDouble(3), closeTo(1.43, 0.01));
      expect(analyzer.getStrokeLengthAsDouble(4), isNull); // 0 strokes
    });

    test('getStrokeFrequencyAsDouble calculates strokes per minute', () {
      expect(analyzer.getStrokeFrequencyAsDouble(0), isNull);
      expect(analyzer.getStrokeFrequencyAsDouble(1), isNull); // 0 strokes
      // 3 strokes in (4.2s - 2.8s = 1.4s). Freq = 3 / (1.4 / 60) = 128.5
      expect(analyzer.getStrokeFrequencyAsDouble(2), closeTo(128.5, 0.1));
       // 7 strokes in (11.5s - 4.2s = 7.3s). Freq = 7 / (7.3 / 60) = 57.5
      expect(analyzer.getStrokeFrequencyAsDouble(3), closeTo(57.5, 0.1));
      expect(analyzer.getStrokeFrequencyAsDouble(4), isNull); // 0 strokes
    });
  });

  group('RaceDataAnalyzer: Edge Cases', () {
    test('handles zero stroke count gracefully', () {
       final analyzer = RaceDataAnalyzer(
        recordedSegments: mockSegments50sc,
        poolLength: PoolLength.m25,
        event: FiftyMeterRace(stroke: Stroke.freestyle),
        editableStrokeCounts: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], // All zeros
      );
      expect(analyzer.getStrokeLengthAsDouble(2), isNull);
      expect(analyzer.getStrokeFrequencyAsDouble(2), isNull);
      expect(analyzer.getStrokeLength(2), '-');
      //expect(analyzer.getStrokeFrequency(2, asStrokesPerMinute: null), '-');
    });
  });
}
