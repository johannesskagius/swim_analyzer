import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
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

  // Added for easy state comparison to prevent unnecessary rebuilds.
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

// REFACTORED: This widget now uses a listener for real-time subscription updates.
class _SubscriptionWrapper extends StatefulWidget {
  final AppUser appUser;

  const _SubscriptionWrapper({required this.appUser});

  @override
  State<_SubscriptionWrapper> createState() => _SubscriptionWrapperState();
}

// REFACTORED: This state now manages permissions reactively.
// It no longer uses a FutureBuilder, but instead listens to a stream of updates
// from RevenueCat and rebuilds its child UI accordingly. This is more robust
// for handling subscription changes that happen outside the app (e.g., from
// the App Store settings) or when entitlement access is granted with a delay.
class _SubscriptionWrapperState extends State<_SubscriptionWrapper> {
  PermissionLevel? _permissionLevel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 1. Set up the listener to react to any changes in customer info.
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    // 2. Fetch the initial permission state when the widget is first built.
    _initializePermissions();
  }

  @override
  void dispose() {
    // 3. Clean up the listener when the widget is removed from the tree.
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    super.dispose();
  }

  /// This function is the callback for the RevenueCat listener.
  /// It's triggered whenever subscription information changes.
  void _onCustomerInfoUpdated(CustomerInfo customerInfo) {
    if (kDebugMode) {
      debugPrint("✅ CustomerInfo Listener Fired!");
      debugPrint("Listener - Active Entitlements: ${customerInfo.entitlements.active.keys}");
    }
    _updatePermissionsFromInfo(customerInfo);
  }

  /// Fetches the initial customer info from RevenueCat.
  Future<void> _initializePermissions() async {
    try {
      // It's good practice to log in to ensure the user context is correct.
      await Purchases.logIn(widget.appUser.id);
      final customerInfo = await Purchases.getCustomerInfo();
      _updatePermissionsFromInfo(customerInfo);
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s,
        reason: 'Initial RevenueCat permission check failed',
      );
      // If the initial check fails, default to no permissions.
      if (mounted) {
        setState(() {
          _permissionLevel = PermissionLevel(appUser: widget.appUser);
          _isLoading = false;
        });
      }
    }
  }

  /// Centralized logic to process `CustomerInfo` and update the state.
  /// This is called by both the initial fetch and the listener.
  void _updatePermissionsFromInfo(CustomerInfo customerInfo) {
    final hasProSwimmer =
    customerInfo.entitlements.active.containsKey('swim_analyzer_pro_single');
    final hasProCoach =
    customerInfo.entitlements.active.containsKey('swim_analyzer_pro_team');

    final newPermissionLevel = PermissionLevel(
      appUser: widget.appUser,
      hasSwimmerSubscription: hasProSwimmer,
      hasCoachSubscription: hasProCoach,
    );

    // Only call setState if the permission level has actually changed or if
    // we are moving out of the initial loading state. This prevents
    // unnecessary rebuilds of the widget tree.
    if (mounted && (_permissionLevel != newPermissionLevel || _isLoading)) {
      setState(() {
        _permissionLevel = newPermissionLevel;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // While loading, show a simple loading screen.
    if (_isLoading || _permissionLevel == null) {
      return const _LoadingScreen(message: 'Verifying subscription...');
    }

    final permissions = _permissionLevel!;

    // Based on the current permission state, show either the app or the paywall.
    // This will automatically rebuild whenever the listener fires and updates the state.
    if (permissions.hasActiveSubscription) {
      return Provider<PermissionLevel>.value(
        value: permissions,
        child: const HomePage(),
      );
    } else {
      return PaywallPage(appUser: widget.appUser);
    }
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