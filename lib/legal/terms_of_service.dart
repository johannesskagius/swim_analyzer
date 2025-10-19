import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
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
  // Refactored _signOut to handle potential exceptions from FirebaseAuth.
  // A try-catch block ensures that if the sign-out process fails,
  // the app won't crash. The error is logged to Crashlytics for diagnostics.
  // A SnackBar provides immediate user feedback about the failure.
  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      // Check if the widget is still in the tree before using its context.
      // This prevents errors if the user navigates away while sign-out is pending.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e, s) {
      // Log the specific authentication error to Firebase Crashlytics.
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to sign out');
      // Inform the user that the sign-out failed.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: ${e.message}')),
        );
      }
    }
  }

  // The _capitalize function remains simple and effective.
  // No changes are needed as it's already null-safe and handles empty strings.
  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '';

  // This widget builder function is clear and has no complex logic.
  // It remains as is for readability.
  Widget _buildSectionHeader(String title, {IconData? icon}) {
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

  // This widget builder function is clear and has no complex logic.
  // It remains as is for readability.
  Widget _buildLegalSection() {
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

  // Refactored the 'About' section to better handle states in the FutureBuilder.
  // Added explicit checks for connection state and errors.
  // If the future fails (e.g., package_info fails), the error is logged
  // to Crashlytics and a user-friendly error message is displayed in the UI
  // instead of crashing or showing incomplete data.
  Widget _buildAboutSection() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        // Handle error state: log the error and show an informative message.
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

        // Handle loading state: show a placeholder.
        if (snapshot.connectionState != ConnectionState.done) {
          return const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('App Version'),
            subtitle: Text('Loading...'),
          );
        }

        // Handle success state: safely access data.
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

  // This widget builder function is clear and has no complex logic.
  // The sign-out logic is handled in the `onTap` callback, which is now more robust.
  // It remains as is for readability.
  Widget _buildActionsSection() {
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

        // A null check `== true` is safer than `if (confirmed)`.
        // If the dialog is dismissed, `confirmed` will be null.
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
            // Added a null-safety check for user.name to prevent a range error
            // on `user.name[0]` if the name is unexpectedly empty.
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
            ),
            title: Text(user.name),
            subtitle: Text('${user.email} • $role'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfilePage(appUser: user)),
            ),
          ),
          if (user.userType == UserType.coach)
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('My Swimmers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MySwimmersPage()),
              ),
            ),
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
