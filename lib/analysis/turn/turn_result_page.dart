import 'package:flutter/material.dart';
import 'package:swim_analyzer/analysis/turn/turn_event.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class TurnResultPage extends StatelessWidget {
  final AppUser appUser;
  final Map<TurnEvent, Duration> markedTimestamps;

  const TurnResultPage({
    super.key,
    required this.appUser,
    required this.markedTimestamps,
  });

  Duration? _delta(TurnEvent start, TurnEvent end) {
    final t1 = markedTimestamps[start];
    final t2 = markedTimestamps[end];
    if (t1 == null || t2 == null) return null;
    return t2 - t1;
  }

  String _formatTime(Duration? d) =>
      d == null ? '--' : '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // --- CALCULATIONS ---
    final Duration? totalUnderwaterTime =
        _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout15m);
    final Duration? to5m =
        _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout5m);
    final Duration? to10m =
        _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout10m);
    final Duration? to15m =
        _delta(TurnEvent.feetLeaveWall, TurnEvent.breakout15m);
    final Duration? wallToFeet =
        _delta(TurnEvent.wallContactOrFlipStart, TurnEvent.feetLeaveWall);

    final avgSpeed5m = (to5m != null && to5m.inMilliseconds > 0)
        ? 5 / (to5m.inMilliseconds / 1000)
        : null;
    final avgSpeed10m = (to10m != null && to10m.inMilliseconds > 0)
        ? 10 / (to10m.inMilliseconds / 1000)
        : null;
    final avgSpeed15m = (to15m != null && to15m.inMilliseconds > 0)
        ? 15 / (to15m.inMilliseconds / 1000)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turn Analysis Results'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text(
              'Turn Summary',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRow('Wall contact → Feet leave wall',
                        _formatTime(wallToFeet)),
                    _buildRow('Feet leave wall → 5m', _formatTime(to5m)),
                    _buildRow('Feet leave wall → 10m', _formatTime(to10m)),
                    _buildRow('Feet leave wall → 15m', _formatTime(to15m)),
                    const Divider(),
                    _buildRow('Total underwater time (to 15m)',
                        _formatTime(totalUnderwaterTime)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Average Speeds',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRow(
                        '0–5m',
                        avgSpeed5m != null
                            ? '${avgSpeed5m.toStringAsFixed(2)} m/s'
                            : '--'),
                    _buildRow(
                        '0–10m',
                        avgSpeed10m != null
                            ? '${avgSpeed10m.toStringAsFixed(2)} m/s'
                            : '--'),
                    _buildRow(
                        '0–15m',
                        avgSpeed15m != null
                            ? '${avgSpeed15m.toStringAsFixed(2)} m/s'
                            : '--'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Marked Events',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              child: Column(
                children: TurnEvent.values.map((event) {
                  final time = markedTimestamps[event];
                  return ListTile(
                    title: Text(event.displayName),
                    trailing: Text(
                      time != null
                          ? '${(time.inMilliseconds / 1000).toStringAsFixed(2)} s'
                          : '--',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Analysis'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
