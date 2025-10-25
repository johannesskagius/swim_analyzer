import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:swim_analyzer/home_page.dart';
import 'package:swim_analyzer/revenue_cat/paywall_page.dart';
import 'package:swim_analyzer/sign_in_page.dart';
import 'package:swim_apps_shared/objects/user/swimmer.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

/// Represents a user's entitlements/subscriptions.
class PermissionLevel {
  final AppUser appUser;
  final bool hasSwimmerSubscription;
  final bool hasCoachSubscription;

  const PermissionLevel({
    required this.appUser,
    this.hasSwimmerSubscription = false,
    this.hasCoachSubscription = false,
  });

  bool get hasActiveSubscription =>
      hasSwimmerSubscription || hasCoachSubscription;

  bool get isCoach => hasCoachSubscription;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PermissionLevel &&
              runtimeType == other.runtimeType &&
              appUser.id == other.appUser.id &&
              hasSwimmerSubscription == other.hasSwimmerSubscription &&
              hasCoachSubscription == other.hasCoachSubscription;

  @override
  int get hashCode =>
      appUser.id.hashCode ^
      hasSwimmerSubscription.hashCode ^
      hasCoachSubscription.hashCode;
}

/// Entry point wrapper that switches between auth states.
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
          // Firebase user exists → load profile
          return _ProfileLoader(key: ValueKey(authSnapshot.data!.uid));
        }

        // User is not authenticated
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && !currentUser.isAnonymous) {
          // Avoid the "logout called for anonymous user" error
          unawaited(Purchases.logOut());
        }

        return const SignInPage();
      },
    );
  }
}

/// Loads the Firestore user profile, with retry logic for new signups.
class _ProfileLoader extends StatefulWidget {
  const _ProfileLoader({super.key});

  @override
  State<_ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<_ProfileLoader> {
  static const int _maxRetries = 8;
  int _attempt = 0;
  AppUser? _appUser;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadProfileWithRetry();
  }

  Future<void> _loadProfileWithRetry() async {
    final userRepository = context.read<UserRepository>();
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      _signOutWithError('Firebase user disappeared during profile load');
      return;
    }

    while (_attempt < _maxRetries) {
      try {
        final profile = await userRepository.getMyProfile();
        if (profile != null) {
          if (!mounted) return;
          setState(() {
            _appUser = profile;
            _isLoading = false;
          });
          return;
        }

        // If profile not found → wait and retry
        _attempt++;
        debugPrint(
          "⏳ Profile not found yet for ${firebaseUser.uid} (attempt $_attempt/$_maxRetries)",
        );
        await Future.delayed(const Duration(seconds: 1));
      } catch (e, s) {
        FirebaseCrashlytics.instance.recordError(
          e,
          s,
          reason: 'Profile load attempt $_attempt failed.',
        );
        _attempt++;
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // 🚀 Still no profile? Create one automatically
    try {
      debugPrint("🆕 No Firestore profile found after retries. Creating default profile for ${firebaseUser.uid}...");
      final newUser = Swimmer(
        id: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'New User',
        email: firebaseUser.email ?? '',

      );
      await userRepository.createAppUser(newUser: newUser);

      if (!mounted) return;
      setState(() {
        _appUser = newUser;
        _isLoading = false;
      });
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Auto-create Firestore user after missing profile failed');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }


  void _signOutWithError(String reason) {
    FirebaseCrashlytics.instance.log('Forced sign-out: $reason');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirebaseAuth.instance.signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _LoadingScreen(message: 'Loading your profile...');
    }

    if (_hasError || _appUser == null) {
      // Instead of kicking out the user, show a friendly waiting screen
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 64),
              const SizedBox(height: 20),
              const Text(
                'Setting up your profile...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              const Text(
                'This can take a few seconds. If it doesn’t finish, try restarting the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Back to Sign-In'),
              ),
            ],
          ),
        ),
      );
    }

    final appUser = _appUser!;
    return _SubscriptionWrapper(appUser: appUser);
  }
}

/// Wraps subscription logic around the loaded AppUser.
class _SubscriptionWrapper extends StatefulWidget {
  final AppUser appUser;
  const _SubscriptionWrapper({required this.appUser});

  @override
  State<_SubscriptionWrapper> createState() => _SubscriptionWrapperState();
}

class _SubscriptionWrapperState extends State<_SubscriptionWrapper> {
  PermissionLevel? _permissionLevel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    _initializePermissions();
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    super.dispose();
  }

  Future<void> _initializePermissions() async {
    try {
      await Purchases.logIn(widget.appUser.id);
      final info = await Purchases.getCustomerInfo();
      _updatePermissions(info);
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Initial RevenueCat permission check failed');
      if (!mounted) return;
      setState(() {
        _permissionLevel = PermissionLevel(appUser: widget.appUser);
        _isLoading = false;
      });
    }
  }

  void _onCustomerInfoUpdated(CustomerInfo info) {
    if (kDebugMode) {
      debugPrint("✅ CustomerInfo updated: ${info.entitlements.active.keys}");
    }
    _updatePermissions(info);
  }

  void _updatePermissions(CustomerInfo info) {
    final hasSwimmer =
    info.entitlements.active.containsKey('swim_analyzer_pro_single');
    final hasCoach =
    info.entitlements.active.containsKey('swim_analyzer_pro_team');

    final newPerms = PermissionLevel(
      appUser: widget.appUser,
      hasSwimmerSubscription: hasSwimmer,
      hasCoachSubscription: hasCoach,
    );

    if (!mounted) return;
    if (_permissionLevel != newPerms || _isLoading) {
      setState(() {
        _permissionLevel = newPerms;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _permissionLevel == null) {
      return const _LoadingScreen(message: 'Verifying subscription...');
    }

    final perms = _permissionLevel!;
    return perms.hasActiveSubscription
        ? Provider<PermissionLevel>.value(
      value: perms,
      child: const HomePage(),
    )
        : PaywallPage(appUser: widget.appUser);
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
