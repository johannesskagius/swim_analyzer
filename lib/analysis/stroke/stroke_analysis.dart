import 'package:swim_analyzer/analysis/stroke/stroke_segment_matrix.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_under_water_matrix.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

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
      'id': id,
      'title': title,
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
      createdAt: DateTime.tryParse(json['createdAt']) ?? DateTime.now(),
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
