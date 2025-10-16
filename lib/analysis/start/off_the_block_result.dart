import 'package:flutter/material.dart';

import 'off_the_block_analysis.dart';

class OffTheBlockResultsPage extends StatelessWidget {
  final Map<OffTheBlockEvent, Duration> markedTimestamps;
  final String? startDistance;
  final String? startHeight;

  const OffTheBlockResultsPage({
    super.key,
    required this.markedTimestamps,
    this.startDistance,
    this.startHeight,
  });

  @override
  Widget build(BuildContext context) {
    final startSignalTime =
        markedTimestamps[OffTheBlockEvent.startSignal] ?? Duration.zero;

    final List<Widget> resultsWidgets = (markedTimestamps.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index)))
        .map<Widget>((entry) {
      final eventName = entry.key.displayName;
      final relativeTime = entry.value - startSignalTime;
      final timeInSeconds =
      (relativeTime.inMilliseconds / 1000.0).toStringAsFixed(2);
      return ListTile(
        title: Text(eventName),
        trailing: Text('$timeInSeconds s'),
      );
    }).toList();

    // Calculate and add speed metrics
    final timeTo5m = markedTimestamps[OffTheBlockEvent.reached5m];
    final timeTo10m = markedTimestamps[OffTheBlockEvent.reached10m];

    if (timeTo5m != null || timeTo10m != null) {
      resultsWidgets.add(const Divider());
    }

    if (timeTo5m != null) {
      final relativeTimeTo5m = timeTo5m - startSignalTime;
      if (relativeTimeTo5m.inMilliseconds > 0) {
        final speedTo5m = 5 / (relativeTimeTo5m.inMilliseconds / 1000.0);
        resultsWidgets.add(ListTile(
          title: const Text('Average Speed to 5m'),
          trailing: Text('${speedTo5m.toStringAsFixed(2)} m/s'),
        ));
      }
    }

    if (timeTo10m != null) {
      final relativeTimeTo10m = timeTo10m - startSignalTime;
      if (relativeTimeTo10m.inMilliseconds > 0) {
        final speedTo10m = 10 / (relativeTimeTo10m.inMilliseconds / 1000.0);
        resultsWidgets.add(ListTile(
          title: const Text('Average Speed to 10m'),
          trailing: Text('${speedTo10m.toStringAsFixed(2)} m/s'),
        ));
      }
    }

    // Add optional stats
    if ((startDistance != null && startDistance!.isNotEmpty) ||
        (startHeight != null && startHeight!.isNotEmpty)) {
      resultsWidgets.add(const Divider());
    }

    if (startDistance != null && startDistance!.isNotEmpty) {
      resultsWidgets.add(ListTile(
        title: const Text('Start Distance'),
        trailing: Text('$startDistance m'),
      ));
    }
    if (startHeight != null && startHeight!.isNotEmpty) {
      resultsWidgets.add(ListTile(
        title: const Text('Start Height'),
        trailing: Text('$startHeight m'),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Results'),
      ),
      body: ListView(
        children: resultsWidgets,
      ),
    );
  }
}
