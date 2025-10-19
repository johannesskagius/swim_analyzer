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
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '';

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

  Widget _buildAboutSection() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        final buildNumber = snapshot.data?.buildNumber ?? '...';

        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('App Version'),
          subtitle: Text('$version ($buildNumber)'),
        );
      },
    );
  }

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

        if (confirmed == true) {
          _signOut();
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
            onChanged: (_) => themeProvider.toggleTheme(),
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