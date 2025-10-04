import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/auth_wrapper.dart';
import 'package:swim_analyzer/race_repository.dart';
import 'package:swim_analyzer/user_repository.dart';

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
        Provider<FirebaseFirestore>(
          create: (_) => FirebaseFirestore.instance,
        ),
        ProxyProvider<FirebaseFirestore, UserRepository>(
          update: (_, db, __) => UserRepository(db),
        ),
        ProxyProvider<FirebaseFirestore, RaceRepository>(
          update: (_, db, __) => RaceRepository(db),
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
