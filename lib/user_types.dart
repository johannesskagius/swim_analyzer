enum UserType {
  coach,
  swimmer
}
extension UserTypeExtension on UserType {
  String get displayName {
    switch (this) {
      case UserType.coach:
        return 'Coach';
      case UserType.swimmer:
        return 'Swimmer';
      default:
        return 'Unknown';
    }
  }
}