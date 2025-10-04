// --- Swimmer Class ---

import 'package:swim_analyzer/user.dart';
import 'package:swim_analyzer/user_types.dart';

class Swimmer extends AppUser {
  String?
  coachCreatorId; // Optional: ID of their primary coach or who added them
  String? headCoachId;
  String? secondCoachId;
  String? thirdCoachId;
  List<String>? memberOfTeams;

  Swimmer({
    required super.id,
    required super.name,
    required super.email,
    super.profilePicturePath,
    super.registerDate,
    super.clubId,
    super.updatedAt,
    this.memberOfTeams,
    this.coachCreatorId,
    this.secondCoachId,
    this.thirdCoachId,
  }) : super(userType: UserType.swimmer);

  factory Swimmer.fromJson(String docId, Map<String, dynamic> json) {
    return Swimmer(
      id: docId,
      name: json['name'] as String? ?? 'Swimmer',
      // Default name
      email: json['email'] as String? ?? '',
      profilePicturePath: json['profilePicturePath'] as String?,
      registerDate: AppUser.parseDateTime(json['registerDate']),
      updatedAt: AppUser.parseDateTime(json['updatedAt']),
      // Added
      clubId: json['memberOfClubId'] as String?,
      memberOfTeams: json['memberOfTeams'] != null
          ? List<String>.from(json['memberOfTeams'] as List<dynamic>)
          : [],
      coachCreatorId: json['coachCreatorId'] as String?,
      secondCoachId: json['secondCoachId'] as String?,
      thirdCoachId: json['thirdCoachId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      if (coachCreatorId != null) 'coachCreatorId': coachCreatorId,
      if (secondCoachId != null) 'secondCoachId': secondCoachId,
      if (thirdCoachId != null) 'thirdCoachId': thirdCoachId,
      if(memberOfTeams != null) 'memberOfTeams': memberOfTeams
    });
    return json;
  }

  @override
  Swimmer copyWith({
    String? id,
    String? name,
    String? email,
    UserType?
    userType, // Kept for signature consistency, but ignored by Swimmer constructor
    String? profilePicturePath,
    DateTime? registerDate,
    DateTime? updatedAt,
    String? memberOfClubId,
    List<String>? memberOfTeams,
    String? coachCreatorId,
    String? secondCoachId,
    String? thirdCoachId,
    // Add Swimmer-specific fields here if any, e.g. DateTime? dateOfBirth
  }) {
    return Swimmer(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      // userType is fixed by the Swimmer constructor to UserType.swimmer
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
      registerDate: registerDate ?? this.registerDate,
      updatedAt: updatedAt ?? this.updatedAt,
      clubId: memberOfClubId ?? clubId,
      memberOfTeams: memberOfTeams ?? this.memberOfTeams,
      coachCreatorId: coachCreatorId ?? this.coachCreatorId,
    );
  }
}
