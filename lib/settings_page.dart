import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/theme_provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
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
    if (mounted) {
      // Pop all routes until the first one. The AuthWrapper will then handle
      // navigation to the sign-in page.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = widget.appUser;
    final role = _capitalize(user.userType.name);

    final appearanceAndAboutWidgets = [
      const Divider(),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      SwitchListTile(
        title: const Text('Dark Mode'),
        value: themeProvider.isDarkMode,
        onChanged: (value) {
          Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
        },
        secondary: const Icon(Icons.brightness_6),
      ),
      const Divider(),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.hasData ? snapshot.data!.version : '...';
          final buildNumber =
              snapshot.hasData ? snapshot.data!.buildNumber : '...';
          return ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App Version'),
            subtitle: Text('$version ($buildNumber)'),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                style: TextStyle(color: theme.colorScheme.onPrimary),
              ),
            ),
            title: Text(user.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${user.email} | $role'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ProfilePage(appUser: user),
                ),
              );
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child:
                Text('Account', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (user.userType == UserType.coach)
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('My Swimmers'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const MySwimmersPage(),
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log Out'),
            onTap: _signOut,
          ),
          ...appearanceAndAboutWidgets,
        ],
      ),
    );
  }
}