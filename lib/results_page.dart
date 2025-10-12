import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/race_data_analyzer.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class RaceResultsView extends StatefulWidget {
  final List<RaceSegment> recordedSegments;
  final List<IntervalAttributes> intervalAttributes;
  final Event event;

  const RaceResultsView({
    super.key,
    required this.recordedSegments,
    required this.intervalAttributes,
    required this.event,
  });

  @override
  State<RaceResultsView> createState() => _RaceResultsViewState();
}

class _RaceResultsViewState extends State<RaceResultsView> {
  late RaceDataAnalyzer raceDataAnalyzer;
  final _formKey = GlobalKey<FormState>();
  final _raceNameController = TextEditingController();
  final _raceDateController = TextEditingController();
  bool _showResults = false;

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
    raceDataAnalyzer = RaceDataAnalyzer(
        recordedSegments: widget.recordedSegments,
        event: widget.event,
        editableStrokeCounts: _editableStrokeCounts,
        poolLength: widget.event.poolLength);
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

    final startTime = widget.recordedSegments[0].splitTimeOfTotalRace;
    final List<AnalyzedSegment> analyzedSegments = [];

    for (int i = 0; i < widget.recordedSegments.length; i++) {
      final segment = widget.recordedSegments[i];
      final originalAttributes =
          i > 0 ? widget.intervalAttributes[i - 1] : null;
      final editableStrokeCount = i > 0 ? _editableStrokeCounts[i - 1] : 0.0;

      final totalTime = segment.splitTimeOfTotalRace - startTime;
      final splitTime = (i > 0)
          ? (segment.splitTimeOfTotalRace - widget.recordedSegments[i - 1].splitTimeOfTotalRace)
          : Duration.zero;

      analyzedSegments.add(
        AnalyzedSegment(
          sequence: i,
          checkPoint: segment.checkPoint.toString().split('.').last,
          distanceMeters: raceDataAnalyzer.getDistanceAsDouble(segment, i),
          totalTimeMillis: totalTime.inMilliseconds,
          splitTimeMillis: splitTime.inMilliseconds,
          dolphinKicks: originalAttributes?.dolphinKickCount,
          // Use the rounded editable stroke count for saving
          strokes: editableStrokeCount.round(),
          breaths: originalAttributes?.breathCount,
          // Use the precise double for calculation before saving
          strokeFrequency: raceDataAnalyzer.getStrokeFrequencyAsDouble(i),
          strokeLengthMeters: raceDataAnalyzer.getStrokeLengthAsDouble(i),
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
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;
    final hasRecordedData = widget.recordedSegments.isNotEmpty;
    final bool isSwimmer = _currentUser is Swimmer;
    final bool isCoach = _currentUser is Coach;

    // Helper widget for the initial input form (Step 1)
    Widget buildDetailsForm() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
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
              initialValue: _selectedSwimmerId,
              decoration: const InputDecoration(labelText: 'Swimmer'),
              items: _swimmers.map((user) {
                return DropdownMenuItem(
                  value: user.id,
                  child: Text(user.name),
                );
              }).toList(),
              onChanged: isSwimmer
                  ? null
                  : (value) => setState(() => _selectedSwimmerId = value),
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
                  : (value) => setState(() => _selectedCoachId = value),
              validator: (value) =>
                  value == null ? 'Please select a coach' : null,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  setState(() {
                    _showResults = true;
                  });
                }
              },
              child: const Text('View Results'),
            ),
          ]
        ],
      );
    }

    // Helper widget for displaying the results table (Step 2)
    Widget buildResultsView() {
      final swimmerName = _swimmers
          .firstWhere((s) => s.id == _selectedSwimmerId,
              orElse: () => Swimmer(id: '', name: 'N/A', email: ''))
          .name;
      final coachName = _coaches
          .firstWhere((c) => c.id == _selectedCoachId,
              orElse: () => Coach(id: '', name: 'N/A', email: ''))
          .name;
      final breakoutEstimate = raceDataAnalyzer.getBreakoutEstimate();
      final startTime =
          hasRecordedData ? widget.recordedSegments[0].splitTimeOfTotalRace : Duration.zero;

      final List<DataColumn> columns = [
        const DataColumn(label: Text('Distance')),
        const DataColumn(label: Text('Time')),
        if (!isBreaststroke) const DataColumn(label: Text('Dolphin Kicks')),
        const DataColumn(label: Text('Strokes')),
        if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
        const DataColumn(label: Text('Stroke Freq.')),
        const DataColumn(label: Text('Stroke Len.')),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_raceNameController.text,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Swimmer: $swimmerName'),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.support, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Coach: $coachName'),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.calendar_today,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Date: ${_raceDateController.text}'),
                  ]),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit Details'),
              onPressed: () => setState(() => _showResults = false),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: columns,
              rows: List<DataRow>.generate(
                widget.recordedSegments.length,
                (index) {
                  final segment = widget.recordedSegments[index];
                  final totalTime =
                      raceDataAnalyzer.formatDuration(segment.splitTimeOfTotalRace - startTime);
                  final splitTime = raceDataAnalyzer.getSplitTime(index);
                  final strokeFreq = raceDataAnalyzer.getStrokeFrequency(index);
                  final strokeLength = raceDataAnalyzer.getStrokeLength(index);

                  final attributes =
                      index > 0 ? widget.intervalAttributes[index - 1] : null;

                  final strokeCountText = index > 0
                      ? _editableStrokeCounts[index - 1].toStringAsFixed(
                          _editableStrokeCounts[index - 1].truncate() ==
                                  _editableStrokeCounts[index - 1]
                              ? 0
                              : 1)
                      : '';

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
                        onTap: index > 0
                            ? () => _editStrokeCount(index - 1)
                            : null,
                        child: Text(strokeCountText,
                            style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    if (!isBreaststroke)
                      DataCell(Text(attributes?.breathCount.toString() ?? '')),
                    DataCell(Text(strokeFreq)),
                    DataCell(Text(strokeLength)),
                  ]);
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
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.event.name} - Results'),
        actions: [
          if (hasRecordedData && _showResults)
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
                child: _showResults ? buildResultsView() : buildDetailsForm(),
              ),
            )
          : const Center(child: Text('No results to display.')),
    );
  }
}
