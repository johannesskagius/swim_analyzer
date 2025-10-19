import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis_repository.dart';
import 'package:swim_analyzer/theme_provider.dart';
import 'package:swim_apps_shared/auth_service.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import 'auth_wrapper.dart';
import 'firebase_options.dart';

void main() async {
  // Use runZonedGuarded to catch errors that occur outside the Flutter framework.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // Pass all uncaught "fatal" errors from the framework to Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    runApp(const MyApp());
  }, (error, stack) {
    // This will catch any errors that occur during the app initialization.
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Static instances for Analytics and its observer
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: analytics);

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<FirestoreHelper>(
          create: (_) => FirestoreHelper(
              firestore: FirebaseFirestore.instance, authService: authService),
        ),
        Provider<UserRepository>(
          create: (_) => UserRepository(FirebaseFirestore.instance,
              authService: authService),
        ),
        Provider<AnalyzesRepository>(
          create: (_) => AnalyzesRepository(FirebaseFirestore.instance),
        ),
        // Correctly provide the instance to the repository
        Provider<StrokeAnalysisRepository>(
          create: (_) =>
              StrokeAnalysisRepository(firestore: FirebaseFirestore.instance),
        ),
        // Provide the FirebaseAnalytics instance to the widget tree
        Provider<FirebaseAnalytics>.value(value: analytics),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Swim Analyzer',
            theme: themeProvider.themeData,
            // Add the observer for automatic screen view tracking
            navigatorObservers: <NavigatorObserver>[observer],
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}
