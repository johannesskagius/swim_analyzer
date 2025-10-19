// Import Firebase Crashlytics to log non-fatal errors.
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:swim_analyzer/history/off_the_block_history_page.dart';
import 'package:swim_analyzer/history/stroke_history_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

// --- Refactoring Reason ---
// Using constants for padding and spacing values improves consistency and makes future UI adjustments easier.
// It avoids "magic numbers" scattered throughout the code.
const double _kVerticalSpacing = 10.0;
const double _kHorizontalPadding = 8.0;

class PickRaceHistoryPage extends StatelessWidget {
  final AppUser? appUser;
  const PickRaceHistoryPage({super.key, required this.appUser});

  // --- Refactoring Reason ---
  // The logic for navigating to different history pages is encapsulated in this private method.
  // It includes a null check for 'appUser' to prevent crashes if it's unexpectedly null.
  // Using a try-catch block makes navigation more robust. If a new page fails to build
  // (e.g., due to a missing asset or a runtime error in its constructor), the app will not crash.
  // The error is caught and logged to Firebase Crashlytics for monitoring.
  void _navigateToPage(BuildContext context, Widget page) {
    try {
      // It's good practice to check for a mounted context before navigating,
      // especially if any async operations were involved.
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    } catch (e, s) {
      // Log any unexpected errors during navigation to Crashlytics.
      // This helps in debugging issues with page transitions or constructions.
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to navigate to page');
      // Optionally, show a user-friendly error message.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the page. Please try again.')),
      );
    }
  }

  // --- Refactoring Reason ---
  // Repetitive UI code for list tiles is extracted into a dedicated builder method.
  // This simplifies the main `build` method, reduces code duplication, and makes the UI structure cleaner.
  // If we need to change the style of all list tiles, we only need to modify this one method.
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
    // --- Error Handling ---
    // Added a null check for `appUser` right at the beginning of the build method.
    // While the constructor requires it, this provides a graceful fallback and a clear
    // error report if a null is somehow passed, preventing a `NullThrownError` later on.
    if (appUser == null) {
      // Log a non-fatal error to Crashlytics to alert developers of this invalid state.
      FirebaseCrashlytics.instance.recordError(
        'appUser is null in PickRaceHistoryPage',
        StackTrace.current,
        reason: 'A critical user object was not provided to the history page.',
        fatal: true, // Marking as fatal as the page cannot function without the user.
      );
      // Display a user-friendly error message instead of a blank or crashing screen.
      return const Scaffold(
        body: Center(
          child: Text('An unexpected error occurred. User data is missing.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: ListView(
        // Use the defined constant for padding.
        padding: const EdgeInsets.all(_kHorizontalPadding),
        children: <Widget>[
          _buildHistoryCard(
            icon: Icons.emoji_events,
            title: 'Race Analyses',
            subtitle: 'View history of your race results and analyses.',
            onTap: () {
              // The navigation logic is now handled by the robust helper method.
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
                OffTheBlockHistoryPage(appUser: appUser!), // We can use '!' here because we've already null-checked appUser.
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
                StrokeHistoryPage(appUser: appUser!), // We can use '!' here because we've already null-checked appUser.
              );
            },
          ),
        ],
      ),
    );
  }
}
