/// A class to hold the calculated metrics for a specific segment of the swim.
class SegmentMetrics {
  final double? time;
  final double? speed;
  final int? strokeCount;
  final double? frequency;
  final double? strokeLength;
  final double? strokeIndex;
  final double? phase1Time;
  final double? phase1Distance;
  final double? phase2Time;
  final double? phase2Distance;

  const SegmentMetrics({
    this.time,
    this.speed,
    this.strokeCount,
    this.frequency,
    this.strokeLength,
    this.strokeIndex,
    this.phase1Time,
    this.phase1Distance,
    this.phase2Time,
    this.phase2Distance,
  });

  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'speed': speed,
      'strokeCount': strokeCount,
      'frequency': frequency,
      'strokeLength': strokeLength,
      'strokeIndex': strokeIndex,
      'phase1Time': phase1Time,
      'phase1Distance': phase1Distance,
      'phase2Time': phase2Time,
      'phase2Distance': phase2Distance,
    };
  }

  factory SegmentMetrics.fromJson(Map<String, dynamic> json) {
    return SegmentMetrics(
      time: (json['time'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      strokeCount: json['strokeCount'] as int?,
      frequency: (json['frequency'] as num?)?.toDouble(),
      strokeLength: (json['strokeLength'] as num?)?.toDouble(),
      strokeIndex: (json['strokeIndex'] as num?)?.toDouble(),
      phase1Time: (json['phase1Time'] as num?)?.toDouble(),
      phase1Distance: (json['phase1Distance'] as num?)?.toDouble(),
      phase2Time: (json['phase2Time'] as num?)?.toDouble(),
      phase2Distance: (json['phase2Distance'] as num?)?.toDouble(),
    );
  }
}