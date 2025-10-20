import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/revenue_cat/paywall_page.dart';
import 'package:swim_analyzer/sign_in_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (authSnapshot.hasData) {
          // User is authenticated with Firebase
          return _ProfileLoader(key: ValueKey(authSnapshot.data!.uid));
        }

        // User is not authenticated, log them out of RevenueCat too.
        Purchases.logOut();
        return const SignInPage();
      },
    );
  }
}

class _ProfileLoader extends StatelessWidget {
  const _ProfileLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final userRepository = context.read<UserRepository>();

    return FutureBuilder<AppUser?>(
      future: userRepository.getMyProfile(),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Loading profile...');
        }

        if (profileSnapshot.hasError || !profileSnapshot.hasData) {
          FirebaseCrashlytics.instance.recordError(
            profileSnapshot.error,
            profileSnapshot.stackTrace,
            reason: 'Failed to load user profile.',
          );
          // If profile fails to load, sign out to prevent an invalid state.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FirebaseAuth.instance.signOut();
          });
          return const _LoadingScreen();
        }

        final appUser = profileSnapshot.requireData!;

        // Profile loaded, now check for an active subscription.
        return _SubscriptionWrapper(appUser: appUser);
      },
    );
  }
}

// New widget to handle RevenueCat subscription logic.
class _SubscriptionWrapper extends StatefulWidget {
  final AppUser appUser;

  const _SubscriptionWrapper({required this.appUser});

  @override
  State<_SubscriptionWrapper> createState() => _SubscriptionWrapperState();
}

class _SubscriptionWrapperState extends State<_SubscriptionWrapper> {
  // This future holds the result of our subscription check.
  late final Future<bool> _hasActiveSubscriptionFuture;

  @override
  void initState() {
    super.initState();
    _hasActiveSubscriptionFuture = _checkSubscriptionStatus();
  }

  Future<bool> _checkSubscriptionStatus() async {
    try {
      // Log in to RevenueCat with the user's unique ID.
      await Purchases.logIn(widget.appUser.id);

      // Get the latest customer info.
      final CustomerInfo customerInfo = await Purchases.getCustomerInfo();

      // Check if the user has an active entitlement in RevenueCat.
      final hasProSwimmer =
          customerInfo.entitlements.active.containsKey('entldd89ea41a6');
      final hasProCoach =
          customerInfo.entitlements.active.containsKey('entlb23409183b');

      debugPrint('Debugprint: Has pro coach: $hasProCoach');
      debugPrint('Debugprint: Has pro swimmer: $hasProSwimmer');
      return hasProSwimmer || hasProCoach;
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: 'RevenueCat subscription check failed',
      );
      // If the check fails, deny access as a safe default.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasActiveSubscriptionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Verifying subscription...');
        }

        // Handle potential errors during the future execution.
        if (snapshot.hasError) {
          FirebaseCrashlytics.instance.recordError(
            snapshot.error,
            snapshot.stackTrace,
            reason: 'Subscription check FutureBuilder failed',
          );
          // Show paywall on error as a safe fallback.
          return PaywallPage(appUser: widget.appUser);
        }

        final hasActiveSubscription = snapshot.data ?? false;

        if (hasActiveSubscription) {
          // User has an active subscription, grant access to the app.
          return HomePage(appUser: widget.appUser);
        } else {
          // User does not have an active subscription, show the paywall.
          return PaywallPage(appUser: widget.appUser);
        }
      },
    );
  }
}

/// A simple, reusable loading screen with an optional message.
class _LoadingScreen extends StatelessWidget {
  final String? message;

  const _LoadingScreen({this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 20),
              Text(message!),
            ]
          ],
        ),
      ),
    );
  }
}
