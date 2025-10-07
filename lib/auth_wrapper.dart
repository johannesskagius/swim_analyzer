import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/sign_in_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show a loading indicator while the connection is being established.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If the snapshot has data, the user is logged in.
        if (snapshot.hasData && !snapshot.data!.isAnonymous) {
          return const HomePage();
        }

        // Otherwise, the user is not logged in.
        return const SignInPage();
      },
    );
  }
}
