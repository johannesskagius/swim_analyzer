import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/sign_in_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

/// Determines whether to show the sign-in page or the main app content
/// based on the user's authentication state.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder listens to authentication state changes from Firebase.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // While waiting for the initial auth state, show a loading screen.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // If the snapshot has user data, the user is authenticated.
        if (authSnapshot.hasData) {
          // Now that we know the user is authenticated, we fetch their profile data.
          // We use a ValueKey to ensure this widget rebuilds if the user ID changes.
          return _ProfileLoader(key: ValueKey(authSnapshot.data!.uid));
        }

        // If there's no user data, show the sign-in page.
        return const SignInPage();
      },
    );
  }
}

/// A helper widget to handle the logic of loading the user profile after authentication.
/// This cleans up the main AuthWrapper's build method.
class _ProfileLoader extends StatelessWidget {
  const _ProfileLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final userRepository = context.read<UserRepository>();

    return FutureBuilder<AppUser?>(
      future: userRepository.getMyProfile(),
      builder: (context, profileSnapshot) {
        // While the profile data is loading, continue showing the loading screen.
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // If there's an error or no profile data is found, it's an invalid state.
        if (profileSnapshot.hasError || !profileSnapshot.hasData) {
          // Log the specific error to Crashlytics for debugging.
          if (profileSnapshot.hasError) {
            FirebaseCrashlytics.instance.recordError(
              profileSnapshot.error,
              profileSnapshot.stackTrace,
              reason: 'Failed to load user profile from repository.',
              fatal: false, // It's a handled error, not a crash.
            );
          } else {
            // Log the case where the profile document might be missing.
            FirebaseCrashlytics.instance.log(
                'User is authenticated but no profile data was found in the repository. Forcing sign-out.');
          }

          // The safest action is to sign the user out to return them to the sign-in flow.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FirebaseAuth.instance.signOut();
          });

          return const _LoadingScreen();
        }

        // If profile data is successfully loaded, link it to our analytics.
        final appUser = profileSnapshot.requireData!;

        // --- Set User Identifiers for Analytics and Crashlytics ---
        FirebaseCrashlytics.instance.setUserIdentifier(appUser.id);
        FirebaseAnalytics.instance.setUserId(id: appUser.id);

        // --- Set a custom property for filtering in Analytics ---
        FirebaseAnalytics.instance
            .setUserProperty(name: 'user_type', value: appUser.userType.name);

        return HomePage(appUser: appUser);
      },
    );
  }
}

/// A simple, reusable loading screen.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}