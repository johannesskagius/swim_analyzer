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
        // For a Swimmer, set them as the selected swimmer.
        swimmers = [currentUser];
        selectedSwimmerId = currentUser.id;
        selectedCoachId = currentUser.coachCreatorId;

        // Fetch their coach's profile for the dropdown.
        if (selectedCoachId != null) {
          // final coach = await userRepo.getUser(selectedCoachId); // Assumes userRepo.getUser(id) exists
          // if (coach is Coach) {
          //   coaches = [coach];
          // }
        }
      } else if (currentUser is Coach) {
        // For a Coach, set them as the selected coach and fetch their swimmers.
        coaches = [currentUser];
        selectedCoachId = currentUser.id;
        swimmers =
            await userRepo.getAllSwimmersFromCoach(coachId: currentUser.id);
      }
      // else {
      //   // Fallback for a generic user (e.g., admin) who can see everyone.
      //   final allUsers = await userRepo.getAllUsers();
      //   coaches = allUsers.whereType<Coach>().toList();
      //   swimmers = allUsers.whereType<Swimmer>().toList();
      // }

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
      final attributes = i > 0 ? widget.intervalAttributes[i - 1] : null;

      final totalTime = segment.time - startTime;
      final splitTime = (i > 0)
          ? (segment.time - widget.recordedSegments[i - 1].time)
          : Duration.zero;

      final strokeFreqStr = _getStrokeFrequency(i);
      final strokeLengthStr = _getStrokeLength(i);

      analyzedSegments.add(
        AnalyzedSegment(
          sequence: i,
          checkPoint: segment.checkPoint.toString().split('.').last,
          distanceMeters: _getDistanceAsDouble(segment, i),
          totalTimeMillis: totalTime.inMilliseconds,
          splitTimeMillis: splitTime.inMilliseconds,
          dolphinKicks: attributes?.dolphinKickCount,
          strokes: attributes?.strokeCount,
          breaths: attributes?.breathCount,
          strokeFrequency:
              strokeFreqStr == '-' ? null : double.tryParse(strokeFreqStr),
          strokeLengthMeters: strokeLengthStr == '-'
              ? null
              : double.tryParse(strokeLengthStr.replaceAll('m', '')),
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
                        value: _selectedCoachId,
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
                                DataCell(Text(
                                    attributes?.strokeCount.toString() ?? '')),
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

    if (segment.checkPoint == CheckPoint.start) return 0.0;
    if (segment.checkPoint == CheckPoint.finish)
      return widget.event.distance.toDouble();

    if (segment.checkPoint == CheckPoint.fifteenMeterMark) {
      // A 15m mark happens after a start or a turn.
      // The number of turns *before* this point determines the base distance.
      final previousTurnCount = widget.recordedSegments
          .sublist(0, index)
          .where((s) => s.checkPoint == CheckPoint.turn)
          .length;
      return (previousTurnCount * poolLengthValue) + 15.0;
    }

    if (segment.checkPoint == CheckPoint.turn) {
      // For a 'turn' checkpoint, we count the turn itself to get the distance at the wall.
      final turnCount = widget.recordedSegments
          .sublist(0, index + 1)
          .where((s) => s.checkPoint == CheckPoint.turn)
          .length;
      return (turnCount * poolLengthValue).toDouble();
    }

    // Fallback for any other checkpoint types.
    return 0.0;
  }

  String _getDistance(RaceSegment segment, int index) {
    final dist = _getDistanceAsDouble(segment, index);
    if (dist == 0 && segment.checkPoint != CheckPoint.start) {
      return segment.checkPoint.toString().split('.').last;
    }
    return '${dist.toInt()}m';
  }

  String _getStrokeFrequency(int index) {
    if (index == 0) return '-';
    final attributes = widget.intervalAttributes[index - 1];
    if (attributes.strokeCount == 0) return '-';
    final splitTime = (widget.recordedSegments[index].time -
            widget.recordedSegments[index - 1].time)
        .inMilliseconds;
    if (splitTime == 0) return '-';
    final freq = attributes.strokeCount / (splitTime / 1000 / 60);
    return freq.toStringAsFixed(1);
  }

  String _getStrokeLength(int index) {
    if (index == 0) return '-';
    final attributes = widget.intervalAttributes[index - 1];
    if (attributes.strokeCount == 0) return '-';

    final prevDist =
        _getDistanceAsDouble(widget.recordedSegments[index - 1], index - 1);
    final currentDist =
        _getDistanceAsDouble(widget.recordedSegments[index], index);
    final distanceCovered = currentDist - prevDist;
    if (distanceCovered <= 0) return '-';

    final length = distanceCovered / attributes.strokeCount;
    return '${length.toStringAsFixed(2)}m';
  }

  String? _getBreakoutEstimate() {
    final breakOutSegment = widget.recordedSegments
        .where((s) => s.checkPoint == CheckPoint.breakOut)
        .firstOrNull;
    if (breakOutSegment == null) return null;
    final offBlockSegment = widget.recordedSegments
        .where((s) => s.checkPoint == CheckPoint.offTheBlock)
        .firstOrNull;
    if (offBlockSegment == null) return null;

    final timeToBreakout = breakOutSegment.time - offBlockSegment.time;
    final distance = timeToBreakout.inMilliseconds / 1000 * 1.5;
    return '* Breakout distance estimate: ${distance.toStringAsFixed(1)}m';
  }
}
