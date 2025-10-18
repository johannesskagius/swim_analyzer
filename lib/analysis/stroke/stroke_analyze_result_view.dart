import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis_repository.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_efficiency_event.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class StrokeAnalysisResultView extends StatefulWidget {
  final IntensityZone intensity;
  final Map<StrokeEfficiencyEvent, Duration> markedTimestamps;
  final List<Duration> strokeTimestamps;
  final double strokeFrequency;
  final Stroke stroke;
  final AppUser user;

  const StrokeAnalysisResultView({
    super.key,
    required this.intensity,
    required this.markedTimestamps,
    required this.strokeTimestamps,
    required this.strokeFrequency,
    required this.stroke,
    required this.user,
  });

  @override
  State<StrokeAnalysisResultView> createState() =>
      _StrokeAnalysisResultViewState();
}

class _StrokeAnalysisResultViewState extends State<StrokeAnalysisResultView> {
  late final AppUser _currentUser;
  late final UserRepository _userRepository;
  Future<List<AppUser>>? _clubSwimmersFuture;

  @override
  void initState() {
    super.initState();
    // It's safe to assign widget data here.
    _currentUser = widget.user;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch dependencies from Provider here.
    _userRepository = Provider.of<UserRepository>(context);

    // Initialize the future for fetching swimmers.
    if (_currentUser.userType == UserType.coach) {
      setState(() {
        if (_currentUser.clubId != null && _currentUser.clubId!.isNotEmpty) {
          // Assumes getUserByClub returns a Stream<List<AppUser>>
          _clubSwimmersFuture =
              _userRepository.getUsersByClub(_currentUser.clubId!).first;
        } else {
          // Assumes getUsersCreatedByMe returns a Stream<List<AppUser>>
          _clubSwimmersFuture = _userRepository.getUsersCreatedByMe().first;
        }
      });
    }
  }

  void _showSaveDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    AppUser? selectedSwimmer; // Use AppUser and scope it to the dialog
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: !isSaving, // Prevent closing while saving
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Save Stroke Analysis'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Please enter a title'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        title: Text(
                            'Date: ${"${selectedDate.toLocal()}".split(' ')[0]}'),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2101),
                          );
                          if (picked != null && picked != selectedDate) {
                            setDialogState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                      ),
                      if (_currentUser.userType == UserType.coach &&
                          _clubSwimmersFuture != null)
                        FutureBuilder<List<AppUser>>(
                          future: _clubSwimmersFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}');
                            }
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Text('No swimmers found.');
                            }
                            final swimmers = snapshot.data!;
                            swimmers.removeWhere((appUser) =>
                                appUser.userType != UserType.swimmer);
                            return DropdownButtonFormField<AppUser>(
                              initialValue: selectedSwimmer,
                              hint: const Text('Assign to swimmer'),
                              onChanged: (AppUser? newValue) {
                                setDialogState(() {
                                  selectedSwimmer = newValue;
                                });
                              },
                              items: swimmers.map<DropdownMenuItem<AppUser>>(
                                  (AppUser user) {
                                return DropdownMenuItem<AppUser>(
                                  value: user,
                                  child: Text(user.name),
                                );
                              }).toList(),
                              validator: (value) => value == null
                                  ? 'Please select a swimmer'
                                  : null,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            if (_currentUser.userType == UserType.coach &&
                                selectedSwimmer == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please select a swimmer to assign the analysis to.')));
                              return;
                            }
                            setDialogState(() => isSaving = true);
                            try {
                              final swimmerId =
                                  _currentUser.userType == UserType.coach
                                      ? selectedSwimmer!.id
                                      : _currentUser.id;
                              await _saveAnalysis(
                                title: titleController.text,
                                date: selectedDate,
                                swimmerId: swimmerId,
                              );
                              if (mounted) {
                                Navigator.of(dialogContext)
                                    .pop(); // Close dialog on success
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Analysis Saved!')));
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Failed to save analysis: $e')));
                              }
                            } finally {
                              if (mounted) {
                                setDialogState(() => isSaving = false);
                              }
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveAnalysis({
    required String title,
    required DateTime date,
    required String swimmerId,
  }) async {
    // 1. Re-calculate all metrics to ensure data integrity
    final pushOffTime =
        widget.markedTimestamps[StrokeEfficiencyEvent.pushOffWall];
    final breakoutTime =
        widget.markedTimestamps[StrokeEfficiencyEvent.breakout];
    final timeTo15m = widget.markedTimestamps[StrokeEfficiencyEvent.reached15m];
    final timeTo25m = widget.markedTimestamps[StrokeEfficiencyEvent.reached25m];

    double? breakoutDist;
    double? underwaterSpeed;
    Duration? timeToBreakout;

    if (pushOffTime != null && breakoutTime != null && timeTo15m != null) {
      final durationTo15m = timeTo15m - pushOffTime;
      if (durationTo15m.inMilliseconds > 0) {
        final avgSpeedTo15m = 15.0 / (durationTo15m.inMilliseconds / 1000.0);
        timeToBreakout = breakoutTime - pushOffTime;
        breakoutDist = avgSpeedTo15m * (timeToBreakout.inMilliseconds / 1000.0);
        if (timeToBreakout.inMilliseconds > 0) {
          underwaterSpeed =
              breakoutDist / (timeToBreakout.inMilliseconds / 1000.0);
        }
      }
    }

    final duration0_15 = (timeTo15m != null && pushOffTime != null)
        ? timeTo15m - pushOffTime
        : null;
    final duration15_25 =
        (timeTo25m != null && timeTo15m != null) ? timeTo25m - timeTo15m : null;
    final duration0_25 = (timeTo25m != null && pushOffTime != null)
        ? timeTo25m - pushOffTime
        : null;

    final speed0_15 = _getSegmentSpeed(pushOffTime, timeTo15m, 15.0);
    final speed15_25 = _getSegmentSpeed(timeTo15m, timeTo25m, 10.0);
    final speed0_25 = _getSegmentSpeed(pushOffTime, timeTo25m, 25.0);

    final taps0_15 = _getStrokesInSegment(pushOffTime, timeTo15m);
    final taps15_25 = _getStrokesInSegment(timeTo15m, timeTo25m);

    final freq0_15 = _calculateFrequency(taps0_15);
    final freq15_25 = _calculateFrequency(taps15_25);

    final isDoubleTap = widget.stroke == Stroke.breaststroke ||
        widget.stroke == Stroke.butterfly;
    final tapsAfterBreakout0_15 = (breakoutTime != null && timeTo15m != null)
        ? widget.strokeTimestamps
            .where((t) => t > breakoutTime && t <= timeTo15m)
            .toList()
        : <Duration>[];
    final tapsAfterBreakout15_25 = (timeTo15m != null && timeTo25m != null)
        ? widget.strokeTimestamps
            .where((t) => t > timeTo15m && t <= timeTo25m)
            .toList()
        : <Duration>[];
    final tapsAfterBreakout0_25 = (breakoutTime != null && timeTo25m != null)
        ? widget.strokeTimestamps
            .where((t) => t > breakoutTime && t <= timeTo25m)
            .toList()
        : <Duration>[];

    final numStrokes0_15 = isDoubleTap
        ? (tapsAfterBreakout0_15.length / 2).floor()
        : tapsAfterBreakout0_15.length;
    final numStrokes15_25 = isDoubleTap
        ? (tapsAfterBreakout15_25.length / 2).floor()
        : tapsAfterBreakout15_25.length;
    final numStrokes0_25 = isDoubleTap
        ? (tapsAfterBreakout0_25.length / 2).floor()
        : tapsAfterBreakout0_25.length;

    final strokeLength0_15 = (breakoutDist != null && numStrokes0_15 > 0)
        ? (15.0 - breakoutDist) / numStrokes0_15
        : null;
    final strokeLength15_25 =
        (numStrokes15_25 > 0) ? 10.0 / numStrokes15_25 : null;
    final strokeLength0_25 = (breakoutDist != null && numStrokes0_25 > 0)
        ? (25.0 - breakoutDist) / numStrokes0_25
        : null;

    final si0_15 = (speed0_15 != null && strokeLength0_15 != null)
        ? speed0_15 * strokeLength0_15
        : null;
    final si15_25 = (speed15_25 != null && strokeLength15_25 != null)
        ? speed15_25 * strokeLength15_25
        : null;
    final si0_25 = (speed0_25 != null && strokeLength0_25 != null)
        ? speed0_25 * strokeLength0_25
        : null;

    final phase1_0_15 = _getAveragePhaseMetricsForSegment(
        isPhase1: true,
        segmentStart: pushOffTime,
        segmentEnd: timeTo15m,
        segmentSpeed: speed0_15);
    final phase2_0_15 = _getAveragePhaseMetricsForSegment(
        isPhase1: false,
        segmentStart: pushOffTime,
        segmentEnd: timeTo15m,
        segmentSpeed: speed0_15);
    final phase1_15_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: true,
        segmentStart: timeTo15m,
        segmentEnd: timeTo25m,
        segmentSpeed: speed15_25);
    final phase2_15_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: false,
        segmentStart: timeTo15m,
        segmentEnd: timeTo25m,
        segmentSpeed: speed15_25);
    final phase1_0_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: true,
        segmentStart: pushOffTime,
        segmentEnd: timeTo25m,
        segmentSpeed: speed0_25);
    final phase2_0_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: false,
        segmentStart: pushOffTime,
        segmentEnd: timeTo25m,
        segmentSpeed: speed0_25);

    // 2. Construct the data models
    final underwaterMetrics = UnderwaterMetrics(
      timeToBreakout: timeToBreakout!.inMilliseconds / 1000.0,
      breakoutDistance: breakoutDist,
      underwaterSpeed: underwaterSpeed,
    );

    final segmentMetrics0_15 = SegmentMetrics(
      time: duration0_15!.inMilliseconds / 1000.0,
      speed: speed0_15,
      strokeCount: numStrokes0_15 > 0 ? numStrokes0_15 : null,
      frequency: freq0_15,
      strokeLength: strokeLength0_15,
      strokeIndex: si0_15,
      phase1Time: phase1_0_15?.$1,
      phase1Distance: phase1_0_15?.$2,
      phase2Time: phase2_0_15?.$1,
      phase2Distance: phase2_0_15?.$2,
    );

    final segmentMetrics15_25 = SegmentMetrics(
      time: duration15_25!.inMilliseconds / 1000.0,
      speed: speed15_25,
      strokeCount: numStrokes15_25 > 0 ? numStrokes15_25 : null,
      frequency: freq15_25,
      strokeLength: strokeLength15_25,
      strokeIndex: si15_25,
      phase1Time: phase1_15_25?.$1,
      phase1Distance: phase1_15_25?.$2,
      phase2Time: phase2_15_25?.$1,
      phase2Distance: phase2_15_25?.$2,
    );

    final segmentMetricsFull25m = SegmentMetrics(
      time: duration0_25!.inMilliseconds / 1000.0,
      speed: speed0_25,
      strokeCount: numStrokes0_25 > 0 ? numStrokes0_25 : null,
      frequency: widget.strokeFrequency,
      strokeLength: strokeLength0_25,
      strokeIndex: si0_25,
      phase1Time: phase1_0_25?.$1,
      phase1Distance: phase1_0_25?.$2,
      phase2Time: phase2_0_25?.$1,
      phase2Distance: phase2_0_25?.$2,
    );

    // 3. Construct the main StrokeAnalysis object
    final newAnalysis = StrokeAnalysis(
      id: '',
      // Firestore will generate this
      title: title,
      createdAt: date,
      swimmerId: swimmerId,
      createdById: _currentUser.id,
      stroke: widget.stroke,
      intensity: widget.intensity,
      markedTimestamps: widget.markedTimestamps
          .map((key, value) => MapEntry(key.name, value.inMilliseconds)),
      strokeTimestamps:
          widget.strokeTimestamps.map((d) => d.inMilliseconds).toList(),
      strokeFrequency: widget.strokeFrequency,
      underwater: underwaterMetrics,
      segment0_15m: segmentMetrics0_15,
      segment15_25m: segmentMetrics15_25,
      segmentFull25m: segmentMetricsFull25m,
    );

    // 4. Get repository and save
    final analyzesRepository =
        Provider.of<StrokeAnalysisRepository>(context, listen: false);
    await analyzesRepository.addAnalysis(newAnalysis);
  }

  // --- Segment-Specific Calculations ---

  double? _getSegmentSpeed(Duration? start, Duration? end, double distance) {
    if (start == null || end == null) return null;
    final duration = end - start;
    if (duration.inMilliseconds <= 0) return null;
    return distance / (duration.inMilliseconds / 1000.0);
  }

  List<Duration> _getStrokesInSegment(Duration? start, Duration? end) {
    if (start == null || end == null) return [];
    return widget.strokeTimestamps
        .where((t) => t >= start && t <= end)
        .toList();
  }

  double? _calculateFrequency(List<Duration> strokes) {
    if (strokes.length < 2) return null;
    strokes.sort();
    final totalDuration = strokes.last - strokes.first;
    if (totalDuration.inMilliseconds <= 0) return null;

    if (widget.stroke == Stroke.breaststroke ||
        widget.stroke == Stroke.butterfly) {
      final cycles = (strokes.length - 1) / 2;
      return cycles / (totalDuration.inMilliseconds / 1000.0) * 60;
    } else {
      return (strokes.length - 1) /
          (totalDuration.inMilliseconds / 1000.0) *
          60;
    }
  }

  (double, double)? _getAveragePhaseMetricsForSegment({
    required bool isPhase1,
    required Duration? segmentStart,
    required Duration? segmentEnd,
    required double? segmentSpeed,
  }) {
    if (segmentSpeed == null || segmentStart == null || segmentEnd == null)
      return null;

    Duration totalDuration = Duration.zero;
    int count = 0;
    final startIndex = isPhase1 ? 0 : 1;
    if (widget.strokeTimestamps.length < (isPhase1 ? 2 : 3)) return null;

    for (int i = startIndex; i < widget.strokeTimestamps.length - 1; i += 2) {
      final tStart = widget.strokeTimestamps[i];
      final tEnd = widget.strokeTimestamps[i + 1];
      if (tStart >= segmentStart && tEnd <= segmentEnd) {
        totalDuration += tEnd - tStart;
        count++;
      }
    }

    if (count == 0) return null;
    final avgPhaseTime = (totalDuration.inMilliseconds / 1000.0) / count;
    final avgPhaseDistance = avgPhaseTime * segmentSpeed;
    return (avgPhaseTime, avgPhaseDistance);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _showSaveDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildCard(
            title: 'Swim Timeline',
            child: AnalysisTimelineChart(
              markedTimestamps: widget.markedTimestamps,
              strokeTimestamps: widget.strokeTimestamps,
              stroke: widget.stroke,
            ),
          ),
          _buildCard(
            title: 'Swim Details',
            details: [
              'Stroke: ${widget.stroke.name}',
              'Intensity: ${widget.intensity.name}',
            ],
          ),
          _buildUnderwaterCard(),
          _buildMetricsTable(context),
        ],
      ),
    );
  }

  void _showStrokeIndexInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('What is Stroke Index?'),
          content: const Text(
              'Stroke Index is a measure of swimming efficiency, calculated by multiplying Average Speed by Stroke Length.\n\nA higher value generally indicates better efficiency.'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildUnderwaterCard() {
    final pushOffTime =
        widget.markedTimestamps[StrokeEfficiencyEvent.pushOffWall];
    final breakoutTime =
        widget.markedTimestamps[StrokeEfficiencyEvent.breakout];
    final timeTo15m = widget.markedTimestamps[StrokeEfficiencyEvent.reached15m];

    double? breakoutDist;
    double? underwaterSpeed;
    Duration? timeToBreakout;

    if (pushOffTime != null && breakoutTime != null && timeTo15m != null) {
      final durationTo15m = timeTo15m - pushOffTime;
      if (durationTo15m.inMilliseconds > 0) {
        final avgSpeedTo15m = 15.0 / (durationTo15m.inMilliseconds / 1000.0);
        timeToBreakout = breakoutTime - pushOffTime;
        breakoutDist = avgSpeedTo15m * (timeToBreakout.inMilliseconds / 1000.0);
        if (timeToBreakout.inMilliseconds > 0) {
          underwaterSpeed =
              breakoutDist / (timeToBreakout.inMilliseconds / 1000.0);
        }
      }
    }

    return _buildCard(
      title: 'Underwater Analysis',
      details: [
        if (timeToBreakout != null)
          'Time to Breakout: ${(timeToBreakout.inMilliseconds / 1000.0).toStringAsFixed(2)}s',
        if (breakoutDist != null)
          'Breakout Distance: ${breakoutDist.toStringAsFixed(1)}m',
        if (underwaterSpeed != null)
          'Avg. Underwater Speed: ${underwaterSpeed.toStringAsFixed(2)} m/s',
      ],
    );
  }

  Widget _buildMetricsTable(BuildContext context) {
    final pushOffTime =
        widget.markedTimestamps[StrokeEfficiencyEvent.pushOffWall];
    final timeTo15m = widget.markedTimestamps[StrokeEfficiencyEvent.reached15m];
    final timeTo25m = widget.markedTimestamps[StrokeEfficiencyEvent.reached25m];
    final breakoutTime =
        widget.markedTimestamps[StrokeEfficiencyEvent.breakout];

    // --- Breakout Distance Calculation ---
    double? breakoutDist;
    if (pushOffTime != null && breakoutTime != null && timeTo15m != null) {
      final durationTo15m = timeTo15m - pushOffTime;
      if (durationTo15m.inMilliseconds > 0) {
        final avgSpeedTo15m = 15.0 / (durationTo15m.inMilliseconds / 1000.0);
        final durationToBreakout = breakoutTime - pushOffTime;
        breakoutDist =
            avgSpeedTo15m * (durationToBreakout.inMilliseconds / 1000.0);
      }
    }

    // --- Calculate all metrics ---
    // Durations
    final duration0_15 = (timeTo15m != null && pushOffTime != null)
        ? timeTo15m - pushOffTime
        : null;
    final duration15_25 =
        (timeTo25m != null && timeTo15m != null) ? timeTo25m - timeTo15m : null;
    final duration0_25 = (timeTo25m != null && pushOffTime != null)
        ? timeTo25m - pushOffTime
        : null;

    // Speeds
    final speed0_15 = _getSegmentSpeed(pushOffTime, timeTo15m, 15.0);
    final speed15_25 = _getSegmentSpeed(timeTo15m, timeTo25m, 10.0);
    final speed0_25 = _getSegmentSpeed(pushOffTime, timeTo25m, 25.0);

    // Strokes (taps)
    final taps0_15 = _getStrokesInSegment(pushOffTime, timeTo15m);
    final taps15_25 = _getStrokesInSegment(timeTo15m, timeTo25m);

    // Frequencies
    final freq0_15 = _calculateFrequency(taps0_15);
    final freq15_25 = _calculateFrequency(taps15_25);
    final freq0_25 = widget.strokeFrequency;

    // Stroke Length
    final isDoubleTap = widget.stroke == Stroke.breaststroke ||
        widget.stroke == Stroke.butterfly;
    final tapsAfterBreakout0_15 = (breakoutTime != null && timeTo15m != null)
        ? widget.strokeTimestamps
            .where((t) => t > breakoutTime && t <= timeTo15m)
            .toList()
        : <Duration>[];
    final tapsAfterBreakout15_25 = (timeTo15m != null && timeTo25m != null)
        ? widget.strokeTimestamps
            .where((t) => t > timeTo15m && t <= timeTo25m)
            .toList()
        : <Duration>[];
    final tapsAfterBreakout0_25 = (breakoutTime != null && timeTo25m != null)
        ? widget.strokeTimestamps
            .where((t) => t > breakoutTime && t <= timeTo25m)
            .toList()
        : <Duration>[];

    final numStrokes0_15 = isDoubleTap
        ? (tapsAfterBreakout0_15.length / 2).floor()
        : tapsAfterBreakout0_15.length;
    final numStrokes15_25 = isDoubleTap
        ? (tapsAfterBreakout15_25.length / 2).floor()
        : tapsAfterBreakout15_25.length;
    final numStrokes0_25 = isDoubleTap
        ? (tapsAfterBreakout0_25.length / 2).floor()
        : tapsAfterBreakout0_25.length;

    final strokeLength0_15 = (breakoutDist != null && numStrokes0_15 > 0)
        ? (15.0 - breakoutDist) / numStrokes0_15
        : null;
    final strokeLength15_25 =
        (numStrokes15_25 > 0) ? 10.0 / numStrokes15_25 : null;
    final strokeLength0_25 = (breakoutDist != null && numStrokes0_25 > 0)
        ? (25.0 - breakoutDist) / numStrokes0_25
        : null;

    // Stroke Index
    final si0_15 = (speed0_15 != null && strokeLength0_15 != null)
        ? speed0_15 * strokeLength0_15
        : null;
    final si15_25 = (speed15_25 != null && strokeLength15_25 != null)
        ? speed15_25 * strokeLength15_25
        : null;
    final si0_25 = (speed0_25 != null && strokeLength0_25 != null)
        ? speed0_25 * strokeLength0_25
        : null;

    // Phase Analysis
    final phase1Name =
        widget.stroke == Stroke.breaststroke ? "High-Glide" : "Back-Fwd";
    final phase2Name =
        widget.stroke == Stroke.breaststroke ? "Glide-High" : "Fwd-Back";

    final phase1_0_15 = _getAveragePhaseMetricsForSegment(
        isPhase1: true,
        segmentStart: pushOffTime,
        segmentEnd: timeTo15m,
        segmentSpeed: speed0_15);
    final phase2_0_15 = _getAveragePhaseMetricsForSegment(
        isPhase1: false,
        segmentStart: pushOffTime,
        segmentEnd: timeTo15m,
        segmentSpeed: speed0_15);

    final phase1_15_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: true,
        segmentStart: timeTo15m,
        segmentEnd: timeTo25m,
        segmentSpeed: speed15_25);
    final phase2_15_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: false,
        segmentStart: timeTo15m,
        segmentEnd: timeTo25m,
        segmentSpeed: speed15_25);

    final phase1_0_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: true,
        segmentStart: pushOffTime,
        segmentEnd: timeTo25m,
        segmentSpeed: speed0_25);
    final phase2_0_25 = _getAveragePhaseMetricsForSegment(
        isPhase1: false,
        segmentStart: pushOffTime,
        segmentEnd: timeTo25m,
        segmentSpeed: speed0_25);

    // --- Build helper ---
    DataRow _createDataRow(
        String title, String? val1, String? val2, String? val3,
        {VoidCallback? onTitleTap}) {
      Widget titleWidget =
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold));

      if (onTitleTap != null) {
        titleWidget = InkWell(
          onTap: onTitleTap,
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
            ],
          ),
        );
      }

      return DataRow(cells: [
        DataCell(titleWidget),
        DataCell(Text(val1 ?? '-')),
        DataCell(Text(val2 ?? '-')),
        DataCell(Text(val3 ?? '-')),
      ]);
    }

    DataRow _createHeaderRow(String title) {
      return DataRow(cells: [
        DataCell(Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))),
        DataCell(Text('')),
        DataCell(Text('')),
        DataCell(Text('')),
      ]);
    }

    return _buildCard(
      title: 'Surface Swim Analysis',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(
                label: Text('Metric',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('0-15m',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
            DataColumn(
                label: Text('15-25m',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
            DataColumn(
                label: Text('Full 25m',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true),
          ],
          rows: [
            _createDataRow(
              'Time (s)',
              duration0_15 != null
                  ? (duration0_15.inMilliseconds / 1000.0).toStringAsFixed(2)
                  : null,
              duration15_25 != null
                  ? (duration15_25.inMilliseconds / 1000.0).toStringAsFixed(2)
                  : null,
              duration0_25 != null
                  ? (duration0_25.inMilliseconds / 1000.0).toStringAsFixed(2)
                  : null,
            ),
            _createDataRow(
              'Avg Speed (m/s)',
              speed0_15?.toStringAsFixed(2),
              speed15_25?.toStringAsFixed(2),
              speed0_25?.toStringAsFixed(2),
            ),
            _createDataRow(
              'Stroke Count',
              numStrokes0_15 > 0 ? numStrokes0_15.toString() : null,
              numStrokes15_25 > 0 ? numStrokes15_25.toString() : null,
              numStrokes0_25 > 0 ? numStrokes0_25.toString() : null,
            ),
            _createDataRow(
              'Frequency (str/min)',
              freq0_15?.toStringAsFixed(1),
              freq15_25?.toStringAsFixed(1),
              freq0_25.toStringAsFixed(1),
            ),
            _createDataRow(
              'Stroke Length (m)',
              strokeLength0_15?.toStringAsFixed(2),
              strokeLength15_25?.toStringAsFixed(2),
              strokeLength0_25?.toStringAsFixed(2),
            ),
            _createDataRow(
              'Stroke Index',
              si0_15?.toStringAsFixed(2),
              si15_25?.toStringAsFixed(2),
              si0_25?.toStringAsFixed(2),
              onTitleTap: () => _showStrokeIndexInfo(context),
            ),
            if (isDoubleTap) _createHeaderRow('Phase Analysis'),
            if (isDoubleTap)
              _createDataRow(
                '$phase1Name Time (s)',
                phase1_0_15?.$1.toStringAsFixed(2),
                phase1_15_25?.$1.toStringAsFixed(2),
                phase1_0_25?.$1.toStringAsFixed(2),
              ),
            if (isDoubleTap)
              _createDataRow(
                '$phase1Name Dist. (m)',
                phase1_0_15?.$2.toStringAsFixed(2),
                phase1_15_25?.$2.toStringAsFixed(2),
                phase1_0_25?.$2.toStringAsFixed(2),
              ),
            if (isDoubleTap)
              _createDataRow(
                '$phase2Name Time (s)',
                phase2_0_15?.$1.toStringAsFixed(2),
                phase2_15_25?.$1.toStringAsFixed(2),
                phase2_0_25?.$1.toStringAsFixed(2),
              ),
            if (isDoubleTap)
              _createDataRow(
                '$phase2Name Dist. (m)',
                phase2_0_15?.$2.toStringAsFixed(2),
                phase2_15_25?.$2.toStringAsFixed(2),
                phase2_0_25?.$2.toStringAsFixed(2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
      {required String title, List<String>? details, Widget? child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (details != null && details.isNotEmpty || child != null)
              const SizedBox(height: 8),
            if (child != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: child,
              ),
            if (details != null)
              ...details.map((text) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(text, style: const TextStyle(fontSize: 16)),
                  )),
          ],
        ),
      ),
    );
  }
}

class AnalysisTimelineChart extends StatelessWidget {
  final Map<StrokeEfficiencyEvent, Duration> markedTimestamps;
  final List<Duration> strokeTimestamps;
  final Stroke stroke;

  const AnalysisTimelineChart({
    super.key,
    required this.markedTimestamps,
    required this.strokeTimestamps,
    required this.stroke,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.5,
      child: CustomPaint(
        painter: _TimelineChartPainter(
          markedTimestamps: markedTimestamps,
          strokeTimestamps: strokeTimestamps,
          stroke: stroke,
          eventLabelStyle:
              Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
          strokeColors: (
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary
          ),
          eventColor: Theme.of(context).colorScheme.error,
        ),
        child: Container(),
      ),
    );
  }
}

class _TimelineChartPainter extends CustomPainter {
  final Map<StrokeEfficiencyEvent, Duration> markedTimestamps;
  final List<Duration> strokeTimestamps;
  final Stroke stroke;
  final TextStyle eventLabelStyle;
  final (Color, Color) strokeColors;
  final Color eventColor;

  _TimelineChartPainter({
    required this.markedTimestamps,
    required this.strokeTimestamps,
    required this.stroke,
    required this.eventLabelStyle,
    required this.strokeColors,
    required this.eventColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final timelinePaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2.0;

    const double startX = 10;
    final double endX = size.width - 10;
    final double yPos = size.height / 1.5;

    final totalDuration = markedTimestamps[StrokeEfficiencyEvent.reached25m];
    if (totalDuration == null || totalDuration.inSeconds == 0) return;

    final pixelsPerSecond =
        (endX - startX) / totalDuration.inSeconds.toDouble();

    // Draw main timeline
    canvas.drawLine(Offset(startX, yPos), Offset(endX, yPos), timelinePaint);

    // Draw event markers
    markedTimestamps.forEach((event, duration) {
      final eventX =
          startX + (duration.inMilliseconds / 1000.0 * pixelsPerSecond);
      final eventPaint = Paint()
        ..color = eventColor
        ..strokeWidth = 2.0;
      canvas.drawLine(
          Offset(eventX, yPos - 15), Offset(eventX, yPos + 15), eventPaint);

      final textPainter = TextPainter(
        text: TextSpan(text: event.name, style: eventLabelStyle),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(eventX - textPainter.width / 2, yPos + 20));
    });

    // Draw stroke markers
    final strokePaint = Paint()..strokeWidth = 2.0;
    const double strokeMarkerHeight = 10;
    final isDoubleTapStroke =
        stroke == Stroke.breaststroke || stroke == Stroke.butterfly;

    for (int i = 0; i < strokeTimestamps.length; i++) {
      final duration = strokeTimestamps[i];
      final strokeX =
          startX + (duration.inMilliseconds / 1000.0 * pixelsPerSecond);

      Color strokeColor = strokeColors.$1;
      String? strokeLabel;

      if (isDoubleTapStroke) {
        if (i.isEven) {
          strokeColor = strokeColors.$1;
          strokeLabel = stroke == Stroke.breaststroke ? "High" : "Back";
        } else {
          strokeColor = strokeColors.$2;
          strokeLabel = stroke == Stroke.breaststroke ? "Glide" : "Forward";
        }
      }

      canvas.drawLine(Offset(strokeX, yPos - strokeMarkerHeight),
          Offset(strokeX, yPos), strokePaint..color = strokeColor);

      if (strokeLabel != null) {
        final strokeTextPainter = TextPainter(
          text: TextSpan(
              text: strokeLabel,
              style:
                  eventLabelStyle.copyWith(color: strokeColor, fontSize: 10)),
          textDirection: TextDirection.ltr,
        );
        strokeTextPainter.layout();
        strokeTextPainter.paint(
            canvas,
            Offset(strokeX - (strokeTextPainter.width / 2),
                yPos - strokeMarkerHeight - 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineChartPainter oldDelegate) => false;
}
