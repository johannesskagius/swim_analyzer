
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_efficiency_event.dart';

class StrokeAnalysisData {
  final IntensityZone intensity;
  final Stroke stroke;
  final Map<StrokeEfficiencyEvent, Duration> markedTimestamps;
  final List<Duration> strokeTimestamps;
  final double strokeFrequency;

  StrokeAnalysisData({
    required this.intensity,
    required this.stroke,
    required this.markedTimestamps,
    required this.strokeTimestamps,
    required this.strokeFrequency,
  });
}
