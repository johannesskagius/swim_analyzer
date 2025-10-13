import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/race_data_analyzer.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import 'add_swimmer.dart';
import 'analysis/analysis_level.dart';

class RaceResultsView extends StatefulWidget {
  final List<RaceSegment> recordedSegments;

  // This is nullable, as it's only provided for a 'full' analysis.
  final List<IntervalAttributes>? intervalAttributes;
  final Event event;

  // This tells the view how to interpret the data.
  final AnalysisType analysisType;

  const RaceResultsView({
    super.key,
    required this.recordedSegments,
    required this.event,
    required this.analysisType,
    this.intervalAttributes,
  });

  @override
  State<RaceResultsView> createState() => _RaceResultsViewState();
}

class _RaceResultsViewState extends State<RaceResultsView> {
  late RaceDataAnalyzer raceDataAnalyzer;
  final _saveFormKey = GlobalKey<FormState>();
  final _raceNameController = TextEditingController();
  final _raceDateController = TextEditingController();

  // This list will hold editable stroke counts for 'full' analysis
  late List<double> _editableStrokeCounts;

  List<AppUser> _swimmers = [];
  List<AppUser> _coaches = [];
  AppUser? _currentUser;
  String? _selectedCoachId;
  String? _selectedSwimmerId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _raceDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Initialize stroke counts based on analysis type.
    if (widget.analysisType == AnalysisType.full &&
        widget.intervalAttributes != null) {
      _editableStrokeCounts = widget.intervalAttributes!
          .map((attr) => attr.strokeCount.toDouble())
          .toList();
    } else if (widget.analysisType == AnalysisType.quick &&
        widget.intervalAttributes != null &&
        widget.intervalAttributes!.isNotEmpty) {
      // FIX: This is the robust and correct way to map lap strokes to segments.
      _editableStrokeCounts = [];
      int currentLapIndex = 0;
      final int maxLapIndex = widget.intervalAttributes!.length - 1;

      // Iterate through each segment *interval* (from 1 to length)
      for (int i = 1; i < widget.recordedSegments.length; i++) {
        // The stroke count for this segment interval belongs to the current lap.
        // We use clamp to be absolutely sure we don't exceed the bounds.
        int safeLapIndex = currentLapIndex.clamp(0, maxLapIndex);
        final lapStrokes =
            widget.intervalAttributes![safeLapIndex].strokeCount.toDouble();
        _editableStrokeCounts.add(lapStrokes);

        // If the *previous* segment was a turn, we are now in the next lap.
        if (widget.recordedSegments[i - 1].checkPoint == CheckPoint.turn) {
          currentLapIndex++;
        }
      }
    } else {
      // Fallback for empty attributes or other cases.
      _editableStrokeCounts =
          List.filled(widget.recordedSegments.length - 1, 0.0);
    }

    raceDataAnalyzer = RaceDataAnalyzer(
      recordedSegments: widget.recordedSegments,
      event: widget.event,
      editableStrokeCounts: _editableStrokeCounts,
      poolLength: widget.event.poolLength,
    );
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final userRepo = Provider.of<UserRepository>(context, listen: false);
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser == null) {
        throw Exception("No user logged in");
      }

      final AppUser? currentUser = await userRepo.getMyProfile();
      List<AppUser> swimmers = [];
      List<AppUser> coaches = [];
      String? selectedSwimmerId;
      String? selectedCoachId;

      if (currentUser is Swimmer) {
        swimmers = [currentUser];
        selectedSwimmerId = currentUser.id;
        final coach =
            await userRepo.getUserDocument(currentUser.creatorId ?? '');
        if (coach != null) {
          coaches = [coach];
          selectedCoachId = coach.id;
        }
      } else if (currentUser is Coach) {
        coaches = [currentUser];
        selectedCoachId = currentUser.id;
        swimmers =
            await userRepo.getAllSwimmersFromCoach(coachId: currentUser.id);
      }

      setState(() {
        _currentUser = currentUser;
        _coaches = coaches;
        _swimmers = swimmers;
        _selectedCoachId = selectedCoachId;
        _selectedSwimmerId = selectedSwimmerId;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load user data: $e')));
      }
    }
  }

  Future<void> _saveRaceToFirestore(BuildContext context) async {
    if (widget.recordedSegments.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No data to save.')));
      return;
    }

    final startTime = widget.recordedSegments[0].splitTimeOfTotalRace;
    final List<AnalyzedSegment> analyzedSegments = [];
    int lapIndex = 0;

    for (int i = 0; i < widget.recordedSegments.length; i++) {
      final segment = widget.recordedSegments[i];
      final totalTime = segment.splitTimeOfTotalRace - startTime;
      final splitTime = (i > 0)
          ? (segment.splitTimeOfTotalRace -
              widget.recordedSegments[i - 1].splitTimeOfTotalRace)
          : Duration.zero;

      IntervalAttributes? attributes;
      double strokeCount = 0;
      double? strokeFreq;
      double? strokeLength;
      double? avgSpeed;

      if (widget.analysisType == AnalysisType.full && i > 0) {
        attributes = widget.intervalAttributes?[i - 1];
        strokeCount = _editableStrokeCounts[i - 1];
        strokeFreq =
            raceDataAnalyzer.getStrokeFrequency(i, asStrokesPerMinute: false);
        strokeLength = raceDataAnalyzer.getStrokeLengthAsDouble(i);
        avgSpeed = raceDataAnalyzer.getAverageSpeed(i);
      } else if (widget.analysisType == AnalysisType.quick) {
        if (segment.checkPoint == CheckPoint.turn ||
            segment.checkPoint == CheckPoint.finish) {
          if (lapIndex < (widget.intervalAttributes?.length ?? 0)) {
            final lapAttributes = widget.intervalAttributes![lapIndex];
            attributes = lapAttributes;
            strokeCount = lapAttributes.strokeCount.toDouble();

            // Find the start segment of this lap to calculate metrics
            RaceSegment startOfLapSegment;
            if (lapIndex == 0) {
              startOfLapSegment = widget.recordedSegments.firstWhere(
                  (s) => s.checkPoint == CheckPoint.start,
                  orElse: () => widget.recordedSegments.first);
            } else {
              startOfLapSegment = widget.recordedSegments
                  .where((s) => s.checkPoint == CheckPoint.turn)
                  .toList()[lapIndex - 1];
            }

            final lapTime = segment.splitTimeOfTotalRace -
                startOfLapSegment.splitTimeOfTotalRace;
            final lapDistance = widget.event.poolLength.distance.toDouble();

            if (lapTime > Duration.zero && strokeCount > 0) {
              final lapTimeInSeconds = lapTime.inMilliseconds / 1000.0;
              avgSpeed = lapDistance / lapTimeInSeconds;
              strokeFreq = strokeCount / lapTimeInSeconds;
              strokeLength = lapDistance / strokeCount;
            }
            lapIndex++;
          }
        }
      }

      analyzedSegments.add(
        AnalyzedSegment(
          sequence: i,
          checkPoint: segment.checkPoint.toString().split('.').last,
          distanceMeters: raceDataAnalyzer.getDistanceAsDouble(segment, i),
          totalTimeMillis: totalTime.inMilliseconds,
          splitTimeMillis: splitTime.inMilliseconds,
          dolphinKicks: attributes?.dolphinKickCount,
          strokes: strokeCount.round(),
          breaths: attributes?.breathCount,
          strokeFrequency: strokeFreq,
          strokeLengthMeters: strokeLength,
          //averageSpeedMetersPerSecond: avgSpeed,
        ),
      );
    }

    final newRace = RaceAnalysis.fromSegments(
      eventName: widget.event.name,
      raceName: _raceNameController.text,
      raceDate: DateFormat('yyyy-MM-dd').parse(_raceDateController.text),
      poolLength: widget.event.poolLength,
      stroke: widget.event.stroke,
      distance: widget.event.distance,
      segments: analyzedSegments,
      coachId: _selectedCoachId,
      swimmerId: _selectedSwimmerId,
    );

    try {
      final raceRepository =
          Provider.of<AnalyzesRepository>(context, listen: false);
      await raceRepository.addRace(newRace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Race analysis saved successfully!')),
        );
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving race: $e')));
      }
    }
  }

  void _editStrokeCount(int attributeIndex) {
    if (widget.analysisType != AnalysisType.full) return;

    double tempValue = _editableStrokeCounts[attributeIndex];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Stroke Count'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => setDialogState(
                        () => tempValue = (tempValue - 0.5).clamp(0.0, 50.0)),
                  ),
                  Text(tempValue.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.headlineSmall),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setDialogState(
                        () => tempValue = (tempValue + 0.5).clamp(0.0, 50.0)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _editableStrokeCounts[attributeIndex] = tempValue;
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSaveDialog() async {
    final bool isSwimmer = _currentUser is Swimmer;
    final bool isCoach = _currentUser is Coach;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        String? dialogSwimmerId = _selectedSwimmerId;
        String? dialogCoachId = _selectedCoachId;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Save Race Analysis'),
              content: SingleChildScrollView(
                child: Form(
                  key: _saveFormKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        TextFormField(
                          controller: _raceNameController,
                          decoration:
                              const InputDecoration(labelText: 'Race Name'),
                          validator: (value) =>
                              value!.isEmpty ? 'Please enter a name' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _raceDateController,
                          decoration: const InputDecoration(
                            labelText: 'Race Date',
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          readOnly: true,
                          onTap: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2101),
                            );
                            if (pickedDate != null) {
                              setDialogState(() {
                                _raceDateController.text =
                                    DateFormat('yyyy-MM-dd').format(pickedDate);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: dialogSwimmerId,
                                decoration:
                                    const InputDecoration(labelText: 'Swimmer'),
                                items: _swimmers.map((user) {
                                  return DropdownMenuItem(
                                    value: user.id,
                                    child: Text(user.name),
                                  );
                                }).toList(),
                                onChanged: isSwimmer
                                    ? null
                                    : (value) => setDialogState(
                                        () => dialogSwimmerId = value),
                                validator: (value) => value == null
                                    ? 'Please select a swimmer'
                                    : null,
                              ),
                            ),
                            if (isCoach)
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 8.0, bottom: 4.0),
                                child: IconButton(
                                  icon: const Icon(Icons.add),
                                  tooltip: 'Add New Swimmer',
                                  onPressed: () async {
                                    final newSwimmerAdded = await Navigator.of(
                                            context)
                                        .push(MaterialPageRoute(
                                            builder: (_) => AddSwimmerPage(
                                                coach: _currentUser as Coach)));
                                    if (newSwimmerAdded == true) {
                                      await _loadInitialData();
                                      setDialogState(() {});
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: dialogCoachId,
                          decoration: const InputDecoration(labelText: 'Coach'),
                          items: _coaches.map((user) {
                            return DropdownMenuItem(
                              value: user.id,
                              child: Text(user.name),
                            );
                          }).toList(),
                          onChanged: (isSwimmer || isCoach)
                              ? null
                              : (value) =>
                                  setDialogState(() => dialogCoachId = value),
                          validator: (value) =>
                              value == null ? 'Please select a coach' : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                ElevatedButton(
                  child: const Text('Save'),
                  onPressed: () {
                    if (_saveFormKey.currentState!.validate()) {
                      setState(() {
                        _selectedSwimmerId = dialogSwimmerId;
                        _selectedCoachId = dialogCoachId;
                      });
                      _saveRaceToFirestore(context);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRecordedData = widget.recordedSegments.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.event.name} - Results'),
        actions: [
          if (hasRecordedData)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _showSaveDialog,
              tooltip: 'Save Race Analysis',
            ),
        ],
      ),
      body: hasRecordedData
          ? buildResultsView()
          : const Center(child: Text('No results to display.')),
    );
  }

  // In results_page.dart

  Widget buildResultsView() {
    final startTime = widget.recordedSegments.isNotEmpty
        ? widget.recordedSegments[0].splitTimeOfTotalRace
        : Duration.zero;
    final isBreaststroke = widget.event.stroke == Stroke.breaststroke;
    final isFullAnalysis = widget.analysisType == AnalysisType.full;

    // Define columns based on the analysis type and stroke
    final List<DataColumn> columns = [
      const DataColumn(label: Text('Split')),
      const DataColumn(label: Text('Time')),
      if (!isBreaststroke) const DataColumn(label: Text('Kicks')),
      const DataColumn(label: Text('Strokes')),
      if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
      const DataColumn(label: Text('m/s')),
      const DataColumn(label: Text('Str. Freq\n(str/min)')), // Updated label
      const DataColumn(label: Text('Str. Length\n(m/str)')), // Updated label
    ];

    int lapIndex = 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: columns,
              rows: List<DataRow>.generate(
                widget.recordedSegments.length,
                (index) {
                  final segment = widget.recordedSegments[index];
                  final totalTime = raceDataAnalyzer
                      .formatDuration(segment.splitTimeOfTotalRace - startTime);
                  final splitTime = raceDataAnalyzer.getSplitTime(index);

                  IntervalAttributes? attributes;
                  String strokeCountText = '';
                  String avgSpeedText = '';
                  String strokeFreqText = '';
                  String strokeLengthText = '';

                  if (isFullAnalysis && index > 0) {
                    attributes = widget.intervalAttributes?[index - 1];
                    strokeCountText = _editableStrokeCounts[index - 1]
                        .toStringAsFixed(_editableStrokeCounts[index - 1]
                                    .truncateToDouble() ==
                                _editableStrokeCounts[index - 1]
                            ? 0
                            : 1);
                    avgSpeedText = raceDataAnalyzer
                            .getAverageSpeed(index)
                            ?.toStringAsFixed(2) ??
                        '';
                    strokeFreqText = raceDataAnalyzer
                            .getStrokeFrequency(index,
                                asStrokesPerMinute: false)
                            ?.toStringAsFixed(2) ??
                        '-'; // Pass flag
                    strokeLengthText = raceDataAnalyzer.getStrokeLength(index);
                  } else if (!isFullAnalysis) {
                    if (segment.checkPoint == CheckPoint.turn ||
                        segment.checkPoint == CheckPoint.finish) {
                      if (lapIndex < (widget.intervalAttributes?.length ?? 0)) {
                        attributes = widget.intervalAttributes![lapIndex];
                        strokeCountText = attributes.strokeCount.toString();

                        RaceSegment startOfLapSegment;
                        if (lapIndex == 0) {
                          startOfLapSegment = widget.recordedSegments
                              .firstWhere(
                                  (s) => s.checkPoint == CheckPoint.start,
                                  orElse: () => widget.recordedSegments.first);
                        } else {
                          startOfLapSegment = widget.recordedSegments
                              .where((s) => s.checkPoint == CheckPoint.turn)
                              .toList()[lapIndex - 1];
                        }
                        final endOfLapSegment = segment;
                        final totalLapTime =
                            endOfLapSegment.splitTimeOfTotalRace -
                                startOfLapSegment.splitTimeOfTotalRace;

                        final startSegmentIndex =
                            widget.recordedSegments.indexOf(startOfLapSegment);
                        final endSegmentIndex =
                            widget.recordedSegments.indexOf(endOfLapSegment);

                        RaceSegment? breakoutSegmentInLap;
                        try {
                          breakoutSegmentInLap = widget.recordedSegments
                              .sublist(startSegmentIndex, endSegmentIndex + 1)
                              .firstWhere(
                                  (s) => s.checkPoint == CheckPoint.breakOut);
                        } catch (e) {
                          breakoutSegmentInLap =
                              null; // No breakout found for this lap
                        }

                        final Duration timeToBreakout = breakoutSegmentInLap !=
                                null
                            ? breakoutSegmentInLap.splitTimeOfTotalRace -
                                startOfLapSegment.splitTimeOfTotalRace
                            : const Duration(seconds: 5); // Default estimate

                        const double distanceToBreakout =
                            12.0; // Default estimate

                        final double lapDistance =
                            widget.event.poolLength.distance.toDouble();

                        if (totalLapTime > Duration.zero &&
                            attributes.strokeCount > 0) {
                          // Calculate overall lap speed (m/s)
                          final lapTimeInSeconds =
                              totalLapTime.inMilliseconds / 1000.0;
                          avgSpeedText = (lapDistance / lapTimeInSeconds)
                              .toStringAsFixed(2);

                          // --- Apply new formulas ---

                          // Effective swimming time and distance (surface swimming)
                          final effectiveSwimmingTime =
                              totalLapTime - timeToBreakout;
                          final effectiveSwimmingDistance =
                              lapDistance - distanceToBreakout;

                          if (effectiveSwimmingTime > Duration.zero &&
                              effectiveSwimmingDistance > 0) {
                            // Stroke Frequency (strokes per minute)
                            final strokesPerSecond = attributes.strokeCount /
                                (effectiveSwimmingTime.inMilliseconds / 1000.0);
                            strokeFreqText =
                                (strokesPerSecond * 60).toStringAsFixed(2);

                            // Stroke Length (meters per stroke)
                            strokeLengthText = (effectiveSwimmingDistance /
                                    attributes.strokeCount)
                                .toStringAsFixed(2);
                          }
                        }
                        // --- END: NEW CALCULATION LOGIC ---
                        lapIndex++;
                      }
                    }
                  }

                  return DataRow(cells: <DataCell>[
                    DataCell(
                        Text(raceDataAnalyzer.getDistance(segment, index))),
                    DataCell(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(totalTime,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            if (splitTime != '0.00')
                              Text(splitTime,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    ),
                    if (!isBreaststroke)
                      DataCell(
                          Text(attributes?.dolphinKickCount.toString() ?? '')),
                    DataCell(
                      InkWell(
                        onTap: isFullAnalysis &&
                                index > 0 &&
                                index - 1 < _editableStrokeCounts.length
                            ? () => _editStrokeCount(index - 1)
                            : null,
                        child: Text(strokeCountText,
                            style: TextStyle(
                                color: isFullAnalysis
                                    ? Theme.of(context).primaryColor
                                    : null,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (!isBreaststroke)
                      DataCell(Text(attributes?.breathCount.toString() ?? '')),
                    DataCell(Text(avgSpeedText)),
                    DataCell(Text(strokeFreqText)),
                    DataCell(Text(strokeLengthText)),
                  ]);
                },
              ),
            ),
          ),
          if (raceDataAnalyzer.getBreakoutEstimate() != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(raceDataAnalyzer.getBreakoutEstimate()!),
            ),
        ],
      ),
    );
  }
}
