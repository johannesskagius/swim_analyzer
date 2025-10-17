import 'package:flutter/material.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Terms of Service',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Last updated: October 2025\n',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to Swim Analyzer! These Terms of Service ("Terms") govern your access to and use of the Swim Analyzer app and related services provided by Swim Apps AB ("we", "our", or "us"). By using our app, you agree to these Terms.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(theme, '1. Use of Service'),
              _buildSectionBody(
                theme,
                'You agree to use Swim Analyzer responsibly and in compliance with all applicable laws and regulations. '
                    'You must not misuse the app or attempt to gain unauthorized access to our systems.',
              ),
              _buildSectionTitle(theme, '2. Accounts'),
              _buildSectionBody(
                theme,
                'To use certain features, you may need to create an account. You are responsible for maintaining the confidentiality of your login credentials and for all activities under your account.',
              ),
              _buildSectionTitle(theme, '3. Data & Privacy'),
              _buildSectionBody(
                theme,
                'We respect your privacy and handle your data according to our Privacy Policy. '
                    'By using the app, you consent to our data collection and usage practices as outlined therein.',
              ),
              _buildSectionTitle(theme, '4. Modifications'),
              _buildSectionBody(
                theme,
                'We may modify these Terms at any time. Continued use of the app after changes indicates your acceptance of the new Terms.',
              ),
              _buildSectionTitle(theme, '5. Contact'),
              _buildSectionBody(
                theme,
                'For any questions about these Terms, please contact us at:\n\n'
                    '📧 support@swim-analyzer.app',
              ),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  '© 2025 Swim Apps AB. All rights reserved.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
    child: Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _buildSectionBody(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
  );
}
