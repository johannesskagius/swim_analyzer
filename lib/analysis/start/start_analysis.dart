import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis/start/start_analyses_types.dart';
import 'package:swim_apps_shared/src/objects/user.dart';

class StartAnalysis extends StatelessWidget {
  final AppUser appUser;
  const StartAnalysis({super.key, required this.appUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: GridView(
        padding: const EdgeInsets.all(12.0), // Add padding around the grid
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12, // Add spacing between cards horizontally
          mainAxisSpacing: 12, // Add spacing between cards vertically
          childAspectRatio: 1, // Make cards square
        ),
        children: [
          for (final startAnalysis in StartAnalyzes.values)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              // Use a semi-transparent color for unimplemented features to give a visual cue.
              color: startAnalysis.isImplemented
                  ? null
                  : theme.cardColor.withAlpha(50),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (startAnalysis.isImplemented) {
                    // If the type is implemented, navigate to its page.
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => startAnalysis.page(appUser),
                      ),
                    );
                  } else {
                    // If the type is not implemented, show a SnackBar.
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${startAnalysis.displayName} analysis is not implemented yet.'),
                        duration: const Duration(seconds: 2),
                        action: SnackBarAction(
                          label: 'OK',
                          onPressed: () {
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
                      startAnalysis.icon, // Use the icon from the extension.
                      size: 64,
                      color: startAnalysis.isImplemented
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      startAnalysis.displayName, // Use the display name from the extension.
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: startAnalysis.isImplemented
                            ? null
                            : theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }
}
