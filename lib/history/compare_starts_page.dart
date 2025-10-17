import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/start/off_the_block_enums.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'dart:math';

class CompareStartsPage extends StatefulWidget {
  final AppUser appUser;
  final List<String> analysisIds;

  const CompareStartsPage(
      {super.key, required this.appUser, required this.analysisIds});

  @override
  State<CompareStartsPage> createState() => _CompareStartsPageState();
}

class _CompareStartsPageState extends State<CompareStartsPage> {
  late Future<List<OffTheBlockAnalysisData>> _analysesFuture;

  @override
  void initState() {
    super.initState();
    final analysisRepository = context.read<AnalyzesRepository>();
    _analysesFuture = analysisRepository.getOffTheBlockAnalysesByIds(
        analysisIds: widget.analysisIds);
  }

  /// Helper to safely calculate the time interval between two events.
  /// Returns the formatted string in seconds or 'N/A' if data is missing.
  String _formatInterval(Map<String, int> markedTimestamps,
      OffTheBlockEvent startEvent, OffTheBlockEvent endEvent) {
    final start = markedTimestamps[startEvent.name];
    final end = markedTimestamps[endEvent.name];
    if (start != null && end != null) {
      final interval = (end - start) / 1000.0; // Convert ms to seconds
      return interval.toStringAsFixed(2);
    }
    return 'N/A';
  }

  /// Helper to safely calculate the average velocity over a distance.
  /// Returns the formatted string in m/s or 'N/A' if data is missing.
  String _formatVelocity(Map<String, int> markedTimestamps,
      OffTheBlockEvent startEvent, OffTheBlockEvent endEvent, double distance) {
    final start = markedTimestamps[startEvent.name];
    final end = markedTimestamps[endEvent.name];
    if (start != null && end != null) {
      final time = (end - start) / 1000.0;
      if (time > 0) {
        final velocity = distance / time;
        return velocity.toStringAsFixed(2);
      }
    }
    return 'N/A';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Starts'),
      ),
      body: FutureBuilder<List<OffTheBlockAnalysisData>>(
        future: _analysesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No analyses found.'));
          }

          final analyses = snapshot.data!;
          final theme = Theme.of(context);

          // --- ENHANCEMENT: Dynamically collect all jump data keys ---
          final allJumpDataKeys = <String>{};
          for (final analysis in analyses) {
            if (analysis.jumpData != null) {
              allJumpDataKeys.addAll(analysis.jumpData!.keys);
            }
          }
          final sortedJumpDataKeys = allJumpDataKeys.toList()..sort();

          // A map where the key is the metric name and the value is a list of results for each analysis.
          final Map<String, List<String>> comparisonData = {
            'Date': analyses
                .map((a) => DateFormat.yMMMd().format(a.date))
                .toList(),
            'Distance (m)':
            analyses.map((a) => a.startDistance.toStringAsFixed(2)).toList(),
            'Height (m)':
            analyses.map((a) => a.startHeight.toStringAsFixed(2)).toList(),
            'Time on Block (s)': analyses
                .map((a) => _formatInterval(a.markedTimestamps,
                OffTheBlockEvent.startSignal, OffTheBlockEvent.leftBlock))
                .toList(),
            'Flight Time (s)': analyses
                .map((a) => _formatInterval(a.markedTimestamps,
                OffTheBlockEvent.leftBlock, OffTheBlockEvent.touchedWater))
                .toList(),
            'Entry Time (s)': analyses
                .map((a) => _formatInterval(a.markedTimestamps,
                OffTheBlockEvent.touchedWater, OffTheBlockEvent.submergedFully))
                .toList(),
            'Time to 5m (s)': analyses
                .map((a) => _formatInterval(a.markedTimestamps,
                OffTheBlockEvent.startSignal, OffTheBlockEvent.reached5m))
                .toList(),
            'Time to 10m (s)': analyses
                .map((a) => _formatInterval(
                a.markedTimestamps,
                OffTheBlockEvent.startSignal,
                OffTheBlockEvent.reached10m))
                .toList(),
            'Time to 15m (s)': analyses
                .map((a) => _formatInterval(
                a.markedTimestamps,
                OffTheBlockEvent.startSignal,
                OffTheBlockEvent.reached15m))
                .toList(),
            'Avg Velocity to 5m (m/s)': analyses
                .map((a) => _formatVelocity(a.markedTimestamps,
                OffTheBlockEvent.startSignal, OffTheBlockEvent.reached5m, 5.0))
                .toList(),
            'Avg Velocity to 10m (m/s)': analyses
                .map((a) => _formatVelocity(a.markedTimestamps,
                OffTheBlockEvent.startSignal, OffTheBlockEvent.reached10m, 10.0))
                .toList(),
            'Avg Velocity to 15m (m/s)': analyses
                .map((a) => _formatVelocity(a.markedTimestamps,
                OffTheBlockEvent.startSignal, OffTheBlockEvent.reached15m, 15.0))
                .toList(),
          };

          // --- ENHANCEMENT: Add jump data to the comparison map (robustly) ---
          for (final key in sortedJumpDataKeys) {
            comparisonData[key] = analyses.map((a) {
              final value = a.jumpData?[key];
              if (value != null) {
                return value.toStringAsFixed(2);
              }
              // Handle non-numeric jump data gracefully
              return value?.toString() ?? 'N/A';
            }).toList();
          }

          final Map<String, int?> bestValueIndices = {};
          final Map<String, String> averageData = {};
          final Map<String, String> bestData = {};

          const lowerIsBetterMetrics = {
            'Time on Block (s)',
            'Flight Time (s)',
            'Entry Time (s)',
            'Time to 5m (s)',
            'Time to 10m (s)',
            'Time to 15m (s)',
          };
          final higherIsBetterMetrics = {
            'Distance (m)',
            'Height (m)',
            'Avg Velocity to 5m (m/s)',
            'Avg Velocity to 10m (m/s)',
            'Avg Velocity to 15m (m/s)',
            ...sortedJumpDataKeys,
          };

          for (final metric in comparisonData.keys) {
            final isLowerBetter = lowerIsBetterMetrics.contains(metric);
            final isHigherBetter = higherIsBetterMetrics.contains(metric);

            final valuesAsStrings = comparisonData[metric]!;
            final values = valuesAsStrings.map((s) => double.tryParse(s)).whereType<double>().toList();

            if (values.isNotEmpty) {
              final average = values.reduce((a, b) => a + b) / values.length;
              averageData[metric] = average.toStringAsFixed(2);
            }

            if (!isLowerBetter && !isHigherBetter) continue;

            double? bestValue;
            int? bestIndex;

            for (int i = 0; i < valuesAsStrings.length; i++) {
              final value = double.tryParse(valuesAsStrings[i]);
              if (value == null) continue;

              bool isBest = false;
              if (bestValue == null) {
                isBest = true;
              } else if (isLowerBetter && value < bestValue) {
                isBest = true;
              } else if (isHigherBetter && value > bestValue) {
                isBest = true;
              }

              if (isBest) {
                bestValue = value;
                bestIndex = i;
              }
            }
            if (bestValue != null) {
              bestData[metric] = bestValue.toStringAsFixed(2);
            }
            bestValueIndices[metric] = bestIndex;
          }

          final List<dynamic> metricDefinitions = [
            'Date',
            'Distance (m)',
            'Height (m)',
            'Time on Block (s)',
            'Flight Time (s)',
            'Entry Time (s)',
            ...sortedJumpDataKeys,
            {
              'title': 'Time / Velocity to 5m',
              'timeMetric': 'Time to 5m (s)',
              'velocityMetric': 'Avg Velocity to 5m (m/s)',
            },
            {
              'title': 'Time / Velocity to 10m',
              'timeMetric': 'Time to 10m (s)',
              'velocityMetric': 'Avg Velocity to 10m (m/s)',
            },
            {
              'title': 'Time / Velocity to 15m',
              'timeMetric': 'Time to 15m (s)',
              'velocityMetric': 'Avg Velocity to 15m (m/s)',
            },
          ];

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                horizontalMargin: 12.0,
                columnSpacing: 24.0,
                columns: [
                  const DataColumn(
                      label: Text('Metric',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  ...analyses.map((a) => DataColumn(
                      label: SizedBox(
                        width: 100,
                        child: Text(a.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2),
                      ))),
                  const DataColumn(
                      label: Text('Average',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(
                      label: Text('Best',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: metricDefinitions.asMap().entries.map((rowEntry) {
                  final rowIndex = rowEntry.key;
                  final metricDef = rowEntry.value;

                  final rowColor = rowIndex.isEven
                      ? theme.colorScheme.onSurface.withOpacity(0.04)
                      : null;

                  if (metricDef is String) {
                    final metric = metricDef;
                    final values = comparisonData[metric]!;
                    final bestIndex = bestValueIndices[metric];

                    return DataRow(
                      color: MaterialStateProperty.all(rowColor),
                      cells: [
                        DataCell(Text(metric, style: const TextStyle(fontWeight: FontWeight.w500))),
                        ...values.asMap().entries.map((entry) {
                          final colIndex = entry.key;
                          final val = entry.value;
                          final isBest = colIndex == bestIndex;

                          return DataCell(
                            Container(
                              color: isBest ? theme.colorScheme.primary.withOpacity(0.2) : null,
                              child: Center(
                                child: Text(
                                  val,
                                  style: isBest
                                      ? TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  )
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        DataCell(Center(child: Text(averageData[metric] ?? 'N/A'))),
                        DataCell(Center(child: Text(bestData[metric] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)))),
                      ],
                    );
                  } else if (metricDef is Map) {
                    final String title = metricDef['title'];
                    final String timeMetric = metricDef['timeMetric'];
                    final String velocityMetric = metricDef['velocityMetric'];

                    final timeValues = comparisonData[timeMetric]!;
                    final velocityValues = comparisonData[velocityMetric]!;
                    final bestTimeIndex = bestValueIndices[timeMetric];
                    final bestVelocityIndex = bestValueIndices[velocityMetric];

                    return DataRow(
                      color: MaterialStateProperty.all(rowColor),
                      cells: [
                        DataCell(Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
                        ...List.generate(analyses.length, (colIndex) {
                          final timeVal = timeValues[colIndex];
                          final velocityVal = velocityValues[colIndex];
                          final isBestTime = colIndex == bestTimeIndex;
                          final isBestVelocity = colIndex == bestVelocityIndex;

                          return DataCell(
                            Center(
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(
                                      text: '${timeVal}s',
                                      style: isBestTime
                                          ? TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      )
                                          : null,
                                    ),
                                    const TextSpan(text: '\n'),
                                    TextSpan(
                                      text: '${velocityVal}m/s',
                                      style: isBestVelocity
                                          ? TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        DataCell(
                          Center(
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(text: '${averageData[timeMetric] ?? 'N/A'}s\n'),
                                    TextSpan(text: '${averageData[velocityMetric] ?? 'N/A'}m/s'),
                                  ]
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Center(
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(
                                        text: '${bestData[timeMetric] ?? 'N/A'}s',
                                        style: const TextStyle(fontWeight: FontWeight.bold)
                                    ),
                                    const TextSpan(text: '\n'),
                                    TextSpan(
                                        text: '${bestData[velocityMetric] ?? 'N/A'}m/s',
                                        style: const TextStyle(fontWeight: FontWeight.bold)
                                    ),
                                  ]
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return const DataRow(cells: []); // Should not happen
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}