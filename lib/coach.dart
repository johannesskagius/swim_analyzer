// --- Coach Class ---

import 'package:swim_analyzer/user.dart';
import 'package:swim_analyzer/user_types.dart';

class Coach extends AppUser {
  List<String> memberOfTeams; // Teams the coach is directly coaching or part of
  List<String> ownerOfTeams;  // Teams the coach created/manages in the app
  String? coachCreatorId;     // Optional: ID of an admin or head coach who set up this coach account

  Coach({
    required super.id,
    required super.name,
    required super.email,
    super.profilePicturePath,
    super.registerDate,
    super.updatedAt, // Added
    super.clubId,
    List<String>? memberOfTeams,
    List<String>? ownerOfTeams,
    this.coachCreatorId,
  })  : memberOfTeams = memberOfTeams ?? [],
        ownerOfTeams = ownerOfTeams ?? [],
        super(
        userType: UserType.coach,
      );

  factory Coach.fromJson(String docId, Map<String, dynamic> json) {
    return Coach(
      id: docId,
      name: json['name'] as String? ?? 'Coach', // Default name
      email: json['email'] as String? ?? '',
      profilePicturePath: json['profilePicturePath'] as String?,
      registerDate: AppUser.parseDateTime(json['registerDate']),
      updatedAt: AppUser.parseDateTime(json['updatedAt']), // Added
      clubId: json['memberOfClubId'] as String?,
      memberOfTeams: json['memberOfTeams'] != null
          ? List<String>.from(json['memberOfTeams'] as List<dynamic>)
          : [],
      ownerOfTeams: json['ownerOfTeams'] != null
          ? List<String>.from(json['ownerOfTeams'] as List<dynamic>)
          : [],
      coachCreatorId: json['coachCreatorId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'memberOfTeams': memberOfTeams,
      'ownerOfTeams': ownerOfTeams,
      if (coachCreatorId != null) 'coachCreatorId': coachCreatorId,
    });
    return json;
  }

  @override
  Coach copyWith({
    String? id,
    String? name,
    String? email,
    UserType? userType, // Kept for signature consistency, but ignored by Coach constructor
    String? profilePicturePath,
    DateTime? registerDate,
    DateTime? updatedAt,
    String? memberOfClubId,
    List<String>? memberOfTeams,
    List<String>? ownerOfTeams,
    String? coachCreatorId,
  }) {
    return Coach(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      // userType is fixed by the Coach constructor to UserType.coach
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
      registerDate: registerDate ?? this.registerDate,
      updatedAt: updatedAt ?? this.updatedAt,
      clubId: memberOfClubId ?? clubId,
      memberOfTeams: memberOfTeams ?? this.memberOfTeams,
      ownerOfTeams: ownerOfTeams ?? this.ownerOfTeams,
      coachCreatorId: coachCreatorId ?? this.coachCreatorId,
    );
  }
}
