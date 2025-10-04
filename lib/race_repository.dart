import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:swim_analyzer/race_model.dart';

class RaceRepository {
  final FirebaseFirestore _db;

  RaceRepository(this._db);

  CollectionReference get _racesCollection => _db.collection('races');

  /// Saves a new race analysis to Firestore.
  Future<void> addRace(Race newRace) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Error: No authenticated user to save the race for.");
      return;
    }

    try {
      // Add the userId and a server-side timestamp before saving.
      final raceData = newRace.toJson();
      raceData['userId'] = user.uid;
      raceData['createdAt'] = FieldValue.serverTimestamp();

      await _racesCollection.add(raceData);
      debugPrint("Race successfully saved to Firestore.");
    } catch (e) {
      debugPrint("Error saving race to Firestore: $e");
      // Optionally, rethrow the error or handle it as needed.
    }
  }

  // Future methods for getting races can be added here, for example:
  // Future<List<Race>> getRacesByStroke(String stroke) async { ... }
}
