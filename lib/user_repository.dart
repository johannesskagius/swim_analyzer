import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:swim_analyzer/swimmer.dart';
import 'package:swim_analyzer/user.dart';
import 'package:swim_analyzer/user_types.dart';

class UserRepository {
  final FirebaseFirestore _db;

  UserRepository(this._db);

  CollectionReference get usersCollection => _db.collection('users');

  CollectionReference get _coachesCollection => _db.collection('coaches');

  Future<AppUser?> getUserDocument(String uid) async {
    if (uid.isEmpty) {
      debugPrint("Error: UID cannot be empty when fetching user document.");
      return null;
    }
    try {
      final DocumentSnapshot userDoc = await usersCollection.doc(uid).get();

      if (userDoc.exists && userDoc.data() != null) {
        return AppUser.fromJson(
          userDoc.id,
          userDoc.data() as Map<String, dynamic>,
        );
      } else {
        debugPrint("No user document found for UID: $uid");
        return null;
      }
    } catch (e) {
      debugPrint(
        "Error fetching and converting user document for UID $uid: $e",
      );
      return null;
    }
  }

  Future<List<AppUser>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) {
      return [];
    }
    try {
      List<AppUser> users = [];
      // Batch requests in chunks of 30, as 'whereIn' has a limit.
      for (var i = 0; i < userIds.length; i += 30) {
        final chunk = userIds.sublist(
          i,
          i + 30 > userIds.length ? userIds.length : i + 30,
        );
        if (chunk.isEmpty) continue;

        final QuerySnapshot snapshot = await usersCollection
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        users.addAll(
          snapshot.docs.map(
            (doc) =>
                AppUser.fromJson(doc.id, doc.data() as Map<String, dynamic>),
          ),
        );
      }
      return users;
    } catch (e) {
      debugPrint("Error fetching users by IDs: $e");
      return [];
    }
  }

  Future<List<Swimmer>> getAllSwimmersFromCoach({
    required String coachId,
  }) async {
    try {
      final QuerySnapshot snapshot = await usersCollection
          .where('userType', isEqualTo: UserType.swimmer.name)
          .where('coachCreatorId', isEqualTo: coachId)
          .orderBy('name')
          .get();
      return snapshot.docs
          .map(
            (doc) =>
                Swimmer.fromJson(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint("Error fetching all swimmers from coach: $e");
      return [];
    }
  }

  Future<void> createAppUser({required AppUser newUser}) async {
    await usersCollection.doc(newUser.id).set(newUser.toJson());
  }

  Future<AppUser?> getCoach(String coachId) async {
    try {
      DocumentSnapshot doc = await _coachesCollection.doc(coachId).get();
      if (doc.exists) {
        return AppUser.fromJson(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint("Error getting coach $coachId: $e");
      return null;
    }
  }

  Future<void> updateUser(AppUser updatedUser) async {
    usersCollection.doc(updatedUser.id).set(updatedUser.toJson());
  }

  Future<AppUser?> getMyProfile() async {
    String? myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) {
      return await getUserDocument(myUid);
    }
    return null;
  }
}
