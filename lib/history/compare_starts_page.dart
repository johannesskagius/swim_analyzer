import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/start/off_the_block_enums.dart';
import 'package:swim_apps_shared/objects/off_the_block_model.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

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
    _fetchAnalyses();
  }

  // --- REFACTOR: Isolate data fetching logic ---
  // This makes it easier to handle errors and reload data if necessary.
  void _fetchAnalyses() {
    try {
      final analysisRepository = context.read<AnalyzesRepository>();
      _analysesFuture = analysisRepository.getOffTheBlockAnalysesByIds(
          analysisIds: widget.analysisIds);
    } catch (e, s) {
      // --- ERROR HANDLING: Catch potential errors during initial data fetch setup ---
      // This could happen if the context is unusual or the repository is not available.
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Failed to initiate getOffTheBlockAnalysesByIds call.');
      // Set a failed future to display an error message in the UI.
      _analysesFuture = Future.error(
          'Failed to load analysis data. Please try again.',
          StackTrace.current);
    }
  }

  /// Helper to safely calculate the time interval between two events.
  /// Returns the formatted string in seconds or 'N/A' if data is missing.
  String _formatInterval(Map<String, int> markedTimestamps,
      OffTheBlockEvent startEvent, OffTheBlockEvent endEvent) {
    try {
      final start = markedTimestamps[startEvent.name];
      final end = markedTimestamps[endEvent.name];
      if (start != null && end != null) {
        final interval = (end - start) / 1000.0; // Convert ms to seconds
        return interval.toStringAsFixed(2);
      }
      return 'N/A';
    } catch (e, s) {
      // --- ERROR HANDLING: Log unexpected calculation errors ---
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Error formatting interval for events: '
              '${startEvent.name} to ${endEvent.name}');
      return 'Err'; // Return a distinct string for error cases
    }
  }

  /// Helper to safely calculate the average velocity over a distance.
  /// Returns the formatted string in m/s or 'N/A' if data is missing or time is zero.
  String _formatVelocity(Map<String, int> markedTimestamps,
      OffTheBlockEvent startEvent, OffTheBlockEvent endEvent, double distance) {
    try {
      final start = markedTimestamps[startEvent.name];
      final end = markedTimestamps[endEvent.name];
      if (start != null && end != null) {
        final time = (end - start) / 1000.0;
        // --- STABILITY: Prevent division by zero ---
        if (time > 0) {
          final velocity = distance / time;
          return velocity.toStringAsFixed(2);
        }
      }
      return 'N/A';
    } catch (e, s) {
      // --- ERROR HANDLING: Log unexpected calculation errors ---
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Error formatting velocity for events: '
              '${startEvent.name} to ${endEvent.name}');
      return 'Err';
    }
  }

  // --- REFACTOR: Main build method now focuses on handling Future states ---
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
          // --- ERROR HANDLING: Display a user-friendly message for failed data fetches ---
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading analyses: ${snapshot.error}'),
                ));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No analyses found.'));
          }

          // Once data is available, delegate the complex UI building to a separate method.
          return _buildComparisonTable(context, snapshot.data!);
        },
      ),
    );
  }

  // --- REFACTOR: Extracted the main table building logic into its own method ---
  /// Builds the scrollable DataTable from the provided analysis data.
  /// This improves readability by separating data processing from widget structure.
  Widget _buildComparisonTable(
      BuildContext context, List<OffTheBlockAnalysisData> analyses) {
    final theme = Theme.of(context);

    // --- Data Processing ---
    // Safely collect all unique jump data keys from all analyses.
    final allJumpDataKeys = <String>{};
    for (final analysis in analyses) {
      if (analysis.jumpData != null) {
        allJumpDataKeys.addAll(analysis.jumpData!.keys);
      }
    }
    final sortedJumpDataKeys = allJumpDataKeys.toList()..sort();

    // The map holding all data for the comparison table.
    final Map<String, List<String>> comparisonData = {
      'Date': analyses.map((a) => DateFormat.yMMMd().format(a.date)).toList(),
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
      'Time to 10m (s)': analyses
          .map((a) => _formatInterval(a.markedTimestamps,
          OffTheBlockEvent.startSignal, OffTheBlockEvent.reached10m))
          .toList(),
      'Time to 15m (s)': analyses
          .map((a) => _formatInterval(a.markedTimestamps,
          OffTheBlockEvent.startSignal, OffTheBlockEvent.reached15m))
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

    // Robustly add jump data to the comparison map.
    for (final key in sortedJumpDataKeys) {
      comparisonData[key] = analyses.map((a) {
        final value = a.jumpData?[key];
        // --- STABILITY: Handle both numeric and non-numeric jump data gracefully ---
        if (value is num && value != null) {
          return value.toStringAsFixed(2);
        }
        return value?.toString() ?? 'N/A';
      }).toList();
    }

    // --- Metric Definitions & Calculations ---
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

    // Calculate average, best value, and best index for each metric.
    for (final metric in comparisonData.keys) {
      final isLowerBetter = lowerIsBetterMetrics.contains(metric);
      final isHigherBetter = higherIsBetterMetrics.contains(metric);

      // --- STABILITY: Use null-safe access and provide a fallback empty list ---
      final valuesAsStrings = comparisonData[metric] ?? [];
      final values = valuesAsStrings
          .map((s) => double.tryParse(s))
          .whereType<double>()
          .toList();

      if (values.isNotEmpty) {
        final average = values.reduce((a, b) => a + b) / values.length;
        averageData[metric] = average.toStringAsFixed(2);
      } else {
        averageData[metric] = 'N/A';
      }

      // Skip best/worst calculation for non-numeric or non-comparable metrics like 'Date'.
      if (!isLowerBetter && !isHigherBetter) continue;

      double? bestValue;
      int? bestIndex;

      for (int i = 0; i < valuesAsStrings.length; i++) {
        final value = double.tryParse(valuesAsStrings[i]);
        if (value == null) continue; // Skip non-numeric values

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

    // Define the order and structure of rows in the DataTable.
    final List<dynamic> metricDefinitions = [
      'Date',
      'Distance (m)',
      'Height (m)',
      'Time on Block (s)',
      'Flight Time (s)',
      'Entry Time (s)',
      ...sortedJumpDataKeys,
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

    // --- Widget Building ---
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          horizontalMargin: 12.0,
          columnSpacing: 24.0,
          columns: [
            const DataColumn(
                label:
                Text('Metric', style: TextStyle(fontWeight: FontWeight.bold))),
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
                label:
                Text('Best', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: metricDefinitions.asMap().entries.map((rowEntry) {
            final rowIndex = rowEntry.key;
            final metricDef = rowEntry.value;
            final rowColor = rowIndex.isEven
                ? theme.colorScheme.onSurface.withAlpha(4)
                : null;

            if (metricDef is String) {
              return _buildMetricRow(context, metricDef, rowColor,
                  comparisonData, bestValueIndices, averageData, bestData);
            } else if (metricDef is Map) {
              return _buildCombinedMetricRow(
                  context,
                  metricDef as Map<String, String>,
                  rowColor,
                  analyses.length,
                  comparisonData,
                  bestValueIndices,
                  averageData,
                  bestData);
            } else {
              // --- STABILITY: This case should not be reached with the current logic ---
              // This block handles unexpected types in metricDefinitions, which indicates
              // a developer error. We log it for debugging but prevent a UI crash.
              final error = ArgumentError(
                  'Unknown metric definition type: ${metricDef?.runtimeType}');
              FirebaseCrashlytics.instance.recordError(
                error,
                StackTrace.current,
                reason: 'An unexpected type was found in metricDefinitions.',
                fatal: false, // Non-fatal for the user, but needs developer attention.
              );
              // Return a visually distinct error row to make the problem obvious
              // without crashing the application.
              return DataRow(
                color:
                WidgetStateProperty.all(theme.colorScheme.errorContainer),
                cells: [
                  DataCell(Text(
                    'Error: Unknown row type',
                    style: TextStyle(color: theme.colorScheme.onError),
                  )),
                  // Add empty cells to match the table's column count and avoid layout errors.
                  ...List.generate(
                      analyses.length + 2, (_) => const DataCell(SizedBox.shrink())),
                ],
              );
            }
          }).toList(),
        ),
      ),
    );
  }

  // --- REFACTOR: Extracted single metric row building logic ---
  /// Builds a DataRow for a single metric (e.g., 'Distance (m)').
  DataRow _buildMetricRow(
      BuildContext context,
      String metric,
      Color? rowColor,
      Map<String, List<String>> comparisonData,
      Map<String, int?> bestValueIndices,
      Map<String, String> averageData,
      Map<String, String> bestData,
      ) {
    final theme = Theme.of(context);
    // --- STABILITY: Provide an empty list as a fallback to prevent crashes ---
    final values = comparisonData[metric] ?? [];
    final bestIndex = bestValueIndices[metric];

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(Text(metric, style: const TextStyle(fontWeight: FontWeight.w500))),
        ...values.asMap().entries.map((entry) {
          final colIndex = entry.key;
          final val = entry.value;
          final isBest = colIndex == bestIndex;

          return DataCell(
            Container(
              color: isBest ? theme.colorScheme.primary.withAlpha(20) : null,
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
        DataCell(Center(
            child: Text(bestData[metric] ?? 'N/A',
                style: const TextStyle(fontWeight: FontWeight.bold)))),
      ],
    );
  }

  // --- REFACTOR: Extracted combined metric row building logic ---
  /// Builds a DataRow for combined metrics (e.g., 'Time / Velocity to 10m').
  DataRow _buildCombinedMetricRow(
      BuildContext context,
      Map<String, String> metricDef,
      Color? rowColor,
      int analysisCount,
      Map<String, List<String>> comparisonData,
      Map<String, int?> bestValueIndices,
      Map<String, String> averageData,
      Map<String, String> bestData,
      ) {
    final theme = Theme.of(context);
    final String title = metricDef['title']!;
    final String timeMetric = metricDef['timeMetric']!;
    final String velocityMetric = metricDef['velocityMetric']!;

    // --- STABILITY: Use null-safe access on potentially missing data ---
    final timeValues = comparisonData[timeMetric];
    final velocityValues = comparisonData[velocityMetric];
    final bestTimeIndex = bestValueIndices[timeMetric];
    final bestVelocityIndex = bestValueIndices[velocityMetric];

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
        ...List.generate(analysisCount, (colIndex) {
          // --- STABILITY: Gracefully handle missing values with 'N/A' ---
          final timeVal = timeValues?[colIndex] ?? 'N/A';
          final velocityVal = velocityValues?[colIndex] ?? 'N/A';
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
        // Average column
        DataCell(
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(text: '${averageData[timeMetric] ?? 'N/A'}s\n'),
                    TextSpan(text: '${averageData[velocityMetric] ?? 'N/A'}m/s'),
                  ]),
            ),
          ),
        ),
        // Best column
        DataCell(
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                  style: DefaultTextStyle.of(context).style,
                  children: [
                    TextSpan(
                        text: '${bestData[timeMetric] ?? 'N/A'}s',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(text: '\n'),
                    TextSpan(
                        text: '${bestData[velocityMetric] ?? 'N/A'}m/s',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
            ),
          ),
        ),
      ],
    );
  }
}
