import 'package:flutter/material.dart';
import 'package:swim_analyzer/model/start_analyses_types.dart';

import '../../off_the_block_analysis.dart';

/// Pushes the corresponding analysis page onto the navigation stack.
///
/// This method takes a [BuildContext] and navigates to the correct
/// page based on the enum value, reducing boilerplate navigation code.
///
/// It returns a `Future` that completes when the pushed route is popped.
Future<T?> pushRoute<T>(BuildContext context, StartAnalyzes startAnalyzes) {
  // The target page widget is determined by the enum value.
  Widget targetPage;

  switch (startAnalyzes) {
    case StartAnalyzes.offTheBlock:
      targetPage = OffTheBlockAnalysisPage();
    case StartAnalyzes.uwWork:
    // TODO: Handle this case.
      throw UnimplementedError();
    case StartAnalyzes.breakout:
    // TODO: Handle this case.
      throw UnimplementedError();
    case StartAnalyzes.complete:
    // TODO: Handle this case.
      throw UnimplementedError();
  }

  // A single, consistent navigation call.
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (ctx) => targetPage,
    ),
  );
}

class StartAnalysis extends StatelessWidget {
  const StartAnalysis({super.key});



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView(
        padding: const EdgeInsets.all(12.0), // Add padding around the grid
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12, // Add spacing between cards horizontally
          mainAxisSpacing: 12, // Add spacing between cards vertically
          childAspectRatio: 1, // Make cards square
        ),
        children: [
          for (StartAnalyzes startAnalyzes in StartAnalyzes.values)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final implementedTypes = {StartAnalyzes.offTheBlock};

                  if (implementedTypes.contains(startAnalyzes)) {
                    // If the type is implemented, navigate to its page.
                    pushRoute(context, startAnalyzes);
                  } else {
                    // If the type is not implemented, show a SnackBar.
                    // Capitalize the first letter of the analysis type name for the message.
                    final typeName = startAnalyzes.name[0].toUpperCase() +
                        startAnalyzes.name.substring(1);
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
                      getIconForStartAnalysis(startAnalyzes),
                      size: 64, // Increase icon size for better visibility
                      color: theme.colorScheme.primary, // Use theme color
                    ),
                    const SizedBox(height: 16),
                    Text(
                      // Capitalize the first letter for a clean look
                      startAnalyzes.name[0].toUpperCase() +
                          startAnalyzes.name.substring(1),
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
IconData getIconForStartAnalysis(StartAnalyzes startAnalysis) {
  switch (startAnalysis) {
    case StartAnalyzes.offTheBlock:
      return Icons.flag_circle_outlined;
    case StartAnalyzes.uwWork:
      return Icons.start_outlined;
    case StartAnalyzes.breakout:
      return Icons.waves_outlined; // Icon representing swimming strokes.
    case StartAnalyzes.complete:
      return Icons.waves_outlined; // Icon representing swimming strokes.
  }
}