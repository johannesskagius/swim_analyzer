
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/helpers/race_repository.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class RaceComparisonPage extends StatelessWidget {
  final List<String> raceIds;

  const RaceComparisonPage({super.key, required this.raceIds});

  @override
  Widget build(BuildContext context) {
    final raceRepository = Provider.of<RaceRepository>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Race Comparison'),
      ),
      body: FutureBuilder<List<Race>>(
        future: Future.wait(raceIds.map((id) => raceRepository.getRace(id))),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Could not load race data.'));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final races = snapshot.data!;
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildComparisonTable(context, races),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComparisonTable(BuildContext context, List<Race> races) {
    // Assume all races have the same number of segments
    final segmentCount = races.isNotEmpty ? races.first.segments.length : 0;
    if (segmentCount == 0) {
      return const Center(child: Text('No segments to compare.'));
    }

    final List<DataColumn> columns = [
      const DataColumn(label: Text('Metric')),
      ...races.map((race) => DataColumn(label: Text(race.raceName))),
    ];

    final List<DataRow> rows = [];

    // Add rows for each segment's metrics
    for (int i = 0; i < segmentCount; i++) {
      final segment = races.first.segments[i];

      rows.add(DataRow(cells: [
        DataCell(Text('${segment.checkPoint} Split', style: const TextStyle(fontWeight: FontWeight.bold))),
        ...races.map((race) => DataCell(Text(_formatMillis(race.segments[i].splitTimeMillis)))),
      ]));
      rows.add(DataRow(cells: [
        DataCell(Text('${segment.checkPoint} Strokes')),
        ...races.map((race) => DataCell(Text(race.segments[i].strokes?.toString() ?? '-'))),
      ]));
       rows.add(DataRow(cells: [
        DataCell(Text('${segment.checkPoint} Stroke Freq.')),
        ...races.map((race) => DataCell(Text(race.segments[i].strokeFrequency?.toStringAsFixed(1) ?? '-'))),
      ]));
      rows.add(DataRow(cells: [
        DataCell(Text('${segment.checkPoint} Stroke Len.')),
        ...races.map((race) => DataCell(Text('${race.segments[i].strokeLengthMeters?.toStringAsFixed(2) ?? '-'}m'))),
      ]));
    }

    return DataTable(
      columns: columns,
      rows: rows,
    );
  }

  String _formatMillis(int millis) {
    final duration = Duration(milliseconds: millis);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String threeDigits(int n) => n.toString().padLeft(3, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    String twoDigitMillis = threeDigits(duration.inMilliseconds.remainder(1000)).substring(0,2);
    return "$twoDigitMinutes:$twoDigitSeconds.$twoDigitMillis";
  }
}
