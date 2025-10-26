import 'package:swim_analyzer/analysis/stroke/stroke_segment_matrix.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_under_water_matrix.dart';
import 'package:swim_apps_shared/objects/intensity_zones.dart';
import 'package:swim_apps_shared/objects/stroke.dart';

class StrokeAnalysis {
  String id;
  String title;
  DateTime createdAt;
  String swimmerId;
  String createdById;

  // Captured Data
  final Stroke stroke;
  final IntensityZone intensity;
  final Map<String, int> markedTimestamps;
  final List<int> strokeTimestamps;

  // Calculated Data
  final UnderwaterMetrics underwater;
  final SegmentMetrics segment0_15m;
  final SegmentMetrics segment15_25m;
  final SegmentMetrics segmentFull25m;
  final double strokeFrequency;

  // 🧮 Derived Metrics for comparison/visualization
  double? averageSpeed;          // <-- nullable, can be reassigned
  late final double strokeLength;
  late final double cycleTime;
  late final double efficiencyIndex;
  late final double totalDistance;
  late final double underwaterTime;
  late final double underwaterDistance;
  late final double underwaterVelocity;
  late final double startReaction;
  late final double turnTime;

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
  }) {
    // Compute derived metrics
    averageSpeed = _computeAverageSpeed(segmentFull25m);
    strokeLength = segmentFull25m.strokeLength ??
        (strokeFrequency > 0 ? averageSpeed! / strokeFrequency : 0);
    cycleTime = strokeFrequency > 0 ? 1 / strokeFrequency : 0;
    efficiencyIndex = averageSpeed! * strokeLength;
    totalDistance = 25.0;

    underwaterTime = segment0_15m.phase1Time ?? 0.0;
    underwaterDistance = segment0_15m.phase1Distance ?? 0.0;
    underwaterVelocity = underwaterTime > 0
        ? underwaterDistance / underwaterTime
        : 0.0;

    startReaction =
        (markedTimestamps['reaction'] ?? 0) / 1000.0;
    turnTime =
        (markedTimestamps['turn'] ?? 0) / 1000.0;
  }

  double _computeAverageSpeed(SegmentMetrics seg) {
    if (seg.speed != null && seg.speed! > 0) return seg.speed!;
    if (seg.time != null && seg.time! > 0) return 25.0 / seg.time!;
    return 0.0;
  }

  Map<String, dynamic> toJson() => {
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

    // Derived
    'averageSpeed': averageSpeed,
    'strokeLength': strokeLength,
    'cycleTime': cycleTime,
    'efficiencyIndex': efficiencyIndex,
    'totalDistance': totalDistance,
    'underwaterTime': underwaterTime,
    'underwaterDistance': underwaterDistance,
    'underwaterVelocity': underwaterVelocity,
    'startReaction': startReaction,
    'turnTime': turnTime,
  };

  factory StrokeAnalysis.fromJson(Map<String, dynamic> json) {
    final analysis = StrokeAnalysis(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.tryParse(json['createdAt']) ?? DateTime.now(),
      swimmerId: json['swimmerId'] ?? json['userId'] ?? "",
      createdById: json['createdBy'] ?? "",
      stroke: Stroke.values.byName(json['stroke'] as String),
      intensity: IntensityZone.values.byName(json['intensity'] as String),
      markedTimestamps: Map<String, int>.from(json['markedTimestamps'] ?? {}),
      strokeTimestamps: List<int>.from(json['strokeTimestamps'] ?? []),
      strokeFrequency: (json['strokeFrequency'] as num?)?.toDouble() ?? 0,
      underwater: UnderwaterMetrics.fromJson(
          (json['underwater'] ?? {}) as Map<String, dynamic>),
      segment0_15m:
      SegmentMetrics.fromJson((json['segment0_15m'] ?? {}) as Map<String, dynamic>),
      segment15_25m:
      SegmentMetrics.fromJson((json['segment15_25m'] ?? {}) as Map<String, dynamic>),
      segmentFull25m:
      SegmentMetrics.fromJson((json['segmentFull25m'] ?? {}) as Map<String, dynamic>),
    );

    // ✅ Safely overwrite averageSpeed after constructor
    analysis.averageSpeed = (json['averageSpeed'] as num?)?.toDouble() ??
        analysis._computeAverageSpeed(analysis.segmentFull25m);

    return analysis;
  }
}
