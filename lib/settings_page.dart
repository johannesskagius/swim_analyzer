import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart'; // <-- ADD THIS
import 'package:swim_analyzer/revenue_cat/manage_subscription_page.dart';
import 'package:swim_analyzer/revenue_cat/purchases_service.dart';
import 'package:swim_analyzer/theme_provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import 'legal/privacy_policy.dart';
import 'legal/terms_of_service.dart';
import 'profile/my_swimmers_page.dart';
import 'profile/profile_page.dart';

class SettingsPage extends StatefulWidget {
  final AppUser appUser;

  const SettingsPage({super.key, required this.appUser});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // --- NEW: State for subscription info ---
  bool _isLoadingSubscription = true;
  String _subscriptionInfo = 'Basic'; // Default value

  @override
  void initState() {
    super.initState();
    _fetchSubscriptionInfo(); // Fetch info when the page loads
  }

  // --- NEW: Method to get subscription details ---
  Future<void> _fetchSubscriptionInfo() async {
    try {
      final CustomerInfo customerInfo = await Purchases.getCustomerInfo();
      String activeEntitlement = 'Basic'; // Default to 'Basic'

      if (customerInfo.entitlements.active.isNotEmpty) {
        // Get the identifier of the first active entitlement
        final entitlement = customerInfo.entitlements.active.values.first;
        activeEntitlement =
            _formatEntitlementIdentifier(entitlement.productIdentifier);
      }

      if (mounted) {
        setState(() {
          _subscriptionInfo = activeEntitlement;
          _isLoadingSubscription = false;
        });
      }
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Failed to fetch subscription info on SettingsPage');
      if (mounted) {
        setState(() {
          _subscriptionInfo = 'Could not load';
          _isLoadingSubscription = false;
        });
      }
    }
  }

  // --- NEW: Helper to make entitlement names user-friendly ---
  String _formatEntitlementIdentifier(String identifier) {
    // Example: 'pro_swimmer' becomes 'Pro Swimmer'
    return identifier
        .split('_')
        .map((word) => word.isNotEmpty
        ? '${word[0].toUpperCase()}${word.substring(1)}'
        : '')
        .join(' ');
  }

  // --- MODIFIED: Ensure RevenueCat logout is called ---
  Future<void> _signOut() async {
    try {
      // First, log out from RevenueCat to clear the user cache
      await PurchasesService.logout();
      // Then, sign out from Firebase
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e, s) {
      FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'Failed to sign out');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: ${e.message}')),
        );
      }
    }
  }

  Widget _buildSubscriptionSection() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Subscription'),
          subtitle: _isLoadingSubscription
              ? const Text('Loading...')
              : Text(_subscriptionInfo),
          trailing: const Icon(Icons.chevron_right),
          // Add a chevron
          // Make the whole ListTile tappable
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ManageSubscriptionPage(),
              ),
            );
          },
        ),
      ],
    );
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '';

  Widget _buildSectionHeader(String title, {IconData? icon}) {
    // ... (This method remains unchanged)
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 20, color: theme.colorScheme.primary),
          if (icon != null) const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// --- NEW: Fetches and displays the coach's name ---
  Widget _buildCoachInfo(String coachId) {
    // Use the UserRepository from the provider to fetch user details.
    final userRepository = context.read<UserRepository>();
    return FutureBuilder<AppUser?>(
      future: userRepository.getUserDocument(coachId),
      builder: (context, snapshot) {
        String coachName = 'Loading...';
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData && snapshot.data != null) {
            coachName = snapshot.data!.name;
          } else {
            coachName = 'Not available';
            // Log if the coach's profile can't be fetched.
            FirebaseCrashlytics.instance.recordError(
              snapshot.error ?? 'Coach not found for id $coachId',
              snapshot.stackTrace,
              reason: 'Failed to fetch coach profile in SettingsPage',
            );
          }
        }
        return ListTile(
          leading: const Icon(Icons.person_search_outlined),
          title: const Text('Coach'),
          subtitle: Text(coachName),
        );
      },
    );
  }

  /// --- NEW: Fetches and displays the club's name ---
  Widget _buildClubInfo(String clubId) {
    // Use the ClubRepository from the provider to fetch club details.
    final clubRepository = context.read<ClubRepository>();
    return FutureBuilder<SwimClub?>(
      future: clubRepository.getClub(clubId),
      builder: (context, snapshot) {
        String clubName = 'Loading...';
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData && snapshot.data != null) {
            clubName = snapshot.data!.name;
          } else {
            clubName = 'Not available';
            // Log if the club's details can't be fetched.
            FirebaseCrashlytics.instance.recordError(
              snapshot.error ?? 'Club not found for id $clubId',
              snapshot.stackTrace,
              reason: 'Failed to fetch club details in SettingsPage',
            );
          }
        }
        return ListTile(
          leading: const Icon(Icons.pool_outlined),
          title: const Text('Club'),
          subtitle: Text(clubName),
        );
      },
    );
  }

  Widget _buildLegalSection() {
    // ... (This method remains unchanged)
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: const Text('Terms of Service'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TermsOfServicePage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy Policy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.balance_outlined),
          title: const Text('Open Source Licenses'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Swim Analyzer',
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    // ... (This method remains unchanged)
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          FirebaseCrashlytics.instance.recordError(
            snapshot.error,
            snapshot.stackTrace,
            reason: 'Failed to get package info',
          );
          return const ListTile(
            leading: Icon(Icons.error_outline, color: Colors.red),
            title: Text('App Version'),
            subtitle: Text('Could not load version info'),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('App Version'),
            subtitle: Text('Loading...'),
          );
        }
        final version = snapshot.data?.version ?? 'N/A';
        final buildNumber = snapshot.data?.buildNumber ?? 'N/A';
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('App Version'),
          subtitle: Text('$version ($buildNumber)'),
        );
      },
    );
  }

  Widget _buildActionsSection() {
    // ... (This method remains unchanged)
    return ListTile(
      leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
      title: Text('Sign Out',
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
      onTap: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _signOut();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final user = widget.appUser;
    final role = _capitalize(user.userType.name);

    return Scaffold(
      body: ListView(
        children: [
          _buildSectionHeader('Account', icon: Icons.person_outline),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child:
              Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
            ),
            title: Text(user.name),
            subtitle: Text('${user.email} • $role'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfilePage(appUser: user)),
            ),
          ),
          if (user.clubId?.isNotEmpty == true) _buildClubInfo(user.clubId!),
          // Show "My Swimmers" for coaches
          if (user.userType == UserType.coach)
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('My Swimmers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MySwimmersPage()),
              ),
            ),
          // --- MODIFIED: Show Coach and Club for Swimmers ---
          if (user.userType == UserType.swimmer) ...[
            // Fetch and display Coach Name
            if (user.creatorId?.isNotEmpty == true)
              _buildCoachInfo(user.creatorId!),

            // Fetch and display Club Name
          ],

          // --- Subscription Section ---
          const Divider(height: 24),
          _buildSectionHeader('Subscription',
              icon: Icons.workspace_premium_outlined),
          _buildSubscriptionSection(),
          // --- END NEW SECTION ---

          const Divider(height: 24),
          _buildSectionHeader('Appearance', icon: Icons.palette_outlined),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: themeProvider.isDarkMode,
            onChanged: (value) => themeProvider.toggleTheme(),
            secondary: const Icon(Icons.dark_mode_outlined),
          ),
          const Divider(height: 24),
          _buildSectionHeader('About', icon: Icons.info_outline),
          _buildAboutSection(),
          const Divider(height: 24),
          _buildSectionHeader('Legal', icon: Icons.gavel_outlined),
          _buildLegalSection(),
          const Divider(height: 24),
          _buildActionsSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}