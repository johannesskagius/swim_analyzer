import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis_page.dart';

enum AnalyzeType {
  race,
  start,
  stroke,
  turn,
}
extension AnalyzeTypeUIHelper on AnalyzeType {
  /// Returns the appropriate [IconData] for each analysis type.
  IconData get icon {
    // A switch statement provides compile-time safety, ensuring all
    // enum values are handled.
    switch (this) {
      case AnalyzeType.race:
        return Icons.flag_circle_outlined; // Icon for a full race.
      case AnalyzeType.start:
        return Icons.start_outlined; // Icon representing a start or block.
      case AnalyzeType.stroke:
        return Icons.waves_outlined; // Icon representing swimming strokes.
      case AnalyzeType.turn:
        return Icons.sync_alt_outlined; // Icon representing a turn or flip.
    }
  }

} //How to Use the ExtensionNow, in any part of your app where you have a BuildContext and an AnalyzeType variable, you can easily access the icon and trigger navigation.Example Usage in a UI Widget:Let's imagine you have a home screen with buttons for each analysis type.Dartimport 'package:flutter/material.dart';
// import 'package:flutter/material.dart';
// import 'package:swim_analyzer/analyze_type.dart'; // Make sure to import the file with the extension
//
// class HomePage extends StatelessWidget {
//   const HomePage({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Swim Analyzer'),
//       ),
//       body: ListView.builder(
//         itemCount: AnalyzeType.values.length,
//         itemBuilder: (context, index) {
//           final analyzeType = AnalyzeType.values[index];
//
//           return Card(
//             margin: const EdgeInsets.all(8.0),
//             child: ListTile(
//               // 1. Using the .icon getter from the extension
//               leading: Icon(
//                 analyzeType.icon,
//                 size: 40,
//                 color: Theme.of(context).colorScheme.primary,
//               ),
//               title: Text(
//                 // Capitalize the first letter for display
//                 analyzeType.name[0].toUpperCase() + analyzeType.name.substring(1),
//                 style: const TextStyle(fontWeight: FontWeight.bold),
//               ),
//               trailing: const Icon(Icons.arrow_forward_ios),
//               onTap: () {
//                 // 2. Using the .pushRoute() method from the extension
//                 analyzeType.pushRoute(context);
//               },
//             ),
//           );
//         },
//       ),
//     );
//   }
// }