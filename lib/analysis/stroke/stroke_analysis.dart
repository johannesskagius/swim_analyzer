import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

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

/// A class to hold the calculated metrics for the underwater portion of the swim.
class UnderwaterMetrics {
  final double? timeToBreakout;
  final double? breakoutDistance;
  final double? underwaterSpeed;

  const UnderwaterMetrics({
    this.timeToBreakout,
    this.breakoutDistance,
    this.underwaterSpeed,
  });

  Map<String, dynamic> toJson() {
    return {
      'timeToBreakout': timeToBreakout,
      'breakoutDistance': breakoutDistance,
      'underwaterSpeed': underwaterSpeed,
    };
  }

  factory UnderwaterMetrics.fromJson(Map<String, dynamic> json) {
    return UnderwaterMetrics(
      timeToBreakout: (json['timeToBreakout'] as num?)?.toDouble(),
      breakoutDistance: (json['breakoutDistance'] as num?)?.toDouble(),
      underwaterSpeed: (json['underwaterSpeed'] as num?)?.toDouble(),
    );
  }
}

/// The main data model for a complete stroke analysis.
class StrokeAnalysis {
  String id;
  String title;
  DateTime createdAt;
  String swimmerId;
  String createdById;

  // Captured Data
  final Stroke stroke;
  final IntensityZone intensity;
  final Map<String, int> markedTimestamps; // event.name -> milliseconds
  final List<int> strokeTimestamps; // milliseconds

  // Calculated Data
  final UnderwaterMetrics underwater;
  final SegmentMetrics segment0_15m;
  final SegmentMetrics segment15_25m;
  final SegmentMetrics segmentFull25m;
  final double strokeFrequency; // Overall frequency

  StrokeAnalysis({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.swimmerId,
    required this.createdById,
    required this.stroke,
    required this.intensity,
    required this.markedTimestamps,
    required this.strokeTimestamps,
    required this.strokeFrequency,
    required this.underwater,
    required this.segment0_15m,
    required this.segment15_25m,
    required this.segmentFull25m,
  });

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {
      'id':id,
      'title':title,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdById,
      'swimmerId': swimmerId,
      'stroke': stroke.name,
      'intensity': intensity.name,
      'markedTimestamps': markedTimestamps,
      'strokeTimestamps': strokeTimestamps,
      'strokeFrequency': strokeFrequency,
      'underwater': underwater.toJson(),
      'segment0_15m': segment0_15m.toJson(),
      'segment15_25m': segment15_25m.toJson(),
      'segmentFull25m': segmentFull25m.toJson(),
    };
    return data;
  }

  factory StrokeAnalysis.fromJson(Map<String, dynamic> json) {
    return StrokeAnalysis(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.tryParse(json['createdAt'])??DateTime.now(),
      swimmerId: json['userId'] as String,
      createdById: json['createdBy'] as String,
      stroke: Stroke.values.byName(json['stroke'] as String),
      intensity: IntensityZone.values.byName(json['intensity'] as String),
      markedTimestamps: Map<String, int>.from(json['markedTimestamps'] as Map),
      strokeTimestamps: List<int>.from(json['strokeTimestamps'] as List),
      strokeFrequency: (json['strokeFrequency'] as num).toDouble(),
      underwater: UnderwaterMetrics.fromJson(
          json['underwater'] as Map<String, dynamic>),
      segment0_15m:
          SegmentMetrics.fromJson(json['segment0_15m'] as Map<String, dynamic>),
      segment15_25m: SegmentMetrics.fromJson(
          json['segment15_25m'] as Map<String, dynamic>),
      segmentFull25m: SegmentMetrics.fromJson(
          json['segmentFull25m'] as Map<String, dynamic>),
    );
  }
}
