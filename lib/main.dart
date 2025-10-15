import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/theme_provider.dart';
import 'package:swim_apps_shared/auth_service.dart';
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
    final AuthService authService = AuthService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<FirestoreHelper>(
          create: (_) => FirestoreHelper(firestore: FirebaseFirestore.instance, authService: authService),
        ),
        Provider<UserRepository>(
          create: (_) => UserRepository(FirebaseFirestore.instance, authService: authService),
        ),
        Provider<AnalyzesRepository>(
          create: (_) => AnalyzesRepository(FirebaseFirestore.instance),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Swim Analyzer',
            theme: themeProvider.themeData,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}
