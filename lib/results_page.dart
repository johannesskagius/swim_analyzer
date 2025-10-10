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
    _raceNameController.text = widget.event.name;
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

      final AppUser? currentUser = await userRepo.getMyProfile();

      List<AppUser> swimmers = [];
      List<AppUser> coaches = [];
      String? selectedSwimmerId;
      String? selectedCoachId;

      if (currentUser is Swimmer) {
        swimmers = [currentUser];
        selectedSwimmerId = currentUser.id;
        // Attempt to pre-fill coach if available
        if (currentUser.coachCreatorId != null &&
            currentUser.coachCreatorId!.isNotEmpty) {
          try {
            final coach =
                await userRepo.getUserDocument(currentUser.coachCreatorId!);
            if (coach != null) {
              coaches = [coach];
              selectedCoachId = coach.id;
            }
          } catch (e) {
            debugPrint("Could not pre-load coach: $e");
          }
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
      }
    }
  }

  Future<void> _showSaveDialog() async {
    final bool isSwimmer = _currentUser is Swimmer;
    final bool isCoach = _currentUser is Coach;

    return showDialog<void>(
      context: context,
      // Use a StatefulBuilder to manage the dialog's own state for dropdowns
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Save Race Analysis'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextFormField(
                      controller: _raceNameController,
                      decoration: const InputDecoration(labelText: 'Race Name'),
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
                          context: dialogContext,
                          initialDate: DateFormat('yyyy-MM-dd')
                              .parse(_raceDateController.text),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (pickedDate != null) {
                          // No need for setState here as controller is updated directly
                          _raceDateController.text =
                              DateFormat('yyyy-MM-dd').format(pickedDate);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_swimmers.isNotEmpty)
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
                            ? null // Disable if the user is a swimmer
                            : (value) => setDialogState(
                                () => _selectedSwimmerId = value),
                        validator: (value) =>
                            value == null ? 'Please select a swimmer' : null,
                      ),
                    const SizedBox(height: 16),
                    if (_coaches.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: _selectedCoachId,
                        decoration: const InputDecoration(labelText: 'Coach'),
                        items: _coaches.map((user) {
                          return DropdownMenuItem(
                            value: user.id,
                            child: Text(user.name),
                          );
                        }).toList(),
                        onChanged: isSwimmer || isCoach
                            ? null // Disable if user is swimmer or coach
                            : (value) => setDialogState(
                                () => _selectedCoachId = value),
                        validator: (value) =>
                            value == null ? 'Please select a coach' : null,
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              ElevatedButton(
                child: const Text('Save'),
                onPressed: () => _saveRaceToFirestore(dialogContext),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _saveRaceToFirestore(BuildContext dialogContext) async {
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
      final originalAttributes =
          i > 0 ? widget.intervalAttributes[i - 1] : null;
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
          strokes: editableStrokeCount.round(),
          breaths: originalAttributes?.breathCount,
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Race analysis saved successfully!')),
      );
      Navigator.of(dialogContext).pop(); // Close the dialog
      Navigator.of(context).pop(); // Close the results page
    } catch (e) {
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _showSaveDialog,
            tooltip: 'Save Race',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : buildResultsView(),
    );
  }

  Widget buildResultsView() {
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;
    final hasRecordedData = widget.recordedSegments.isNotEmpty;
    final swimmerName = _swimmers
        .firstWhere((s) => s.id == _selectedSwimmerId, orElse: () => Swimmer(id: '', name: 'N/A', email: ''))
        .name;
    final coachName = _coaches
        .firstWhere((c) => c.id == _selectedCoachId, orElse: () => Coach(id: '', name: 'N/A', email: ''))
        .name;
    final breakoutEstimate = _getBreakoutEstimate();
    final startTime =
        hasRecordedData ? widget.recordedSegments[0].time : Duration.zero;

    final List<DataColumn> columns = [
      const DataColumn(label: Text('Dist.')),
      const DataColumn(label: Text('Time')),
      if (!isBreaststroke) const DataColumn(label: Text('Kicks')),
      const DataColumn(label: Text('Strokes')),
      if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
      const DataColumn(label: Text('Freq.')),
      const DataColumn(label: Text('Len.')),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 8.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pool, size: 16),
                        const SizedBox(width: 8),
                        Text('Swimmer: $swimmerName',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.ac_unit_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text('Coach: $coachName',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    if (breakoutEstimate != null) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.waves, size: 16),
                          const SizedBox(width: 8),
                          Text(
                              'Avg. Breakout: ${breakoutEstimate.toStringAsFixed(1)}m'),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
            ),
            DataTable(
              columns: columns,
              rows: List.generate(
                widget.recordedSegments.length,
                (index) {
                  final segment = widget.recordedSegments[index];
                  final isTurnOrFinish =
                      segment.checkPoint == CheckPoint.turn ||
                          segment.checkPoint == CheckPoint.finish;
                  final attributeIndex = isTurnOrFinish ? index - 1 : -1;
                  final originalAttributes = attributeIndex != -1
                      ? widget.intervalAttributes[attributeIndex]
                      : null;
                  final editableStrokeCount = attributeIndex != -1
                      ? _editableStrokeCounts[attributeIndex]
                      : 0.0;

                  return DataRow(
                    cells: [
                      DataCell(
                          Text('${_getDistanceAsString(segment, index)}m')),
                      DataCell(Text(_formatDuration(segment.time - startTime))),
                      if (!isBreaststroke)
                        DataCell(Text(originalAttributes?.dolphinKickCount
                                .toString() ??
                            '-')),
                      DataCell(
                        Row(
                          children: [
                            Text(editableStrokeCount.round().toString()),
                            if (attributeIndex != -1)
                              IconButton(
                                icon: const Icon(Icons.edit, size: 16),
                                onPressed: () => _editStrokeCount(attributeIndex),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      ),
                      if (!isBreaststroke)
                        DataCell(
                            Text(originalAttributes?.breathCount.toString() ??
                                '-')), // Default to '-' if null
                      DataCell(Text(_getStrokeFrequencyAsString(index))),
                      DataCell(Text(_getStrokeLengthAsString(index))),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods to calculate and format results data
  String _formatDuration(Duration d) {
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0')}';
  }

  String _getDistanceAsString(RaceSegment segment, int index) {
    if (segment.checkPoint == CheckPoint.breakOut) {
      final prevDist =
          index > 0 ? _getDistanceAsDouble(widget.recordedSegments[index - 1], index - 1) : 0.0;
      return _getDistanceAsDouble(segment, index).toStringAsFixed(1);
    }
    return _getDistanceAsDouble(segment, index).toInt().toString();
  }

  double _getDistanceAsDouble(RaceSegment segment, int index) {
    final poolLength = widget.event.poolLength;
    if (segment.checkPoint == CheckPoint.breakOut) {
      final turnIndex = widget.recordedSegments
          .sublist(0, index)
          .lastIndexWhere((s) => s.checkPoint == CheckPoint.turn);
      final startIndex = widget.recordedSegments
          .sublist(0, index)
          .lastIndexWhere((s) => s.checkPoint == CheckPoint.start);
      final lastWallIndex = turnIndex > startIndex ? turnIndex : startIndex;
      final wallTime = widget.recordedSegments[lastWallIndex].time;
      final breakoutTime = segment.time;
      final timeDiff =
          (breakoutTime - wallTime).inMilliseconds / 1000.0; // in seconds
      // Rough speed estimate: Assume swimmer's avg speed on that length
      final nextWallIndex = widget.recordedSegments
          .indexWhere((s) => (s.checkPoint == CheckPoint.turn || s.checkPoint == CheckPoint.finish) && s.time > wallTime);
      final wallDist = (lastWallIndex == 0) ? 0.0 : (lastWallIndex / 2).ceil() * poolLength.distance.toDouble();

      if(nextWallIndex != -1) {
         final nextWallTime = widget.recordedSegments[nextWallIndex].time;
         final lapTime = (nextWallTime - wallTime).inMilliseconds / 1000.0;
         if(lapTime > 0) {
           final avgSpeed = poolLength.distance / lapTime;
           return wallDist + (timeDiff * avgSpeed);
         }
      }
      return wallDist + 5; // fallback
    } else {
      final turnCount = segment.checkPoint == CheckPoint.start
          ? 0
          : widget.recordedSegments
              .sublist(0, index + 1)
              .where((s) => s.checkPoint == CheckPoint.turn)
              .length +
              1;
      return turnCount * poolLength.distance.toDouble();
    }
  }

  String _getStrokeFrequencyAsString(int segmentIndex) {
    final freq = _getStrokeFrequencyAsDouble(segmentIndex);
    return freq != null ? freq.toStringAsFixed(1) : '-';
  }

  double? _getStrokeFrequencyAsDouble(int segmentIndex) {
    if (segmentIndex == 0) return null;
    final isTurnOrFinish = widget.recordedSegments[segmentIndex].checkPoint == CheckPoint.turn ||
        widget.recordedSegments[segmentIndex].checkPoint == CheckPoint.finish;
    if (!isTurnOrFinish) return null;

    final attributeIndex = segmentIndex - 1;
    final strokeCount = _editableStrokeCounts[attributeIndex];
    if (strokeCount <= 0) return null;

    final prevSegment = widget.recordedSegments[segmentIndex - 1];
    final timeDiff = (widget.recordedSegments[segmentIndex].time - prevSegment.time)
        .inMilliseconds / 1000.0;
    if (timeDiff <= 0) return null;

    return (strokeCount / timeDiff) * 60; // strokes per minute
  }

  String _getStrokeLengthAsString(int segmentIndex) {
    final length = _getStrokeLengthAsDouble(segmentIndex);
    return length != null ? length.toStringAsFixed(2) : '-';
  }

  double? _getStrokeLengthAsDouble(int segmentIndex) {
    if (segmentIndex == 0) return null;
    final isTurnOrFinish = widget.recordedSegments[segmentIndex].checkPoint == CheckPoint.turn ||
        widget.recordedSegments[segmentIndex].checkPoint == CheckPoint.finish;
    if (!isTurnOrFinish) return null;

    final attributeIndex = segmentIndex - 1;
    final strokeCount = _editableStrokeCounts[attributeIndex];
    if (strokeCount <= 0) return null;

    final distance = widget.event.poolLength.distance.toDouble();
    return distance / strokeCount;
  }

  double? _getBreakoutEstimate() {
    final breakoutSegments = widget.recordedSegments.where((s) => s.checkPoint == CheckPoint.breakOut).toList();
    if(breakoutSegments.isEmpty) return null;

    List<double> breakoutDistances = [];
    for(final segment in breakoutSegments) {
      final index = widget.recordedSegments.indexOf(segment);
      final dist = _getDistanceAsDouble(segment, index);
      final prevWallIndex = widget.recordedSegments.sublist(0, index).lastIndexWhere((s) => s.checkPoint == CheckPoint.start || s.checkPoint == CheckPoint.turn);
      final prevWallDist = _getDistanceAsDouble(widget.recordedSegments[prevWallIndex], prevWallIndex);
      breakoutDistances.add(dist - prevWallDist);
    }

    return breakoutDistances.first;
  }
}
