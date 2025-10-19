import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Safely access the theme, which is crucial for styling the page.
    // Storing it in a variable is a good practice for readability and performance,
    // as it avoids multiple lookups in the widget tree.
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        centerTitle: true,
      ),
      body: SafeArea(
        // Use a try-catch block to handle any unexpected layout errors during build time.
        // While unlikely in this static page, it's a robust way to prevent crashes.
        child: _buildBody(context, theme),
      ),
    );
  }

  /// Builds the main scrollable content of the page.
  Widget _buildBody(BuildContext context, ThemeData theme) {
    try {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 16),
            _buildLastUpdated(theme),
            const SizedBox(height: 16),
            _buildWelcomeText(theme),
            const SizedBox(height: 24),
            _buildSection(
              theme,
              title: '1. Use of Service',
              content:
              'You agree to use Swim Analyzer responsibly and in compliance with all applicable laws and regulations. '
                  'You must not misuse the app or attempt to gain unauthorized access to our systems.',
            ),
            _buildSection(
              theme,
              title: '2. Accounts',
              content:
              'To use certain features, you may need to create an account. You are responsible for maintaining the confidentiality of your login credentials and for all activities under your account.',
            ),
            _buildSection(
              theme,
              title: '3. Data & Privacy',
              content:
              'We respect your privacy and handle your data according to our Privacy Policy. '
                  'By using the app, you consent to our data collection and usage practices as outlined therein.',
            ),
            _buildSection(
              theme,
              title: '4. Modifications',
              content:
              'We may modify these Terms at any time. Continued use of the app after changes indicates your acceptance of the new Terms.',
            ),
            _buildSection(
              theme,
              title: '5. Contact',
              content:
              'For any questions about these Terms, please contact us at:\n\n'
                  '📧 support@swim-analyzer.app',
            ),
            const SizedBox(height: 40),
            _buildFooter(theme),
          ],
        ),
      );
    } catch (e, s) {
      // If a non-fatal error occurs during the build process, log it to Crashlytics.
      // This helps in monitoring UI rendering issues without crashing the app for the user.
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to build TermsOfServicePage body');
      // Return a fallback widget to prevent a crash.
      return const Center(child: Text('An unexpected error occurred.'));
    }
  }

  /// Builds the main title of the page.
  Widget _buildHeader(ThemeData theme) {
    // Using a null-aware cascade operator `?..` provides a fallback if textTheme or headlineSmall is null.
    // Although guaranteed to be non-null in standard Material apps, this is a defensive measure. [4]
    final style = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.bold,
    );

    return Text('Terms of Service', style: style);
  }

  /// Builds the "Last updated" text.
  Widget _buildLastUpdated(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Text('Last updated: October 2025\n', style: style);
  }

  /// Builds the introductory welcome text.
  Widget _buildWelcomeText(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.5);
    return Text(
      'Welcome to Swim Analyzer! These Terms of Service ("Terms") govern your access to and use of the Swim Analyzer app and related services provided by Swim Apps AB ("we", "our", or "us"). By using our app, you agree to these Terms.',
      style: style,
    );
  }

  /// Refactored from the original _buildSectionTitle and _buildSectionBody.
  /// This composite widget improves logical grouping by keeping section titles and bodies together.
  Widget _buildSection(ThemeData theme,
      {required String title, required String content}) {
    // Style for the section title. Defensive null-aware call is used.
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    // Style for the section body content.
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.5);

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 8.0),
          Text(content, style: bodyStyle),
        ],
      ),
    );
  }

  /// Builds the footer section with copyright information.
  Widget _buildFooter(ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Center(
      child: Text(
        '© 2025 Swim Apps AB. All rights reserved.',
        style: style,
      ),
    );
  }
}
