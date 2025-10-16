import 'package:flutter/material.dart';

enum StartAnalyzes{
  offTheBlock,
  uwWork,
  breakout,
  complete,
}

extension StartAnalyzesExtension on StartAnalyzes {
  IconData get icon {
    switch (this) {
      case StartAnalyzes.offTheBlock:
        return Icons.start;
      case StartAnalyzes.uwWork:
        return Icons.waves;
      case StartAnalyzes.breakout:
        return Icons.arrow_upward;
      case StartAnalyzes.complete:
        return Icons.analytics;
    }
  }
}
