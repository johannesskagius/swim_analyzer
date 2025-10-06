import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class ResultsPage extends StatefulWidget {
  final List<RaceSegment> recordedSegments;
  final List<IntervalAttributes> intervalAttributes;
  final Event event;

  const ResultsPage({
    super.key,
    required this.recordedSegments,
    required this.intervalAttributes,
    required this.event,
  });

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  final _formKey = GlobalKey<FormState>();
  final _raceNameController = TextEditingController();
  final _raceDateController = TextEditingController();

  // Editable state for stroke counts
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
    // Initialize editable stroke counts from the widget's data
    _editableStrokeCounts = widget.intervalAttributes
        .map((attr) => attr.strokeCount.toDouble())
        .toList();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final userRepo = Provider.of<UserRepository>(context, listen: false);
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser == null) {
        throw Exception("No user logged in");
      }

      final currentUser = await userRepo.getMyProfile();
      if (currentUser == null) {
        throw Exception("Could not retrieve user profile.");
      }

      List<AppUser> swimmers = [];
      List<AppUser> coaches = [];
      String? selectedSwimmerId;
      String? selectedCoachId;

      if (currentUser is Swimmer) {
        swimmers = [currentUser];
        selectedSwimmerId = currentUser.id;
        selectedCoachId = currentUser.coachCreatorId;
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
      }
    }
  }

  Future<void> _saveRaceToFirestore(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (widget.recordedSegments.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No data to save.')));
      return;
    }

    final startTime = widget.recordedSegments[0].time;
    final List<AnalyzedSegment> analyzedSegments = [];

    for (int i = 0; i < widget.recordedSegments.length; i++) {
      final segment = widget.recordedSegments[i];
      final originalAttributes = i > 0 ? widget.intervalAttributes[i - 1] : null;
      final editableStrokeCount = i > 0 ? _editableStrokeCounts[i - 1] : 0.0;

      final totalTime = segment.time - startTime;
      final splitTime = (i > 0)
          ? (segment.time - widget.recordedSegments[i - 1].time)
          : Duration.zero;

      analyzedSegments.add(
        AnalyzedSegment(
          sequence: i,
          checkPoint: segment.checkPoint.toString().split('.').last,
          distanceMeters: _getDistanceAsDouble(segment, i),
          totalTimeMillis: totalTime.inMilliseconds,
          splitTimeMillis: splitTime.inMilliseconds,
          dolphinKicks: originalAttributes?.dolphinKickCount,
          // Use the rounded editable stroke count for saving
          strokes: editableStrokeCount.round(),
          breaths: originalAttributes?.breathCount,
          // Use the precise double for calculation before saving
          strokeFrequency: _getStrokeFrequencyAsDouble(i),
          strokeLengthMeters: _getStrokeLengthAsDouble(i),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Race analysis saved successfully!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving race: $e')));
    }
  }
  
  void _editStrokeCount(int attributeIndex) {
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
                    onPressed: () => setDialogState(() =>
                        tempValue = (tempValue - 0.5).clamp(0.0, 50.0)),
                  ),
                  Text(tempValue.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.headlineSmall),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setDialogState(() =>
                        tempValue = (tempValue + 0.5).clamp(0.0, 50.0)),
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


  @override
  Widget build(BuildContext context) {
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;
    final hasRecordedData = widget.recordedSegments.isNotEmpty;
    final bool isSwimmer = _currentUser is Swimmer;
    final bool isCoach = _currentUser is Coach;

    final List<DataColumn> columns = [
      const DataColumn(label: Text('Distance')),
      const DataColumn(label: Text('Time')),
      if (!isBreaststroke) const DataColumn(label: Text('Dolphin Kicks')),
      const DataColumn(label: Text('Strokes')),
      if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
      const DataColumn(label: Text('Stroke Freq.')),
      const DataColumn(label: Text('Stroke Len.')),
    ];

    final breakoutEstimate = _getBreakoutEstimate();
    final startTime =
        hasRecordedData ? widget.recordedSegments[0].time : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.event.name} - Results'),
        actions: [
          if (hasRecordedData)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () => _saveRaceToFirestore(context),
            ),
        ],
      ),
      body: hasRecordedData
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            _raceDateController.text =
                                DateFormat('yyyy-MM-dd').format(pickedDate);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedSwimmerId,
                        decoration: const InputDecoration(labelText: 'Swimmer'),
                        items: _swimmers.map((user) {
                          return DropdownMenuItem(
                            value: user.id,
                            child: Text(user.name),
                          );
                        }).toList(),
                        onChanged: isSwimmer
                            ? null
                            : (value) =>
                                setState(() => _selectedSwimmerId = value),
                        validator: (value) =>
                            value == null ? 'Please select a swimmer' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCoachId,
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
                                setState(() => _selectedCoachId = value),
                        validator: (value) =>
                            value == null ? 'Please select a coach' : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: columns,
                        rows: List<DataRow>.generate(
                          widget.recordedSegments.length,
                          (index) {
                            final segment = widget.recordedSegments[index];
                            final totalTime =
                                _formatDuration(segment.time - startTime);
                            final splitTime = _getSplitTime(index);
                            final strokeFreq = _getStrokeFrequency(index);
                            final strokeLength = _getStrokeLength(index);

                            final attributes = index > 0
                                ? widget.intervalAttributes[index - 1]
                                : null;
                            
                            final strokeCountText = index > 0
                                ? _editableStrokeCounts[index - 1]
                                    .toStringAsFixed(
                                        _editableStrokeCounts[index-1].truncate() == _editableStrokeCounts[index-1] ? 0 : 1
                                    )
                                : '';


                            return DataRow(
                              cells: <DataCell>[
                                DataCell(Text(_getDistance(segment, index))),
                                DataCell(
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(totalTime,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        Text(splitTime,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color:
                                                        Colors.grey.shade700)),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!isBreaststroke)
                                  DataCell(Text(
                                      attributes?.dolphinKickCount.toString() ??
                                          '')),
                                DataCell(
                                  InkWell(
                                    onTap: index > 0 ? () => _editStrokeCount(index -1) : null,
                                    child: Text(strokeCountText, style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                if (!isBreaststroke)
                                  DataCell(Text(
                                      attributes?.breathCount.toString() ??
                                          '')),
                                DataCell(Text(strokeFreq)),
                                DataCell(Text(strokeLength)),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    if (breakoutEstimate != null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(breakoutEstimate),
                      ),
                  ],
                ),
              ),
            )
          : const Center(child: Text('No results to display.')),
    );
  }

  String _formatDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2)}';
  }

  String _getSplitTime(int index) {
    if (index == 0) return '-';
    final split = widget.recordedSegments[index].time -
        widget.recordedSegments[index - 1].time;
    return '+${_formatDuration(split)}';
  }

  double _getDistanceAsDouble(RaceSegment segment, int index) {
    final int poolLengthValue = widget.event.poolLength.distance;

    switch (segment.checkPoint) {
      case CheckPoint.start:
        return 0.0;
      case CheckPoint.finish:
        return widget.event.distance.toDouble();
      case CheckPoint.turn:
        final turnCount = widget.recordedSegments
            .sublist(0, index + 1)
            .where((s) => s.checkPoint == CheckPoint.turn)
            .length;
        return (turnCount * poolLengthValue).toDouble();
      case CheckPoint.fifteenMeterMark:
        final previousTurnCount = widget.recordedSegments
            .sublist(0, index)
            .where((s) => s.checkPoint == CheckPoint.turn)
            .length;
        return (previousTurnCount * poolLengthValue) + 15.0;
      case CheckPoint.breakOut:
      // Find the distance of the last wall (start or turn) before this breakout
        final lapStartIndex = widget.recordedSegments.lastIndexWhere(
              (s) => s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn,
          index - 1,
        );
        if (lapStartIndex == -1) return 0.0; // Should not happen in a valid race

        final lastWallDistance = _getDistanceAsDouble(widget.recordedSegments[lapStartIndex], lapStartIndex);

        // Calculate the breakout distance for this specific lap (distance from the wall)
        final breakoutDistFromWall = _getBreakoutDistanceForLap(index);

        // The cumulative distance is the wall's distance + the breakout distance
        return lastWallDistance + (breakoutDistFromWall ?? 0.0);
      default:
      // Handles any other unexpected checkpoint types
        return 0.0;
    }
  }

  String _getDistance(RaceSegment segment, int index) {
    // For breakout rows, display the calculated breakout distance from the wall.
    if (segment.checkPoint == CheckPoint.breakOut) {
      final breakoutDist = _getBreakoutDistanceForLap(index);
      // Prefix with '*' to indicate it's a special, non-cumulative value.
      return '*${breakoutDist?.toStringAsFixed(1) ?? 'N/A'}m';
    }

    final dist = _getDistanceAsDouble(segment, index);
    if (dist == 0 && segment.checkPoint != CheckPoint.start) {
      return segment.checkPoint.toString().split('.').last;
    }
    return '${dist.toInt()}m';
  }

  double? _getStrokeFrequencyAsDouble(int index) {
    if (index == 0) return null;
    final strokeCount = _editableStrokeCounts[index - 1];
    if (strokeCount == 0) return null;
    final splitTime = (widget.recordedSegments[index].time -
        widget.recordedSegments[index - 1].time)
        .inMilliseconds;
    if (splitTime == 0) return null;
    return strokeCount / (splitTime / 1000 / 60);
  }

  String _getStrokeFrequency(int index) {
    final freq = _getStrokeFrequencyAsDouble(index);
    return freq?.toStringAsFixed(1) ?? '-';
  }

  double? _getBreakoutDistanceForLap(int segmentIndex) {
    final currentSegment = widget.recordedSegments[segmentIndex];
    if (currentSegment.checkPoint != CheckPoint.breakOut) return null;

    final lapStartIndex = widget.recordedSegments.lastIndexWhere(
      (s) => s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn,
      segmentIndex - 1,
    );

    if (lapStartIndex == -1) return null;

    final lapStartSegment = widget.recordedSegments[lapStartIndex];
    final timeToBreakout = currentSegment.time - lapStartSegment.time;
    if (timeToBreakout <= Duration.zero) return null;

    // Find 15m mark for this specific lap to calculate speed
    final nextTurnIndex = widget.recordedSegments.indexWhere(
      (s) => s.checkPoint == CheckPoint.turn || s.checkPoint == CheckPoint.finish,
      lapStartIndex + 1,
    );
    
    final endOfLapIndex = nextTurnIndex == -1 ? widget.recordedSegments.length : nextTurnIndex + 1;

    final fifteenMeterMarkIndex = widget.recordedSegments.sublist(lapStartIndex, endOfLapIndex).indexWhere(
      (s) => s.checkPoint == CheckPoint.fifteenMeterMark,
    );

    double avgUnderwaterSpeed = 2.0; // Fallback speed

    if (fifteenMeterMarkIndex != -1) {
      final fifteenMeterSegment = widget.recordedSegments[lapStartIndex + fifteenMeterMarkIndex];
      final timeTo15m = fifteenMeterSegment.time - lapStartSegment.time;
      if (timeTo15m > Duration.zero) {
        avgUnderwaterSpeed = 15.0 / (timeTo15m.inMilliseconds / 1000.0);
      }
    }
    
    return avgUnderwaterSpeed * (timeToBreakout.inMilliseconds / 1000.0);
  }


  double? _getStrokeLengthAsDouble(int index) {
    if (index == 0) return null;
    final strokeCount = _editableStrokeCounts[index - 1];
    if (strokeCount <= 0) return null;

    // Get the correct cumulative distance for the previous and current points.
    // The new _getDistanceAsDouble now correctly calculates the distance for ALL checkpoints.
    final prevDist = _getDistanceAsDouble(widget.recordedSegments[index - 1], index - 1);
    final currentDist = _getDistanceAsDouble(widget.recordedSegments[index], index);

    final distanceCovered = currentDist - prevDist;

    if (distanceCovered <= 0) return null;

    // The logic is now simple and correct for all segments because the
    // distance calculation itself is correct.
    return distanceCovered / strokeCount;
  }

  String _getStrokeLength(int index) {
    final length = _getStrokeLengthAsDouble(index);
    return length != null ? '${length.toStringAsFixed(2)}m' : '-';
  }

  String? _getBreakoutEstimate() {
    final breakOutSegment = widget.recordedSegments
        .where((s) => s.checkPoint == CheckPoint.breakOut)
        .firstOrNull;
    if (breakOutSegment == null) return null;
    
    final breakoutIndex = widget.recordedSegments.indexOf(breakOutSegment);
    final distance = _getBreakoutDistanceForLap(breakoutIndex);

    if (distance == null) return null;

    return '* Breakout distance estimate: ${distance.toStringAsFixed(1)}m';
  }
}
