import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:swim_analyzer/user_repository.dart';

class FirestoreHelper {
  // Single instance of Firestore to be shared across all repositories.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Instances of the specialized repositories.
  late final UserRepository users;
  // late final GroupRepository groups;
  // late final SessionRepository sessions;
  // late final SetRepository sets;
  // late final PlanningRepository planning;
  // late final OnboardingRepository onboarding;
  // late final CompletedSessionRepository completedSessionRepository;
  // late final UserSubscriptionRepository userSubscriptionRepository;

  // Constructor initializes all the repositories, passing the Firestore instance.
  FirestoreHelper() {
    users = UserRepository(_db);
    // groups = GroupRepository(_db);
    // sessions = SessionRepository(_db);
    // sets = SetRepository(_db);
    // planning = PlanningRepository(_db);
    // onboarding = OnboardingRepository(_db);
    // completedSessionRepository = CompletedSessionRepository(_db);
    // userSubscriptionRepository = UserSubscriptionRepository();
  }

  /// Generates a new unique ID for a document within a given collection.
  String generateNewFirestoreId(String collectionPath) {
    return _db.collection(collectionPath).doc().id;
  }
}
