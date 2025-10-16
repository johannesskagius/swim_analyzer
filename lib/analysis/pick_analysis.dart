import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis/race/race_analysis.dart';
import 'package:swim_analyzer/analysis/analyze_type.dart';
import 'package:swim_analyzer/analysis/start/start_analyses_types.dart';
import 'package:swim_analyzer/analysis/start/start_analysis.dart';

import 'not_implement_analyses.dart';
import 'start/off_the_block_analysis.dart';

class PickAnalysis extends StatelessWidget {
  const PickAnalysis({super.key});

  /// Pushes the corresponding analysis page onto the navigation stack.
  ///
  /// This method takes a [BuildContext] and navigates to the correct
  /// page based on the enum value, reducing boilerplate navigation code.
  ///
  /// It returns a `Future` that completes when the pushed route is popped.
  Future<T?> pushRoute<T>(BuildContext context, AnalyzeType a) {
    // The target page widget is determined by the enum value.
    Widget targetPage;

    switch (a) {
      case AnalyzeType.race:
      // Assuming your existing AnalysisPage is for races.
        targetPage = RaceAnalysisView();
        break;
      case AnalyzeType.start:
        targetPage = const StartAnalysis();
        break;
      case AnalyzeType.stroke:
        targetPage = const StrokeAnalysisPage();
        break;
      case AnalyzeType.turn:
        targetPage = const TurnAnalysisPage();
        break;
    }

    // A single, consistent navigation call.
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (ctx) => targetPage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Set<AnalyzeType> implementedTypes = {
      AnalyzeType.race,
      AnalyzeType.start
    };

    return GridView(
        padding: const EdgeInsets.all(12.0), // Add padding around the grid
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12, // Add spacing between cards horizontally
          mainAxisSpacing: 12, // Add spacing between cards vertically
          childAspectRatio: 1, // Make cards square
        ),
        children: [
          for (AnalyzeType a in AnalyzeType.values)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (implementedTypes.contains(a)) {
                    // If the type is implemented, navigate to its page.
                    pushRoute(context, a);
                  } else {
                    // If the type is not implemented, show a SnackBar.
                    // Capitalize the first letter of the analysis type name for the message.
                    final typeName =
                        a.name[0].toUpperCase() + a.name.substring(1);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                        Text('$typeName analysis is not implemented yet.'),
                        duration: const Duration(seconds: 2),
                        action: SnackBarAction(
                          label: 'OK',
                          onPressed: () {
                            // Action to dismiss the SnackBar.
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          },
                        ),
                      ),
                    );
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      getIconForAnalysis(a),
                      size: 64, // Increase icon size for better visibility
                      color: implementedTypes.contains(a) ? theme.colorScheme.primary:theme.colorScheme.primary.withAlpha(50), // Use theme color
                    ),
                    const SizedBox(height: 16),
                    Text(
                      // Capitalize the first letter for a clean look
                      a.name[0].toUpperCase() + a.name.substring(1),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
        ]);
  }
}

IconData getIconForAnalysis(AnalyzeType a) {
  switch (a) {
    case AnalyzeType.race:
      return Icons.flag_circle_outlined;
    case AnalyzeType.start:
      return Icons.start_outlined;
    case AnalyzeType.stroke:
      return Icons.waves_outlined; // Icon representing swimming strokes.
    case AnalyzeType.turn:
      return Icons.sync_alt_outlined; // Icon representing a turn or flip.
  }
}