// Import Firebase Crashlytics to log non-fatal errors.
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:swim_analyzer/history/off_the_block_history_page.dart';
// FIX: Added the missing import for RaceHistoryPage.
import 'package:swim_analyzer/history/stroke_history_page.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/race_analyzes/race_history_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

const double _kVerticalSpacing = 10.0;
const double _kHorizontalPadding = 8.0;

class PickRaceHistoryPage extends StatelessWidget {
  final AppUser? appUser;
  const PickRaceHistoryPage({super.key, required this.appUser});

  void _navigateToPage(BuildContext context, Widget page) {
    try {
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to navigate to page');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the page. Please try again.')),
      );
    }
  }

  Widget _buildHistoryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 40),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (appUser == null) {
      FirebaseCrashlytics.instance.recordError(
        'appUser is null in PickRaceHistoryPage',
        StackTrace.current,
        reason: 'A critical user object was not provided to the history page.',
        fatal: true,
      );
      return const Scaffold(
        body: Center(
          child: Text('An unexpected error occurred. User data is missing.'),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(_kHorizontalPadding),
        children: <Widget>[
          _buildHistoryCard(
            icon: Icons.emoji_events,
            title: 'Race Analyses',
            subtitle: 'View history of your race results and analyses.',
            onTap: () {
              _navigateToPage(
                context,
                RaceHistoryPage(brandIconAssetPath: 'assets/icon/icon.png'),
              );
            },
          ),
          const SizedBox(height: _kVerticalSpacing),
          _buildHistoryCard(
            icon: Icons.start,
            title: 'Start Analyses',
            subtitle: 'View history of your "Off the Block" start analyses.',
            onTap: () {
              _navigateToPage(
                context,
                OffTheBlockHistoryPage(appUser: appUser!),
              );
            },
          ),
          const SizedBox(height: _kVerticalSpacing),
          _buildHistoryCard(
            icon: Icons.pool,
            title: 'Stroke Analyses',
            subtitle: 'View history of your stroke efficiency analyses.',
            onTap: () {
              _navigateToPage(
                context,
                StrokeHistoryPage(appUser: appUser!),
              );
            },
          ),
        ],
      ),
    );
  }
}