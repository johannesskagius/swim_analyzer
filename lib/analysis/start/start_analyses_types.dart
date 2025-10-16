import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis/start/off_the_block_analysis.dart';

enum StartAnalyzes {
  offTheBlock,
  uwWork,
  breakout,
  complete,
}

/// Provides rich metadata for each [StartAnalyzes] enum value.
///
/// This extension centralizes the display name, icon, implementation status,
/// and target page for each analysis type, promoting a clean and
/// maintainable codebase.
extension StartAnalyzesMetadata on StartAnalyzes {
  /// A user-friendly display name for the analysis type.
  String get displayName {
    switch (this) {
      case StartAnalyzes.offTheBlock:
        return 'Off the Block';
      case StartAnalyzes.uwWork:
        return 'UW Work';
      case StartAnalyzes.breakout:
        return 'Breakout';
      case StartAnalyzes.complete:
        return 'Complete Start';
    }
  }

  /// The icon associated with the analysis type.
  IconData get icon {
    switch (this) {
      case StartAnalyzes.offTheBlock:
        return Icons.flag_circle_outlined;
      case StartAnalyzes.uwWork:
        return Icons.start_outlined;
      case StartAnalyzes.breakout:
        return Icons.waves_outlined;
      case StartAnalyzes.complete:
        return Icons.analytics_outlined;
    }
  }

  /// A flag indicating whether the analysis type is implemented and ready for use.
  bool get isImplemented => this == StartAnalyzes.offTheBlock;

  /// The widget corresponding to the analysis page.
  ///
  /// Throws an [UnimplementedError] if `isImplemented` is false to prevent
  /// navigation to incomplete features.
  Widget get page {
    if (!isImplemented) {
      throw UnimplementedError(
          '$displayName analysis page is not implemented yet.');
    }
    switch (this) {
      case StartAnalyzes.offTheBlock:
        return const OffTheBlockAnalysisPage();
      // The if check above handles the other cases.
      default:
        // This should not be reachable if `isImplemented` is checked first.
        throw UnimplementedError(
            '$displayName analysis page is not implemented yet.');
    }
  }
}
