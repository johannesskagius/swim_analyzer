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
    this.enabledAttributes = const {},
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

  /// Converts this object into a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'videoPath': videoPath,
      'analysisDate': analysisDate.toIso8601String(),
      'enabledAttributes': enabledAttributes.toList(),
      'reactionTime': reactionTime?.inMilliseconds,
      'flightTime': flightTime?.inMilliseconds,
      'entryAngle': entryAngle,
      'backLegAngle': backLegAngle,
      'frontLegAngle': frontLegAngle,
      'timeTo15m': timeTo15m?.inMilliseconds,
      'breakoutTime': breakoutTime?.inMilliseconds,
      'breakoutDolphinKicks': breakoutDolphinKicks,
      'timeToFirstDolphinKick': timeToFirstDolphinKick?.inMilliseconds,
      'timeToPullOut': timeToPullOut?.inMilliseconds,
      'timeGlidingPostPullOut': timeGlidingPostPullOut?.inMilliseconds,
      'glidFaceAfterPullOut': glidFaceAfterPullOut?.inMilliseconds,
      'speedToFiveMeters': speedToFiveMeters,
      'speedTo10Meters': speedTo10Meters,
      'speedTo15Meters': speedTo15Meters,
    };
  }

  /// Creates an instance of [StartAnalysis] from a JSON map.
  factory StartAnalysis.fromJson(Map<String, dynamic> json) {
    return StartAnalysis(
      id: json['id'] as String,
      videoPath: json['videoPath'] as String,
      analysisDate: DateTime.parse(json['analysisDate'] as String),
      enabledAttributes: (json['enabledAttributes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toSet() ??
          {},
      reactionTime: _durationFromJson(json['reactionTime']),
      flightTime: _durationFromJson(json['flightTime']),
      entryAngle: (json['entryAngle'] as num?)?.toDouble(),
      backLegAngle: (json['backLegAngle'] as num?)?.toDouble(),
      frontLegAngle: (json['frontLegAngle'] as num?)?.toDouble(),
      timeTo15m: _durationFromJson(json['timeTo15m']),
      breakoutTime: _durationFromJson(json['breakoutTime']),
      breakoutDolphinKicks: json['breakoutDolphinKicks'] as int?,
      timeToFirstDolphinKick: _durationFromJson(json['timeToFirstDolphinKick']),
      timeToPullOut: _durationFromJson(json['timeToPullOut']),
      timeGlidingPostPullOut: _durationFromJson(json['timeGlidingPostPullOut']),
      glidFaceAfterPullOut: _durationFromJson(json['glidFaceAfterPullOut']),
      speedToFiveMeters: (json['speedToFiveMeters'] as num?)?.toDouble(),
      speedTo10Meters: (json['speedTo10Meters'] as num?)?.toDouble(),
      speedTo15Meters: (json['speedTo15Meters'] as num?)?.toDouble(),
    );
  }

  /// Helper method for safely converting milliseconds to [Duration].
  static Duration? _durationFromJson(dynamic value) {
    if (value == null) return null;
    if (value is int) return Duration(milliseconds: value);
    if (value is double) return Duration(milliseconds: value.toInt());
    return null;
  }
}
