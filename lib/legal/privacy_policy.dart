
import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Privacy Policy',
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
                'At Swim Analyzer, your privacy is important to us. This Privacy Policy explains how we collect, use, and protect your personal information when you use our app.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(theme, '1. Information We Collect'),
              _buildSectionBody(
                theme,
                'We may collect information such as your name, email address, and usage data to improve your experience. '
                    'This may include anonymized analytics to understand app performance and user engagement.',
              ),
              _buildSectionTitle(theme, '2. How We Use Information'),
              _buildSectionBody(
                theme,
                'We use your information to provide, maintain, and enhance Swim Analyzer. '
                    'We never sell your personal data to third parties.',
              ),
              _buildSectionTitle(theme, '3. Data Security'),
              _buildSectionBody(
                theme,
                'We implement technical and organizational measures to protect your information from unauthorized access or disclosure.',
              ),
              _buildSectionTitle(theme, '4. Your Rights'),
              _buildSectionBody(
                theme,
                'You may request access to, correction of, or deletion of your personal data by contacting us at privacy@swim-analyzer.app.',
              ),
              _buildSectionTitle(theme, '5. Changes to This Policy'),
              _buildSectionBody(
                theme,
                'We may update this Privacy Policy from time to time. Any updates will be reflected within the app.',
              ),
              _buildSectionTitle(theme, '6. Contact Us'),
              _buildSectionBody(
                theme,
                'If you have any questions or concerns, please contact:\n\n'
                    '📧 privacy@swim-analyzer.app',
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
