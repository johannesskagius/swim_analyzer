import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class RaceComparisonPage extends StatefulWidget {
  final List<String> raceIds;

  const RaceComparisonPage({super.key, required this.raceIds});

  @override
  State<RaceComparisonPage> createState() => _RaceComparisonPageState();
}

class _RaceComparisonPageState extends State<RaceComparisonPage> {
  late Future<List<RaceAnalysis>> _racesFuture;
  List<RaceAnalysis>? _loadedRaces;

  @override
  void initState() {
    super.initState();
    _loadAndProcessRaces();
  }

  /// Optimization: Fetches, processes, and caches race data in one go.
  /// This method computes derived metrics like SWOLF, total kicks/breaths,
  /// and organizes segment data for quick access. This prevents recalculating
  /// these values every time the UI or PDF is built, which is a major
  /// performance improvement.
  void _loadAndProcessRaces() {
    final raceRepository = Provider.of<AnalyzesRepository>(context, listen: false);
    final userRepository = Provider.of<UserRepository>(context, listen: false);

    _racesFuture = Future.wait(widget.raceIds.map((id) => raceRepository.getRace(id)))
        .then((races) async {
      // --- START: Performance Logging ---
      final stopwatch = Stopwatch()..start();
      // --- END: Performance Logging ---

      final racesWithNames = await Future.wait(races.map((RaceAnalysis race) async {
        if (race.swimmerName == null || race.swimmerName!.isEmpty) {
          try {
            final user = await userRepository.getUserDocument(race.swimmerId!);
            final name = '${user?.name ?? ''} ${user?.lastName ?? ''}'.trim();
            race.swimmerName = name.isNotEmpty ? name : 'Unknown Swimmer';
          } catch (e) {
            print('Could not fetch user for race ${race.id}: $e');
            race.swimmerName = 'Unknown Swimmer';
          }
        }
        // Optimization: Pre-calculate and cache derived values for each race.
        _processAndCacheRaceData(race);
        return race;
      }));

      racesWithNames.sort((a, b) => a.raceDate?.compareTo(b.raceDate ?? DateTime(0)) ?? 0);

      // --- START: Performance Logging ---
      stopwatch.stop();
      print('Race data processing took ${stopwatch.elapsedMilliseconds}ms for ${races.length} races.');
      // --- END: Performance Logging ---

      if (mounted) {
        setState(() {
          _loadedRaces = racesWithNames;
        });
      }
      return racesWithNames;
    });
  }

  /// Pre-computes derived statistics for a single race analysis.
  void _processAndCacheRaceData(RaceAnalysis race) {
    // Cache segment lookups for efficiency
    final segmentsBySequence = {for (var s in race.segments) s.sequence: s};
    final wallSegments = race.segments
        .where((s) => ['start', 'turn', 'finish'].contains(s.checkPoint))
        .sortedBy<num>((s) => s.sequence);

    // Pre-calculate totals to avoid repeated .map().sum calls
    int totalBreaths = 0;
    int totalKicks = 0;
    for (var segment in race.segments) {
      totalBreaths += segment.breaths ?? 0;
      totalKicks += segment.dolphinKicks ?? 0;
    }
    race.setExtraData('totalBreaths', totalBreaths);
    race.setExtraData('totalKicks', totalKicks);

    // Pre-calculate average SWOLF
    final List<double> lapSwolfScores = [];
    for (int i = 0; i < wallSegments.length - 1; i++) {
      final startLapSegment = wallSegments[i];
      final endLapSegment = wallSegments[i + 1];

      final lapTimeMillis = endLapSegment.totalTimeMillis - startLapSegment.totalTimeMillis;
      int lapStrokes = 0;
      for (int j = startLapSegment.sequence + 1; j <= endLapSegment.sequence; j++) {
        lapStrokes += segmentsBySequence[j]?.strokes ?? 0;
      }

      if (lapTimeMillis > 0 && lapStrokes > 0) {
        lapSwolfScores.add((lapTimeMillis / 1000.0) + lapStrokes);
      }
    }
    if (lapSwolfScores.isNotEmpty) {
      race.setExtraData('averageSwolf', lapSwolfScores.average);
    }
  }


  /// Generates a PDF from the comparison data and opens the native share dialog.
  Future<void> _shareComparison(
      BuildContext context, List<RaceAnalysis> races) async {
    pw.MemoryImage? icon;
    try {
      // Load the app icon from your project's assets.
      final iconData = await rootBundle.load('assets/icon/icon.png');
      icon = pw.MemoryImage(iconData.buffer.asUint8List());
    } catch (e) {
      // Silently fail if the icon isn't found so it doesn't crash.
      print('PDF share: Could not load brand icon: $e');
    }

    // Correctly use swimmerName for display with the right method.
    final swimmerNames =
    races.map((r) => r.swimmerName).whereNotNull().toSet().join(', ');
    final docTitle = races.length == 2
        ? '${races[0].raceName ?? 'Race'} vs ${races[1].raceName ?? 'Race'}'
        : 'Race Comparison';

    // Create the document with metadata.
    final pdf = pw.Document(
      author: swimmerNames,
      creator: 'SwimAnalyzer App',
      title: docTitle,
    );
    // --- END: Metadata and Asset Loading ---

    final theme = Theme.of(context);

    // Load Unicode-compatible fonts. This is essential.
    final font = await PdfGoogleFonts.nunitoRegular();
    final boldFont = await PdfGoogleFonts.nunitoBold();
    final italicFont = await PdfGoogleFonts.nunitoItalic();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) =>
            _buildPdfHeader(races, boldFont, icon, swimmerNames),
        build: (pw.Context pdfContext) => [
          _buildPdfTable(races, theme, font, boldFont, italicFont),
          pw.SizedBox(height: 20),
          pw.Text(
            'Avg. SWOLF = Time per Lap (s) + Strokes per Lap. Lower is better.',
            style: pw.TextStyle(
                font: italicFont, color: PdfColors.grey600, fontSize: 9),
          ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(font: font, color: PdfColors.grey, fontSize: 8),
          ),
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'race-comparison-${DateTime.now().toIso8601String()}.pdf',
    );
  }

  /// Builds the header for the PDF document, including icon and metadata.
  pw.Widget _buildPdfHeader(List<RaceAnalysis> races, pw.Font boldFont,
      pw.MemoryImage? icon, String swimmerNames) {
    final title = races.length == 2
        ? '${races[0].raceName ?? 'Race'} vs ${races[1].raceName ?? 'Race'}'
        : 'Race Comparison';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20.0),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(font: boldFont, fontSize: 18),
                ),
                if (swimmerNames.isNotEmpty) pw.SizedBox(height: 5),
                if (swimmerNames.isNotEmpty)
                  pw.Text(
                    'Swimmer(s): $swimmerNames',
                    style: pw.TextStyle(font: boldFont, fontSize: 10),
                  ),
              ],
            ),
          ),
          if (icon != null)
            pw.Container(
              height: 50,
              width: 50,
              child: pw.Image(icon),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfTable(List<RaceAnalysis> races, ThemeData theme,
      pw.Font font, pw.Font boldFont, pw.Font italicFont) {
    final bool showDiffColumn = races.length == 2;
    final headerStyle = pw.TextStyle(font: boldFont);
    final bestValueStyle = pw.TextStyle(
        color: PdfColor.fromInt(Colors.green.shade800.value), font: boldFont);

    final List<pw.TableRow> tableRows = [];
    const cellPadding =
    pw.EdgeInsets.all(4); // Define padding once for consistency.

    // --- PDF Table Header ---
    tableRows.add(pw.TableRow(
      children: [
        pw.Padding(
            padding: cellPadding, child: pw.Text('Metric', style: headerStyle)),
        ...races.map((race) {
          final raceDate = race.raceDate != null
              ? DateFormat.yMd().format(race.raceDate!)
              : 'No Date';
          final title = race.raceName != null && race.raceName!.isNotEmpty
              ? race.raceName!
              : (race.eventName ?? 'Race');
          return pw.Padding(
              padding: cellPadding,
              child: pw.Text('$title\n$raceDate',
                  style: headerStyle, textAlign: pw.TextAlign.center));
        }),
        if (showDiffColumn)
          pw.Padding(
              padding: cellPadding,
              child: pw.Text('Difference',
                  style: headerStyle, textAlign: pw.TextAlign.center)),
      ],
    ));

    void addPdfStatRow({
      required String title,
      required bool isOverall,
      required String? Function(int index) getValue,
      required num? Function(int index) getNumericValue,
      required bool lowerIsBetter,
      String Function(num value)? formatDiff,
    }) {
      if (List.generate(races.length, (i) => getValue(i))
          .every((v) => v == null || v == '-')) {
        return;
      }

      final numericValues = List.generate(races.length, getNumericValue)
          .whereType<num>()
          .toList();
      final bestValue = numericValues.isEmpty
          ? null
          : (lowerIsBetter
          ? numericValues.reduce(min)
          : numericValues.reduce(max));

      final cells = <pw.Widget>[
        pw.Padding(
          padding: cellPadding,
          child: pw.Text(title,
              style: pw.TextStyle(font: isOverall ? boldFont : font)),
        ),
        ...List.generate(races.length, (index) {
          final isBest = getNumericValue(index) == bestValue;
          return pw.Padding(
            padding: cellPadding,
            child: pw.Text(getValue(index) ?? '-',
                style: isBest ? bestValueStyle : pw.TextStyle(font: font),
                textAlign: pw.TextAlign.center),
          );
        }),
      ];

      if (showDiffColumn) {
        final val1 = getNumericValue(0);
        final val2 = getNumericValue(1);
        String diffText = '-';
        pw.TextStyle diffStyle = pw.TextStyle(font: font);

        if (val1 != null && val2 != null) {
          final diff = val2 - val1;
          if (diff.abs() >= 0.01) {
            final isImprovement = lowerIsBetter ? diff < 0 : diff > 0;
            diffStyle = pw.TextStyle(
                font: boldFont,
                color: isImprovement
                    ? PdfColor.fromInt(Colors.green.shade800.value)
                    : PdfColor.fromInt(Colors.red.shade700.value));
            diffText =
            formatDiff != null ? formatDiff(diff) : diff.toStringAsFixed(1);
          }
        }
        cells.add(pw.Padding(
          padding: cellPadding,
          child: pw.Text(diffText,
              style: diffStyle, textAlign: pw.TextAlign.center),
        ));
      }
      tableRows.add(pw.TableRow(children: cells));
    }

    final signFormatter =
        (num v, int frac) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(frac)}';
    final signMeterFormatter =
        (num v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}m';
    final allBreaststroke =
    races.every((r) => r.stroke?.name.toLowerCase() == 'breaststroke');

    // --- PDF Overall Stats ---
    addPdfStatRow(
        title: 'Swimmer',
        isOverall: true,
        getValue: (i) => races[i].swimmerName,
        getNumericValue: (i) => null,
        lowerIsBetter: false);
    addPdfStatRow(
        title: 'Total Time',
        isOverall: true,
        getValue: (i) => _formatMillis(races[i].finalTime),
        getNumericValue: (i) => races[i].finalTime,
        lowerIsBetter: true,
        formatDiff: (v) => _formatMillis(v.toInt(), showSign: true));
    addPdfStatRow(
        title: 'Total Strokes',
        isOverall: true,
        getValue: (i) => races[i].totalStrokes.toString(),
        getNumericValue: (i) => races[i].totalStrokes,
        lowerIsBetter: true,
        formatDiff: (v) => signFormatter(v, 0));
    if (!allBreaststroke) {
      addPdfStatRow(
          title: 'Total Breaths',
          isOverall: true,
          getValue: (i) => races[i].getExtraData<int>('totalBreaths')?.toString(),
          getNumericValue: (i) => races[i].getExtraData<int>('totalBreaths'),
          lowerIsBetter: true,
          formatDiff: (v) => signFormatter(v, 0));
      addPdfStatRow(
          title: 'Total Kicks',
          isOverall: true,
          getValue: (i) => races[i].getExtraData<int>('totalKicks')?.toString(),
          getNumericValue: (i) => races[i].getExtraData<int>('totalKicks'),
          lowerIsBetter: false,
          formatDiff: (v) => signFormatter(v, 0));
    }
    addPdfStatRow(
        title: 'Avg. Stroke Freq',
        isOverall: true,
        getValue: (i) => races[i].averageStrokeFrequency?.toStringAsFixed(1),
        getNumericValue: (i) => races[i].averageStrokeFrequency,
        lowerIsBetter: false,
        formatDiff: (v) => signFormatter(v, 1));
    addPdfStatRow(
        title: 'Avg. Stroke Len.',
        isOverall: true,
        getValue: (i) => races[i].averageStrokeLengthMeters != null
            ? '${races[i].averageStrokeLengthMeters!.toStringAsFixed(2)}m'
            : '-',
        getNumericValue: (i) => races[i].averageStrokeLengthMeters,
        lowerIsBetter: false,
        formatDiff: signMeterFormatter);
    addPdfStatRow(
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
    addPdfStatRow(
        title: 'Avg. SWOLF',
        isOverall: true,
        getValue: (i) => races[i].getExtraData<double>('averageSwolf')?.toStringAsFixed(1),
        getNumericValue: (i) => races[i].getExtraData<double>('averageSwolf'),
        lowerIsBetter: true,
        formatDiff: (v) => signFormatter(v, 1));

    // --- PDF Per-Segment Stats ---
    // Optimization: This map is now built once and is much faster.
    final Map<int, String> masterCheckPointMap = {
      for (var r in races)
        for (var s in r.segments) s.sequence: s.checkPoint
    }..removeWhere((k, v) => v == 'start');
    final sortedSequences = masterCheckPointMap.keys.toList()..sort();

    // Optimization: Create maps for faster segment lookups.
    final segmentMaps = races
        .map((race) => {for (var s in race.segments) s.sequence: s})
        .toList();
    final wallSegmentMaps = races
        .map((race) => {
      for (var s in race.segments
          .where((s) => ['start', 'turn'].contains(s.checkPoint)))
        s.sequence: s
    })
        .toList();


    for (final sequence in sortedSequences) {
      final checkPoint = masterCheckPointMap[sequence]!;
      final segments = List.generate(
          races.length, (i) => segmentMaps[i][sequence]);

      if (checkPoint == 'breakOut') {
        addPdfStatRow(
          title: 'Breakout (m)',
          isOverall: false,
          getValue: (i) {
            final segment = segments[i];
            if (segment == null) return null;

            // Optimization: Find previous wall segment more efficiently.
            final prevWall = wallSegmentMaps[i].entries
                .lastWhereOrNull((entry) => entry.key < segment.sequence)
                ?.value;

            final breakoutDist =
                segment.distanceMeters - (prevWall?.distanceMeters ?? 0.0);
            return breakoutDist > 0 ? breakoutDist.toStringAsFixed(1) : null;
          },
          getNumericValue: (i) {
            final segment = segments[i];
            if (segment == null) return null;
            final prevWall = wallSegmentMaps[i].entries
                .lastWhereOrNull((entry) => entry.key < segment.sequence)
                ?.value;

            final breakoutDist =
                segment.distanceMeters - (prevWall?.distanceMeters ?? 0.0);
            return breakoutDist > 0 ? breakoutDist : null;
          },
          lowerIsBetter: false,
          formatDiff: (v) => signFormatter(v, 1),
        );
      } else {
        final distance =
            segments.firstWhereOrNull((s) => s != null)?.distanceMeters;
        if (distance == null) continue;
        final distanceLabel =
            '${distance.toStringAsFixed(distance.truncateToDouble() == distance ? 0 : 1)}m';

        tableRows.add(pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              pw.Container(
                  padding: cellPadding,
                  child: pw.Text(distanceLabel,
                      style: pw.TextStyle(font: boldFont))),
              ...List.generate(races.length, (i) {
                final segment = segments.length > i ? segments[i] : null;
                return pw.Container(
                  padding: cellPadding,
                  alignment: pw.Alignment.center,
                  child: pw.Text(_formatMillis(segment?.totalTimeMillis) ?? '-',
                      style: pw.TextStyle(font: boldFont)),
                );
              }),
              if (showDiffColumn) pw.Container(padding: cellPadding),
            ]));

        addPdfStatRow(
            title: 'Split',
            isOverall: false,
            getValue: (i) => _formatMillis(segments[i]?.splitTimeMillis),
            getNumericValue: (i) => segments[i]?.splitTimeMillis,
            lowerIsBetter: true,
            formatDiff: (v) => _formatMillis(v.toInt(), showSign: true));
        addPdfStatRow(
            title: 'Strokes',
            isOverall: false,
            getValue: (i) => segments[i]?.strokes?.toString(),
            getNumericValue: (i) => segments[i]?.strokes,
            lowerIsBetter: true,
            formatDiff: (v) => signFormatter(v, 0));
        if (!allBreaststroke) {
          addPdfStatRow(
              title: 'Breaths',
              isOverall: false,
              getValue: (i) => segments[i]?.breaths?.toString(),
              getNumericValue: (i) => segments[i]?.breaths,
              lowerIsBetter: true,
              formatDiff: (v) => signFormatter(v, 0));
          if (checkPoint != 'breakOut') {
            addPdfStatRow(
                title: 'Dolphin Kicks',
                isOverall: false,
                getValue: (i) => segments[i]?.dolphinKicks?.toString(),
                getNumericValue: (i) => segments[i]?.dolphinKicks,
                lowerIsBetter: false,
                formatDiff: (v) => signFormatter(v, 0));
          }
        }
        addPdfStatRow(
            title: 'Stroke Freq.',
            isOverall: false,
            getValue: (i) => segments[i]?.strokeFrequency?.toStringAsFixed(1),
            getNumericValue: (i) => segments[i]?.strokeFrequency,
            lowerIsBetter: false,
            formatDiff: (v) => signFormatter(v, 1));
        addPdfStatRow(
            title: 'Stroke Len.',
            isOverall: false,
            getValue: (i) => segments[i]?.strokeLengthMeters != null
                ? '${segments[i]!.strokeLengthMeters!.toStringAsFixed(2)}m'
                : '-',
            getNumericValue: (i) => segments[i]?.strokeLengthMeters,
            lowerIsBetter: false,
            formatDiff: signMeterFormatter);
        addPdfStatRow(
            title: 'Avg. Speed (m/s)',
            isOverall: false,
            getValue: (i) => _calculateSpeed(segments[i]?.strokeLengthMeters,
                segments[i]?.strokeFrequency)
                ?.toStringAsFixed(2),
            getNumericValue: (i) => _calculateSpeed(
                segments[i]?.strokeLengthMeters, segments[i]?.strokeFrequency),
            lowerIsBetter: false,
            formatDiff: (v) => signFormatter(v, 2));
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        ...Map.fromIterable(List.generate(races.length, (i) => i + 1),
            value: (_) => const pw.FlexColumnWidth(1)),
        if (showDiffColumn) races.length + 1: const pw.FlexColumnWidth(1),
      },
      children: tableRows,
      tableWidth: pw.TableWidth.max,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Race Comparison'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _loadedRaces == null
                ? null
                : () => _shareComparison(context, _loadedRaces!),
            tooltip: 'Share as PDF',
          ),
        ],
      ),
      body: FutureBuilder<List<RaceAnalysis>>(
        future: _racesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _loadedRaces == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text(
                    'Error: ${snapshot.error ?? "Could not load race data."}'));
          }
          if (_loadedRaces == null || _loadedRaces!.isEmpty) {
            return const Center(child: Text("No races found to compare."));
          }

          // Optimization: The build method is now much lighter as it receives
          // pre-processed data.
          return _buildComparisonTable(context, _loadedRaces!);
        },
      ),
    );
  }

  Widget _buildComparisonTable(BuildContext context, List<RaceAnalysis> races) {
    // Optimization: _buildStatRows is now much faster because it uses
    // pre-calculated data and doesn't perform heavy computations.
    final statRows = _buildStatRows(context, races);
    final raceDataColumns = _buildDataColumns(races);

    // This layout uses a single, horizontally-scrolling DataTable
    // to ensure all rows remain perfectly aligned.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        horizontalMargin: 12,
        columnSpacing: 24,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 48,
        headingRowHeight: 80,
        columns: [
          // The first, "sticky" column header for metrics.
          const DataColumn(
              label: Text('Metric',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          // The rest of the (scrolling) column headers for races.
          ...raceDataColumns,
        ],
        // The rows contain all cells (metric + data) and will align correctly.
        rows: statRows,
      ),
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
      final allDisplayValues = List.generate(races.length, (i) => getValue(i));
      if (allDisplayValues.every((value) => value == null || value == '-')) {
        return;
      }

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

    final signFormatter =
        (num v, int frac) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(frac)}';
    final signMeterFormatter =
        (num v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}m';

    // --- Overall Statistics ---
    // Optimization: These calls now read pre-computed values from `race.extraData`
    // instead of calculating them on the fly.
    addStatRow(
      title: 'Swimmer',
      isOverall: true,
      getValue: (i) => races[i].swimmerName,
      getNumericValue: (i) => null,
      lowerIsBetter: false,
    );
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
          getValue: (i) => races[i].getExtraData<int>('totalBreaths')?.toString(),
          getNumericValue: (i) => races[i].getExtraData<int>('totalBreaths'),
          lowerIsBetter: true,
          formatDiff: (v) => signFormatter(v, 0));
      addStatRow(
          title: 'Total Kicks',
          isOverall: true,
          getValue: (i) => races[i].getExtraData<int>('totalKicks')?.toString(),
          getNumericValue: (i) => races[i].getExtraData<int>('totalKicks'),
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
        getValue: (i) => races[i].getExtraData<double>('averageSwolf')?.toStringAsFixed(1),
        getNumericValue: (i) => races[i].getExtraData<double>('averageSwolf'),
        lowerIsBetter: true,
        formatDiff: (v) => signFormatter(v, 1));

    // --- Per-Segment Statistics ---
    // Optimization: Building these maps is faster now.
    final Map<int, String> masterCheckPointMap = {};
    for (final race in races) {
      for (final segment in race.segments) {
        masterCheckPointMap.putIfAbsent(
            segment.sequence, () => segment.checkPoint);
      }
    }
    masterCheckPointMap.removeWhere((seq, cp) => cp == 'start');
    final sortedSequences = masterCheckPointMap.keys.toList()..sort();

    // Optimization: Create maps for O(1) segment lookups inside the loop.
    final segmentMaps = races
        .map((race) => {for (var s in race.segments) s.sequence: s})
        .toList();
    final wallSegmentMaps = races
        .map((race) => {
      for (var s in race.segments
          .where((s) => ['start', 'turn'].contains(s.checkPoint)))
        s.sequence: s
    })
        .toList();

    for (final sequence in sortedSequences) {
      final checkPoint = masterCheckPointMap[sequence]!;
      // Optimization: Direct lookup instead of looping with firstWhereOrNull.
      final segments = List.generate(races.length, (i) => segmentMaps[i][sequence]);

      if (checkPoint == 'breakOut') {
        addStatRow(
          title: 'Breakout (m)',
          isOverall: false,
          getValue: (i) {
            final segment = segments[i];
            if (segment == null) return null;
            // Optimization: Efficiently find the previous wall segment from the map.
            final prevWall = wallSegmentMaps[i].entries
                .lastWhereOrNull((entry) => entry.key < segment.sequence)
                ?.value;
            final breakoutDist =
                segment.distanceMeters - (prevWall?.distanceMeters ?? 0.0);
            return breakoutDist > 0 ? breakoutDist.toStringAsFixed(1) : null;
          },
          getNumericValue: (i) {
            final segment = segments[i];
            if (segment == null) return null;
            final prevWall = wallSegmentMaps[i].entries
                .lastWhereOrNull((entry) => entry.key < segment.sequence)
                ?.value;
            final breakoutDist =
                segment.distanceMeters - (prevWall?.distanceMeters ?? 0.0);
            return breakoutDist > 0 ? breakoutDist : null;
          },
          lowerIsBetter: false,
          // Longer breakout is generally better
          formatDiff: (v) => signFormatter(v, 1),
        );
      } else {
        final distance =
            segments.firstWhereOrNull((s) => s != null)?.distanceMeters;
        if (distance == null) continue;

        final distanceLabel =
            '${distance.toStringAsFixed(distance.truncateToDouble() == distance ? 0 : 1)}m';

        final headerCells = <DataCell>[
          DataCell(
            Text(
              distanceLabel,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ...List.generate(races.length, (i) {
            final segment = segments.length > i ? segments[i] : null;
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
          }),
          if (showDiffColumn) const DataCell(SizedBox()),
        ];

        rows.add(DataRow(
            color: MaterialStateProperty.all(Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withOpacity(0.3)),
            cells: headerCells));

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
            getValue: (i) => _calculateSpeed(segments[i]?.strokeLengthMeters,
                segments[i]?.strokeFrequency)
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

  // This function is now only used for PDF generation, which happens less frequently.
  // The UI uses the pre-calculated `averageSwolf` value.
  double? _calculateAverageSwolf(RaceAnalysis race) {
    // Check if the value was pre-calculated and cached.
    final cachedSwolf = race.getExtraData<double>('averageSwolf');
    if (cachedSwolf != null) return cachedSwolf;

    // Fallback to calculation if not cached (for robustness).
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
    // Use a standard dash for zero difference, which is Unicode-safe.
    if (diff.abs() < 0.01)
      return const DataCell(Center(
          child: Text('-', style: TextStyle(fontWeight: FontWeight.bold))));

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
