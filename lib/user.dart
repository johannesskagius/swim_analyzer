// lib/users/user.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:swim_analyzer/swimmer.dart';

import 'coach.dart';
import 'user_types.dart'; // Assuming UserType enum (athlete, coach, admin etc.) is here

// --- AppUser (Abstract Base Class) ---
abstract class AppUser {
  String id;
  String name;
  String email;
  UserType
      userType; // This is key for polymorphism and set by subclass constructors
  String? profilePicturePath;
  DateTime? registerDate;
  DateTime? updatedAt; // Added field
  String?
      clubId; // Common: ID of the club the user is primarily associated with

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.userType, // Will be passed by subclass constructors
    this.profilePicturePath,
    this.registerDate,
    this.updatedAt, // Added to constructor
    this.clubId,
  });

  // Common toJson logic, subclasses will add their specific fields
  Map<String, dynamic> toJson() {
    return {
      'id': id, //is often the document ID, but can be included if useful
      'name': name,
      'email': email,
      'userType': userType.name,
      // Store UserType as a string, crucial for fromJson dispatch
      if (profilePicturePath != null) 'profilePicturePath': profilePicturePath,
      if (registerDate != null)
        'registerDate': Timestamp.fromDate(registerDate!),
      if (updatedAt != null) // Added to toJson
        'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  // Factory constructor to dispatch to specific types based on 'userType' in JSON
  factory AppUser.fromJson(String docId, Map<String, dynamic> json) {
    UserType detectedUserType = _getUserTypeFromString(
      json['userType'] as String?,
    );

    // Ensure the json map has the userType explicitly for the subclass factories
    json['userType'] = detectedUserType.name;
    // Add updatedAt to the json map if it's not directly used by subclass fromJson yet
    // This is to ensure it's available for subclass constructors.
    // However, it's better if subclass fromJson methods explicitly handle it.
    // For now, we assume subclass fromJson will pick it up or it's passed directly.

    switch (detectedUserType) {
      case UserType.coach:
        return Coach.fromJson(docId, json);
      case UserType.swimmer:
        return Swimmer.fromJson(docId, json);
    }
  }

  // Helper to parse UserType from a string, static as it's used by the factory
  static UserType _getUserTypeFromString(String? nameFromJson) {
    if (nameFromJson == null) {
      debugPrint(
        'Warning: UserType string from JSON was null, defaulting to UserType.swimmer.',
      );
      return UserType.swimmer; // Or another sensible default or throw error
    }
    try {
      return UserType.values.firstWhere((e) => e.name == nameFromJson);
    } catch (e) {
      debugPrint(
        'Warning: Unknown UserType string: "$nameFromJson", defaulting to UserType.swimmer.',
      );
      return UserType.swimmer; // Or another sensible default or throw error
    }
  }

  // Helper to parse DateTime from Firestore Timestamp or String, static for factory use
  static DateTime? parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is Timestamp) return value.toDate();
    debugPrint(
      'Warning: Could not parse DateTime from value: $value of type ${value.runtimeType}',
    );
    return null;
  }

  /// Abstract copyWith method. Subclasses must implement this.
  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    UserType? userType,
    String? profilePicturePath,
    DateTime? registerDate,
    DateTime? updatedAt,
    String? memberOfClubId,
    // Note: Subclass implementations will have their own specific fields here
  });

  // ... (rest of your static signUpUserWithEmail and instance updateFirebaseAuthDisplayName methods)
  // These methods should also be reviewed to handle 'updatedAt' if applicable,
  // e.g., setting it during sign-up or updates.

  static Future<AppUser?> signUpUserWithEmail({
    required String newName,
    required String newEmail,
    required String password,
    required UserType userType, // Make userType explicit for sign-up
    // Common fields
    String? profilePicturePath, // Usually from Firebase Auth user.photoURL
    String? memberOfClubId,
    // Fields for Coach
    List<String>? coachMemberOfTeams,
    List<String>? coachOwnerOfTeams,
    String? coachCoachCreatorId,
    // Fields for Swimmer
    List<String>? swimmerMemberOfTeams,
    String? swimmerCoachCreatorId,
    // Add fields for Administrator if any are set at sign-up
  }) async {
    try {
      UserCredential userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: newEmail, password: password);

      User? firebaseUser = userCred.user;
      if (firebaseUser == null) {
        debugPrint("Firebase Auth user creation failed, user is null.");
        return null;
      }

      if (newName.isNotEmpty) {
        await firebaseUser.updateDisplayName(newName);
      }

      final now = DateTime.now();

      Map<String, dynamic> profileJson = {
        'name': newName.isNotEmpty
            ? newName
            : (firebaseUser.displayName ?? newEmail.split('@')[0]),
        'email': firebaseUser.email!,
        'userType': userType.name,
        'profilePicturePath': profilePicturePath ?? firebaseUser.photoURL,
        'registerDate':
            Timestamp.fromDate(firebaseUser.metadata.creationTime ?? now),
        'updatedAt': Timestamp.fromDate(now), // Set updatedAt on creation
        'memberOfClubId': memberOfClubId,
        'memberOfTeams': userType == UserType.coach
            ? coachMemberOfTeams
            : (userType == UserType.swimmer ? swimmerMemberOfTeams : []),
        'ownerOfTeams': userType == UserType.coach ? coachOwnerOfTeams : [],
        'coachCreatorId': userType == UserType.coach
            ? coachCoachCreatorId
            : (userType == UserType.swimmer ? swimmerCoachCreatorId : null),
      };

      AppUser newUserProfile = AppUser.fromJson(firebaseUser.uid, profileJson);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(newUserProfile.id)
          .set(
            newUserProfile.toJson(),
          );

      debugPrint(
        "User document created in Firestore for user ID: ${newUserProfile.id} as type ${newUserProfile.userType}",
      );
      return newUserProfile;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        "FirebaseAuthException during signUp: ${e.message} (code: ${e.code})",
      );
      return null;
    } catch (e) {
      debugPrint("Generic error during signUp process: $e");
      return null;
    }
  }

  Future<void> updateFirebaseAuthDisplayName(String newDisplayName) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && currentUser.uid == id) {
      if (newDisplayName.isEmpty) {
        debugPrint("Display name cannot be empty.");
        return;
      }
      try {
        await currentUser.updateDisplayName(newDisplayName);
        name = newDisplayName;
        updatedAt = DateTime.now(); // Update updatedAt timestamp

        await FirebaseFirestore.instance.collection('users').doc(id).update({
          'name': newDisplayName,
          'updatedAt': Timestamp.fromDate(updatedAt!), // Persist updatedAt
        });
        debugPrint("AppUser name updated in Firestore for ID: $id");
      } on FirebaseAuthException catch (e) {
        debugPrint(
          "FirebaseAuthException updating display name: ${e.message} (code: ${e.code})",
        );
      } catch (e) {
        debugPrint("Error updating display name for ID $id in Firestore: $e");
      }
    } else {
      debugPrint(
        "No user currently signed in, or ID mismatch, to update display name.",
      );
    }
  }
}
