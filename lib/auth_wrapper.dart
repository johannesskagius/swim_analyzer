import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/revenue_cat/paywall_page.dart';
import 'package:swim_analyzer/sign_in_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

/// A class that holds the user's permission status.
/// This will be provided to the widget tree.
class PermissionLevel {
  final AppUser appUser;
  final bool hasSwimmerSubscription;
  final bool hasCoachSubscription;

  PermissionLevel({
    required this.appUser,
    this.hasSwimmerSubscription = false,
    this.hasCoachSubscription = false,
  });

  /// True if the user has any active subscription.
  bool get hasActiveSubscription =>
      hasSwimmerSubscription || hasCoachSubscription;

  /// True if the user has the coach entitlement.
  bool get isCoach => hasCoachSubscription;
}

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

// This widget now provides the PermissionLevel to the rest of the app.
class _SubscriptionWrapper extends StatefulWidget {
  final AppUser appUser;

  const _SubscriptionWrapper({required this.appUser});

  @override
  State<_SubscriptionWrapper> createState() => _SubscriptionWrapperState();
}

class _SubscriptionWrapperState extends State<_SubscriptionWrapper> {
  late final Future<PermissionLevel> _permissionFuture;

  @override
  void initState() {
    super.initState();
    _permissionFuture = _checkPermissions();
  }

  Future<PermissionLevel> _checkPermissions() async {
    try {
      // Log in to RevenueCat with the user's unique ID.
      await Purchases.logIn(widget.appUser.id);

      final CustomerInfo customerInfo = await Purchases.getCustomerInfo();

      // --- FIX: Use the correct, consistent entitlement identifiers ---
      final hasProSwimmer =
          customerInfo.entitlements.active.containsKey('Swimmer subscription');
      final hasProCoach =
          customerInfo.entitlements.active.containsKey('Coach subscription');

      debugPrint(
          'Active Entitlements: ${customerInfo.entitlements.active.keys}');
      debugPrint(
          'Active Entitlements: ${customerInfo.entitlements.active}');

      var permissionLevel = PermissionLevel(
        appUser: widget.appUser,
        hasSwimmerSubscription: hasProSwimmer,
        hasCoachSubscription: hasProCoach,
      );

      debugPrint(
          'Has active subscription: ${permissionLevel.hasActiveSubscription.toString()}');
      debugPrint(
          'Has coach subscription: ${permissionLevel.hasCoachSubscription.toString()}');

      return permissionLevel;
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: 'RevenueCat permission check failed',
      );
      // On failure, return a default PermissionLevel with no access.
      return PermissionLevel(appUser: widget.appUser);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PermissionLevel>(
      future: _permissionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Verifying subscription...');
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return PaywallPage(appUser: widget.appUser);
        }

        final permissions = snapshot.requireData;

        if (permissions.hasActiveSubscription) {
          // If the user has a subscription, provide the `PermissionLevel`
          // object to the HomePage and its descendants.
          return Provider<PermissionLevel>.value(
            value: permissions,
            child: const HomePage(),
          );
        } else {
          // Otherwise, show the paywall.
          return PaywallPage(appUser: widget.appUser);
        }
      },
    );
  }
}

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
