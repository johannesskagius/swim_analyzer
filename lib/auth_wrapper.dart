
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
        // User is logged in
        if (snapshot.connectionState == ConnectionState.active && snapshot.hasData) {
          return const HomePage();
        }

        // User is not logged in
        return const SignInPage();
      },
    );
  }
}
