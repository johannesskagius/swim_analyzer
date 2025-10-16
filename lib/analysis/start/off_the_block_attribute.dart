// A type-safe representation of the attributes that can be analyzed.
enum OffTheBlockAttribute {
  startPositionBackLegAngle,
  startPositionFrontLegAngle,
  reactionTime,
  flightTime,
  entryStartAngle,
  entryHipAngle,
  entryFinishAngle,
}

// An extension to provide user-friendly display names for the enum values.
extension OffTheBlockAttributeExtension on OffTheBlockAttribute {
  String get displayName {
    // Converts camelCase to a readable format. e.g., 'startPositionBackLegAngle' -> 'Start position back leg angle'
    final spaced = name.replaceAllMapped(
        RegExp(r'(?<=[a-z])[A-Z]'), (match) => ' ${match.group(0)}');
    // Capitalizes the first letter.
    final withCase = spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
    
    // A small tweak for 'Start' which is a single word after a capital
    return withCase.replaceAll('Start ', 'Start-');
  }
}
