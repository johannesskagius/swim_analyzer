import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/sign_in_page.dart';
import 'package:swim_apps_shared/helpers/user_repository.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // Show a loading indicator while the connection is being established.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If the snapshot has data, the user is logged in (anonymous or not).
        if (authSnapshot.hasData) {
          // User is authenticated, now fetch the user profile.
          return FutureBuilder(
            // We use a key here to ensure the FutureBuilder re-executes if the user changes.
            key: ValueKey(authSnapshot.data!.uid),
            future: context.read<UserRepository>().getMyProfile(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (profileSnapshot.hasError || !profileSnapshot.hasData) {
                // Optionally handle profile loading error more gracefully
                return Scaffold(
                  body: Center(
                    child: Text(
                        'Error loading user profile: ${profileSnapshot.error}'),
                  ),
                );
              }

              return HomePage(appUser: profileSnapshot.requireData!);
            },
          );
        }
        // Otherwise, the user is not logged in.
        return const SignInPage();
      },
    );
  }
}
