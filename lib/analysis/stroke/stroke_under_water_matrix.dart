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