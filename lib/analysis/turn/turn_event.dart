/// Defines the key events for turn analysis.
enum TurnEvent {
  approach5m,
  wallContactOrFlipStart,
  feetLeaveWall,
  firstKickOrPulloutStart,
  breakout5m,
  breakout10m,
  breakout15m,
}

extension TurnEventX on TurnEvent {
  String get displayName {
    switch (this) {
      case TurnEvent.approach5m:
        return "Approach 5m before wall";
      case TurnEvent.wallContactOrFlipStart:
        return "Wall contact / Flip initiation";
      case TurnEvent.feetLeaveWall:
        return "Feet leave wall";
      case TurnEvent.firstKickOrPulloutStart:
        return "First kick / Pull-out start";
      case TurnEvent.breakout5m:
        return "Breakout at 5m";
      case TurnEvent.breakout10m:
        return "Breakout at 10m";
      case TurnEvent.breakout15m:
        return "Breakout at 15m";
    }
  }
}