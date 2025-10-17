// A dedicated enum for the specific events to be marked in this analysis.
enum OffTheBlockEvent {
  startSignal,
  leftBlock,
  touchedWater,
  submergedFully,
  reached5m,
  reached10m,
  reached15m,
}
// An extension to provide user-friendly names for the UI.
extension OffTheBlockEventExtension on OffTheBlockEvent {
  String get displayName {
    switch (this) {
      case OffTheBlockEvent.startSignal:
        return 'Start Signal';
      case OffTheBlockEvent.leftBlock:
        return 'Left the Block';
      case OffTheBlockEvent.touchedWater:
        return 'Touched the Water';
      case OffTheBlockEvent.submergedFully:
        return 'Submerged Fully';
      case OffTheBlockEvent.reached5m:
        return 'Reached 5m';
      case OffTheBlockEvent.reached10m:
        return 'Reached 10m';
      case OffTheBlockEvent.reached15m:
        return 'Reached 15m';
    }
  }
}