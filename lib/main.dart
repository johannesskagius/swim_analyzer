import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';


import 'auth_wrapper.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirestoreHelper>(
          create: (_) => FirestoreHelper(firestore: FirebaseFirestore.instance),
        ),
        Provider<UserRepository>(
          create: (_) => UserRepository(FirebaseFirestore.instance),
        ),
        Provider<RaceRepository>(
          create: (_) => RaceRepository(FirebaseFirestore.instance),
        ),
      ],
      child: MaterialApp(
        title: 'Swim Analyzer',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}
