import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class RaceComparisonPage extends StatelessWidget {
  final List<String> raceIds;

  const RaceComparisonPage({super.key, required this.raceIds});

  @override
  Widget build(BuildContext context) {
    final raceRepository = Provider.of<AnalyzesRepository>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Race Comparison'),
      ),
      body: FutureBuilder<List<RaceAnalysis>>(
        future: Future.wait(raceIds.map((id) => raceRepository.getRace(id))),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.isEmpty) {
            return Center(
                child: Text(
                    'Error: ${snapshot.error ?? "Could not load race data."}'));
          }

          final races = snapshot.data!;
          races.sort(
              (a, b) => a.raceDate?.compareTo(b.raceDate ?? DateTime(0)) ?? 0);

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _buildComparisonTable(context, races),
            ),
          );
        },
      ),
    );
  }

  /// Builds the comparison table with a sticky first column, ensuring row alignment.
  Widget _buildComparisonTable(BuildContext context, List<RaceAnalysis> races) {
    final statRows = _buildStatRows(context, races);
    const double fixedRowHeight =
        48.0; // Enforce a fixed height for perfect alignment
    const double fixedHeaderHeight = 80.0; // Enforce a fixed height for headers

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Sticky First Column (Metrics) ---
        DataTable(
          horizontalMargin: 12,
          columnSpacing: 24,
          dataRowHeight: fixedRowHeight,
          // Use fixed height
          headingRowHeight: fixedHeaderHeight,
          // Use fixed height for alignment
          columns: const [
            DataColumn(
                label: Text('Metric',
                    style: TextStyle(fontWeight: FontWeight.bold)))
          ],
          rows:
              statRows.map((row) => DataRow(cells: [row.cells.first])).toList(),
        ),
        // --- Scrollable Data Columns ---
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: fixedHeaderHeight,
              // Use fixed height
              horizontalMargin: 12,
              columnSpacing: 36,
              dataRowHeight: fixedRowHeight,
              // Use fixed height
              columns: _buildDataColumns(races),
              rows: statRows
                  .map((row) => DataRow(
                      color: row.color, cells: row.cells.skip(1).toList()))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  List<DataColumn> _buildDataColumns(List<RaceAnalysis> races) {
    final bool showDiffColumn = races.length == 2;
    return [
      ...races.map((race) {
        final raceDate = race.raceDate != null
            ? DateFormat.yMd().format(race.raceDate!)
            : 'No Date';
        final title = race.raceName != null && race.raceName!.isNotEmpty
            ? race.raceName!
            : (race.eventName ?? 'Race');
        return DataColumn(
          label: Text('$title\n$raceDate',
              textAlign: TextAlign.center, softWrap: true),
        );
      }),
      if (showDiffColumn)
        const DataColumn(
            label: Center(
                child: Text('Difference',
                    style: TextStyle(fontWeight: FontWeight.bold)))),
    ];
  }

  List<DataRow> _buildStatRows(BuildContext context, List<RaceAnalysis> races) {
    final bool showDiffColumn = races.length == 2;
    final bestValueStyle =
    TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800);
    final List<DataRow> rows = [];

    final bool allBreaststroke =
    races.every((r) => r.stroke?.name.toLowerCase() == 'breaststroke');

    void addStatRow({
      required String title,
      required bool isOverall,
      required String? Function(int index) getValue,
      required num? Function(int index) getNumericValue,
      required bool lowerIsBetter,
      String Function(num value)? formatDiff,
    }) {
      // --- START: Hide empty rows logic ---
      // Generate all display values for this metric row.
      final allDisplayValues = List.generate(races.length, (i) => getValue(i));

      // If every single value for this metric is null or would be displayed as a dash,
      // then the row is considered empty and we should skip adding it entirely.
      if (allDisplayValues.every((value) => value == null || value == '-')) {
        return; // Don't add the row if it's empty.
      }
      // --- END: Hide empty rows logic ---

      final numericValues = List.generate(races.length, getNumericValue)
          .whereType<num>()
          .toList();
      final bestValue = numericValues.isEmpty
          ? null
          : (lowerIsBetter
          ? numericValues.reduce(min)
          : numericValues.reduce(max));

      Widget titleWidget;
      if (title == 'Avg. SWOLF') {
        titleWidget = InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('What is SWOLF?'),
                content: SingleChildScrollView(
                  child: RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context)
                          .style
                          .copyWith(fontSize: 16),
                      children: const <TextSpan>[
                        TextSpan(
                            text:
                            'SWOLF is a measure of swimming efficiency.\n\n'),
                        TextSpan(
                            text: 'Time per Lap (s) + Strokes per Lap\n\n',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic)),
                        TextSpan(
                            text:
                            'A lower score indicates better efficiency, as it means you are taking fewer strokes to swim at a faster pace.'),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('GOT IT'),
                  ),
                ],
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight:
                      isOverall ? FontWeight.bold : FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ],
          ),
        );
      } else {
        titleWidget = Text(title,
            style: TextStyle(
                fontWeight: isOverall ? FontWeight.bold : FontWeight.w600));
      }

      final cells = [
        DataCell(titleWidget),
        ...List.generate(races.length, (index) {
          final isBest = getNumericValue(index) == bestValue;
          return DataCell(Center(
              child: Text(getValue(index) ?? '-',
                  style: isBest ? bestValueStyle : null)));
        }),
      ];

      if (showDiffColumn) {
        cells.add(_buildDifferenceCell(
            getNumericValue(1), getNumericValue(0), lowerIsBetter, formatDiff));
      }

      rows.add(DataRow(
        color: MaterialStateProperty.all(isOverall
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
            : null),
        cells: cells,
      ));
    }

    // --- Overall Statistics ---
    final signFormatter =
        (num v, int frac) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(frac)}';
    final signMeterFormatter =
        (num v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}m';

    addStatRow(
        title: 'Total Time',
        isOverall: true,
        getValue: (i) => _formatMillis(races[i].finalTime),
        getNumericValue: (i) => races[i].finalTime,
        lowerIsBetter: true,
        formatDiff: (v) => _formatMillis(v.toInt(), showSign: true));
    addStatRow(
        title: 'Total Strokes',
        isOverall: true,
        getValue: (i) => races[i].totalStrokes.toString(),
        getNumericValue: (i) => races[i].totalStrokes,
        lowerIsBetter: true,
        formatDiff: (v) => signFormatter(v, 0));
    if (!allBreaststroke) {
      addStatRow(
          title: 'Total Breaths',
          isOverall: true,
          getValue: (i) =>
              races[i].segments.map((s) => s.breaths ?? 0).sum.toString(),
          getNumericValue: (i) =>
          races[i].segments.map((s) => s.breaths ?? 0).sum,
          lowerIsBetter: true,
          formatDiff: (v) => signFormatter(v, 0));
      addStatRow(
          title: 'Total Kicks',
          isOverall: true,
          getValue: (i) =>
              races[i].segments.map((s) => s.dolphinKicks ?? 0).sum.toString(),
          getNumericValue: (i) =>
          races[i].segments.map((s) => s.dolphinKicks ?? 0).sum,
          lowerIsBetter: false,
          formatDiff: (v) => signFormatter(v, 0));
    }
    addStatRow(
        title: 'Avg. Stroke Freq',
        isOverall: true,
        getValue: (i) => races[i].averageStrokeFrequency?.toStringAsFixed(1),
        getNumericValue: (i) => races[i].averageStrokeFrequency,
        lowerIsBetter: false,
        formatDiff: (v) => signFormatter(v, 1));
    addStatRow(
        title: 'Avg. Stroke Len.',
        isOverall: true,
        getValue: (i) => races[i].averageStrokeLengthMeters != null
            ? '${races[i].averageStrokeLengthMeters!.toStringAsFixed(2)}m'
            : '-',
        getNumericValue: (i) => races[i].averageStrokeLengthMeters,
        lowerIsBetter: false,
        formatDiff: signMeterFormatter);
    addStatRow(
        title: 'Avg. Speed (m/s)',
        isOverall: true,
        getValue: (i) => _calculateSpeed(races[i].averageStrokeLengthMeters,
            races[i].averageStrokeFrequency)
            ?.toStringAsFixed(2),
        getNumericValue: (i) => _calculateSpeed(
            races[i].averageStrokeLengthMeters,
            races[i].averageStrokeFrequency),
        lowerIsBetter: false,
        formatDiff: (v) => signFormatter(v, 2));
    addStatRow(
        title: 'Avg. SWOLF',
        isOverall: true,
        getValue: (i) => _calculateAverageSwolf(races[i])?.toStringAsFixed(1),
        getNumericValue: (i) => _calculateAverageSwolf(races[i]),
        lowerIsBetter: true,
        formatDiff: (v) => signFormatter(v, 1));

    // --- Per-Segment Statistics ---
    final Map<int, String> masterCheckPointMap = {};
    for (final race in races) {
      for (final segment in race.segments) {
        masterCheckPointMap.putIfAbsent(
            segment.sequence, () => segment.checkPoint);
      }
    }
    masterCheckPointMap.removeWhere((seq, cp) => cp == 'start');
    final sortedSequences = masterCheckPointMap.keys.toList()..sort();

    for (final sequence in sortedSequences) {
      final checkPoint = masterCheckPointMap[sequence]!;
      final segments = races
          .map((race) =>
          race.segments.firstWhereOrNull((s) => s.sequence == sequence))
          .toList();

      if (checkPoint == 'breakOut') {
        addStatRow(
          title: 'Breakout (m)',
          isOverall: false,
          getValue: (i) {
            final segment = segments[i];
            if (segment == null) return null;
            final prevWall = races[i].segments.lastWhereOrNull((s) =>
            (s.checkPoint == 'start' || s.checkPoint == 'turn') &&
                s.sequence < segment.sequence);
            final breakoutDist =
                segment.distanceMeters - (prevWall?.distanceMeters ?? 0.0);
            return breakoutDist > 0 ? breakoutDist.toStringAsFixed(1) : null;
          },
          getNumericValue: (i) {
            final segment = segments[i];
            if (segment == null) return null;
            final prevWall = races[i].segments.lastWhereOrNull((s) =>
            (s.checkPoint == 'start' || s.checkPoint == 'turn') &&
                s.sequence < segment.sequence);
            final breakoutDist = segment.distanceMeters - (prevWall?.distanceMeters ?? 0.0);
            return breakoutDist > 0 ? breakoutDist : null;
          },
          lowerIsBetter: false, // Longer breakout is generally better
          formatDiff: (v) => signFormatter(v, 1),
        );
      } else {
        final distance =
            segments.firstWhereOrNull((s) => s != null)?.distanceMeters;
        if (distance == null) continue;

        final distanceLabel =
            '${distance.toStringAsFixed(distance.truncateToDouble() == distance ? 0 : 1)}m';

// Create a visually distinct separator row that now INCLUDES the total time.
        rows.add(DataRow(
            color: MaterialStateProperty.all(Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withOpacity(0.3)),
            cells: List.generate(
              races.length + (showDiffColumn ? 2 : 1),
                  (i) {
                // The first cell is the distance label (e.g., "25m").
                if (i == 0) {
                  return DataCell(
                    Text(
                      distanceLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                }
                // The cells for each race show the cumulative time at that distance.
                else if (i <= races.length) {
                  final segment = segments.length > i - 1 ? segments[i - 1] : null;
                  return DataCell(
                    Center(
                      child: Text(
                        _formatMillis(segment?.totalTimeMillis) ?? '-',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }
                // The final cell (for the difference column) is empty in this header row.
                else {
                  return const DataCell(SizedBox());
                }
              },
            )));

        addStatRow(
            title: 'Split',
            isOverall: false,
            getValue: (i) => _formatMillis(segments[i]?.splitTimeMillis),
            getNumericValue: (i) => segments[i]?.splitTimeMillis,
            lowerIsBetter: true,
            formatDiff: (v) => _formatMillis(v.toInt(), showSign: true));
        addStatRow(
            title: 'Strokes',
            isOverall: false,
            getValue: (i) => segments[i]?.strokes?.toString(),
            getNumericValue: (i) => segments[i]?.strokes,
            lowerIsBetter: true,
            formatDiff: (v) => signFormatter(v, 0));

        if (!allBreaststroke) {
          addStatRow(
              title: 'Breaths',
              isOverall: false,
              getValue: (i) => segments[i]?.breaths?.toString(),
              getNumericValue: (i) => segments[i]?.breaths,
              lowerIsBetter: true,
              formatDiff: (v) => signFormatter(v, 0));
          if (checkPoint != 'breakOut') {
            addStatRow(
                title: 'Dolphin Kicks',
                isOverall: false,
                getValue: (i) => segments[i]?.dolphinKicks?.toString(),
                getNumericValue: (i) => segments[i]?.dolphinKicks,
                lowerIsBetter: false,
                formatDiff: (v) => signFormatter(v, 0));
          }
        }

        addStatRow(
            title: 'Stroke Freq.',
            isOverall: false,
            getValue: (i) => segments[i]?.strokeFrequency?.toStringAsFixed(1),
            getNumericValue: (i) => segments[i]?.strokeFrequency,
            lowerIsBetter: false,
            formatDiff: (v) => signFormatter(v, 1));
        addStatRow(
            title: 'Stroke Len.',
            isOverall: false,
            getValue: (i) => segments[i]?.strokeLengthMeters != null
                ? '${segments[i]!.strokeLengthMeters!.toStringAsFixed(2)}m'
                : '-',
            getNumericValue: (i) => segments[i]?.strokeLengthMeters,
            lowerIsBetter: false,
            formatDiff: signMeterFormatter);
        addStatRow(
            title: 'Avg. Speed (m/s)',
            isOverall: false,
            getValue: (i) => _calculateSpeed(
                segments[i]?.strokeLengthMeters, segments[i]?.strokeFrequency)
                ?.toStringAsFixed(2),
            getNumericValue: (i) => _calculateSpeed(
                segments[i]?.strokeLengthMeters, segments[i]?.strokeFrequency),
            lowerIsBetter: false,
            formatDiff: (v) => signFormatter(v, 2));
      }
    }
    return rows;
  }

  double? _calculateSpeed(num? strokeLength, num? strokeFrequency) {
    if (strokeLength == null || strokeFrequency == null || strokeFrequency == 0)
      return null;
    return (strokeLength * strokeFrequency) / 60.0;
  }

  /// Correctly calculates average SWOLF by identifying laps between wall segments.
  double? _calculateAverageSwolf(RaceAnalysis race) {
    final List<double> lapSwolfScores = [];
    final wallSegments = race.segments
        .where((s) =>
            s.checkPoint == 'start' ||
            s.checkPoint == 'turn' ||
            s.checkPoint == 'finish')
        .toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));

    if (wallSegments.length < 2) return null;

    for (int i = 0; i < wallSegments.length - 1; i++) {
      final startLapSegment = wallSegments[i];
      final endLapSegment = wallSegments[i + 1];

      final lapSegments = race.segments.where((s) =>
          s.sequence > startLapSegment.sequence &&
          s.sequence <= endLapSegment.sequence);
      final lapTimeMillis =
          endLapSegment.totalTimeMillis - startLapSegment.totalTimeMillis;
      final lapStrokes = lapSegments.map((s) => s.strokes ?? 0).sum;

      if (lapTimeMillis > 0 && lapStrokes > 0) {
        final lapTimeSeconds = lapTimeMillis / 1000.0;
        lapSwolfScores.add(lapTimeSeconds + lapStrokes);
      }
    }
    return lapSwolfScores.isEmpty ? null : lapSwolfScores.average;
  }

  String _formatMillis(int? millis, {bool showSign = false}) {
    if (millis == null) return '-';
    final isNegative = millis < 0;
    final duration = Duration(milliseconds: millis.abs());
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final hundredths = (duration.inMilliseconds.remainder(1000) ~/ 10);
    final sign = showSign ? (isNegative ? '-' : '+') : '';
    return '$sign${minutes > 0 ? '$minutes:' : ''}${seconds.toString().padLeft(minutes > 0 ? 2 : 1, '0')}.${hundredths.toString().padLeft(2, '0')}';
  }

  DataCell _buildDifferenceCell(num? val2, num? val1, bool lowerIsBetter,
      String Function(num value)? formatter) {
    if (val1 == null || val2 == null)
      return const DataCell(Center(child: Text('-')));

    final diff = val2 - val1;
    if (diff.abs() < 0.01)
      return const DataCell(Center(
          child: Text('–', style: TextStyle(fontWeight: FontWeight.bold))));

    final bool isImprovement = lowerIsBetter ? diff < 0 : diff > 0;
    final color = isImprovement ? Colors.green.shade800 : Colors.red.shade700;

    final formattedValue = formatter != null
        ? formatter(diff)
        : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}';

    return DataCell(Center(
        child: Text(formattedValue,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15))));
  }
}
