import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis/analyze_type.dart';
import 'package:swim_analyzer/analysis/race/race_analysis.dart';
import 'package:swim_analyzer/analysis/start/start_analysis.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analyzes_widget.dart';
import 'package:swim_analyzer/analysis/turn/turn_analysis_page.dart';
import 'package:swim_apps_shared/src/objects/user.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class PickAnalysis extends StatelessWidget {
  final AppUser appUser;

  const PickAnalysis({super.key, required this.appUser});

  /// Set of currently implemented analysis types.
  /// This is centralized to ensure consistency across the widget.
  static const Set<AnalyzeType> _implementedTypes = {
    AnalyzeType.race,
    AnalyzeType.start,
    AnalyzeType.stroke,
    // AnalyzeType.turn is not yet implemented.
  };

  /// Handles the navigation logic when an analysis card is tapped.
  /// It checks if the analysis type is implemented before navigating.
  void _onAnalysisTap(BuildContext context, AnalyzeType type) {
    if (_implementedTypes.contains(type)) {
      _navigateToAnalysisPage(context, type);
    } else {
      _showNotImplementedSnackBar(context, type);
    }
  }

  /// Pushes the corresponding analysis page onto the navigation stack.
  ///
  /// Refactored to handle potential navigation errors and to be a private utility method.
  Future<void> _navigateToAnalysisPage<T>(BuildContext context, AnalyzeType a) async {
    try {
      // getTargetPage is now a separate function to improve testability and readability.
      final Widget targetPage = _getTargetPage(a);

      // Check if the widget is still in the tree before navigating.
      if (!context.mounted) return;

      await Navigator.of(context).push<T>(
        MaterialPageRoute(
          builder: (ctx) => targetPage,
        ),
      );
    } catch (e, s) {
      // Non-fatal error logging: If page creation or navigation fails,
      // we log it to Crashlytics for monitoring without crashing the app.
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: 'Failed to navigate to analysis page for type: ${a.name}',
      );

      // Optionally, inform the user that something went wrong.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open page. An unexpected error occurred.'),
          ),
        );
      }
    }
  }

  /// Returns the widget for the selected analysis type.
  /// Throws an [ArgumentError] if the type is unknown, preventing crashes.
  Widget _getTargetPage(AnalyzeType a) {
    switch (a) {
      case AnalyzeType.race:
        return RaceAnalysisView(appUser: appUser);
      case AnalyzeType.start:
        return StartAnalysis(appUser: appUser);
      case AnalyzeType.stroke:
        return StrokeAnalysisPage(appUser: appUser);
      case AnalyzeType.turn:
        return TurnAnalysisPage(appUser: appUser);
    // No default case is needed as all enum values are handled.
    // The Dart analyzer will warn if a new AnalyzeType is added and not handled here.
    }
  }

  /// Displays a SnackBar message for features that are not yet implemented.
  void _showNotImplementedSnackBar(BuildContext context, AnalyzeType a) {
    // String capitalization is handled in an extension for reusability.
    final typeName = a.name.capitalize();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$typeName analysis is not implemented yet.'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The main build method is now cleaner, delegating logic to smaller widgets.
    return GridView.builder(
      padding: const EdgeInsets.all(12.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      // Use GridView.builder for better performance with large lists.
      itemCount: AnalyzeType.values.length,
      itemBuilder: (context, index) {
        final analysisType = AnalyzeType.values[index];
        final bool isImplemented = _implementedTypes.contains(analysisType);

        // The card's UI is extracted into its own stateless widget for clarity.
        return _AnalysisCard(
          type: analysisType,
          isImplemented: isImplemented,
          onTap: () => _onAnalysisTap(context, analysisType),
        );
      },
    );
  }
}

/// A stateless widget representing a single card in the analysis grid.
/// This refactoring improves readability and separates UI concerns.
class _AnalysisCard extends StatelessWidget {
  final AnalyzeType type;
  final bool isImplemented;
  final VoidCallback onTap;

  const _AnalysisCard({
    required this.type,
    required this.isImplemented,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    // The title style is now clearly defined and safe from null reference issues.
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    ) ??
        const TextStyle(fontWeight: FontWeight.bold);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIconForAnalysis(type),
              size: 64,
              // Simplified color logic based on whether the feature is implemented.
              color: isImplemented ? primaryColor : primaryColor.withAlpha(50),
            ),
            const SizedBox(height: 16),
            Text(
              type.name.capitalize(), // Using the reusable string extension.
              style: titleStyle,
            ),
          ],
        ),
      ),
    );
  }
}

/// Returns an icon for a given analysis type.
/// This remains a top-level function as it's a pure utility without side effects.
IconData _getIconForAnalysis(AnalyzeType a) {
  switch (a) {
    case AnalyzeType.race:
      return Icons.flag_circle_outlined;
    case AnalyzeType.start:
      return Icons.start_outlined;
    case AnalyzeType.stroke:
      return Icons.waves_outlined;
    case AnalyzeType.turn:
      return Icons.sync_alt_outlined;
  }
}

/// An extension on [String] to provide a reusable capitalization method.
/// This avoids repetitive logic and makes the code cleaner.
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) {
      return this;
    }
    return this[0].toUpperCase() + substring(1);
  }
}
