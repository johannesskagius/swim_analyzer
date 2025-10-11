/// Data model representing a swimming start analysis.
class StartAnalysis {
  final String id; // Unique identifier for the analysis
  final String videoPath; // Path to the video file used for analysis
  final DateTime analysisDate; // The date and time the analysis was performed
  final Set<String> enabledAttributes; // The attributes selected for analysis

  // Key performance metrics for a swimming start
  final Duration? reactionTime; // Time from the starting signal to the feet leaving the block
  final Duration? flightTime; // Time from leaving the block to entering the water
  final double? entryAngle; // Angle of the body upon entering the water
  final double? backLegAngle; // Angle of the back leg upon leaving the block
  final double? frontLegAngle; // Angle of the front leg upon leaving the block
  final Duration? timeTo15m; // The total time to reach the 15-meter mark from the start signal
  final Duration? breakoutTime; // The time when the swimmer's head breaks the water surface
  final int? breakoutDolphinKicks; // The number of dolphin kicks before the breakout
  final Duration? timeToFirstDolphinKick; // Time to the initiation of the first dolphin kick
  final Duration? timeToPullOut; // Time to the initiation of the pull-out (for breaststroke)
  final Duration? timeGlidingPostPullOut; // Glide time after the pull-out
  final Duration? glidFaceAfterPullOut; // Glide phase after the pull-out
  final double? speedToFiveMeters; // Average speed to the 5-meter mark
  final double? speedTo10Meters; // Average speed to the 10-meter mark
  final double? speedTo15Meters; // Average speed to the 15-meter mark

  const StartAnalysis({
    required this.id,
    required this.videoPath,
    required this.analysisDate,
    this.enabledAttributes = const {}, // Default to an empty set
    this.reactionTime,
    this.flightTime,
    this.entryAngle,
    this.backLegAngle,
    this.frontLegAngle,
    this.timeTo15m,
    this.breakoutTime,
    this.breakoutDolphinKicks,
    this.timeToFirstDolphinKick,
    this.timeToPullOut,
    this.timeGlidingPostPullOut,
    this.glidFaceAfterPullOut,
    this.speedToFiveMeters,
    this.speedTo10Meters,
    this.speedTo15Meters,
  });

  StartAnalysis copyWith({
    String? id,
    String? videoPath,
    DateTime? analysisDate,
    Set<String>? enabledAttributes,
    Duration? reactionTime,
    Duration? flightTime,
    double? entryAngle,
    double? backLegAngle,
    double? frontLegAngle,
    Duration? timeTo15m,
    Duration? breakoutTime,
    int? breakoutDolphinKicks,
    Duration? timeToFirstDolphinKick,
    Duration? timeToPullOut,
    Duration? timeGlidingPostPullOut,
    Duration? glidFaceAfterPullOut,
    double? speedToFiveMeters,
    double? speedTo10Meters,
    double? speedTo15Meters,
  }) {
    return StartAnalysis(
      id: id ?? this.id,
      videoPath: videoPath ?? this.videoPath,
      analysisDate: analysisDate ?? this.analysisDate,
      enabledAttributes: enabledAttributes ?? this.enabledAttributes,
      reactionTime: reactionTime ?? this.reactionTime,
      flightTime: flightTime ?? this.flightTime,
      entryAngle: entryAngle ?? this.entryAngle,
      backLegAngle: backLegAngle ?? this.backLegAngle,
      frontLegAngle: frontLegAngle ?? this.frontLegAngle,
      timeTo15m: timeTo15m ?? this.timeTo15m,
      breakoutTime: breakoutTime ?? this.breakoutTime,
      breakoutDolphinKicks: breakoutDolphinKicks ?? this.breakoutDolphinKicks,
      timeToFirstDolphinKick: timeToFirstDolphinKick ?? this.timeToFirstDolphinKick,
      timeToPullOut: timeToPullOut ?? this.timeToPullOut,
      timeGlidingPostPullOut: timeGlidingPostPullOut ?? this.timeGlidingPostPullOut,
      glidFaceAfterPullOut: glidFaceAfterPullOut ?? this.glidFaceAfterPullOut,
      speedToFiveMeters: speedToFiveMeters ?? this.speedToFiveMeters,
      speedTo10Meters: speedTo10Meters ?? this.speedTo10Meters,
      speedTo15Meters: speedTo15Meters ?? this.speedTo15Meters,
    );
  }
}