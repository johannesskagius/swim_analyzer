import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/race_data_analyzer.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import 'add_swimmer.dart';

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
  // REFACTOR: This key is now used inside the save dialog.
  final _saveFormKey = GlobalKey<FormState>();
  final _raceNameController = TextEditingController();
  final _raceDateController = TextEditingController();

  // REFACTOR: No longer need _showResults flag, view defaults to showing results.

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
    // Pre-load user data so it's ready for the save dialog.
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
        // Attempt to pre-select the swimmer's coach
        final coach = await userRepo.getUserDocument(currentUser.creatorId ?? '');
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load user data: $e')));
      }
    }
  }

  Future<void> _saveRaceToFirestore(BuildContext context) async {
    // Validation is now handled inside the dialog before this is called.
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
          ? (segment.splitTimeOfTotalRace -
          widget.recordedSegments[i - 1].splitTimeOfTotalRace)
          : Duration.zero;

      analyzedSegments.add(
        AnalyzedSegment(
          sequence: i,
          checkPoint: segment.checkPoint.toString().split('.').last,
          distanceMeters: raceDataAnalyzer.getDistanceAsDouble(segment, i),
          totalTimeMillis: totalTime.inMilliseconds,
          splitTimeMillis: splitTime.inMilliseconds,
          dolphinKicks: originalAttributes?.dolphinKickCount,
          strokes: editableStrokeCount.round(),
          breaths: originalAttributes?.breathCount,
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
      // Pop twice: once for the dialog, once to exit the results page.
      Navigator.of(context).pop();
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

  Future<void> _showSaveDialog() async {
    final bool isSwimmer = _currentUser is Swimmer;
    final bool isCoach = _currentUser is Coach;

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must interact with the dialog.
      builder: (BuildContext dialogContext) {
        // Use local variables to manage state within the dialog
        String? dialogSwimmerId = _selectedSwimmerId;
        String? dialogCoachId = _selectedCoachId;

        // Wrap with StatefulBuilder to manage the dialog's own state
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
                              // Use the dialog's setState to update the UI
                              setDialogState(() {
                                _raceDateController.text =
                                    DateFormat('yyyy-MM-dd')
                                        .format(pickedDate);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        // --- "Add Swimmer" Feature ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: dialogSwimmerId,
                                decoration: const InputDecoration(
                                    labelText: 'Swimmer'),
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
                                padding:
                                const EdgeInsets.only(left: 8.0, bottom: 4.0),
                                child: IconButton(
                                  icon: const Icon(Icons.add),
                                  tooltip: 'Add New Swimmer',
                                  onPressed: () async {
                                    // You would navigate to your 'AddSwimmerPage' here
                                    final newSwimmerAdded = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddSwimmerPage(coach: _currentUser as Coach))); //Verified in isCoach

                                    // For now, we'll just log it.
                                    // After the page returns, you would refresh the data.
                                    print("Navigate to Add Swimmer page...");

                                    // Example of how you would refresh the list:
                                    if (newSwimmerAdded == true) {
                                      await _loadInitialData(); // Reload all user data
                                      setDialogState((){}); // Rebuild the dialog with the new list
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: dialogCoachId,
                          decoration:
                          const InputDecoration(labelText: 'Coach'),
                          items: _coaches.map((user) {
                            return DropdownMenuItem(
                              value: user.id,
                              child: Text(user.name),
                            );
                          }).toList(),
                          onChanged: (isSwimmer || isCoach)
                              ? null
                              : (value) => setDialogState(
                                  () => dialogCoachId = value),
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
                      // Update the main page's state with the final selections
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
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;
    final hasRecordedData = widget.recordedSegments.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.event.name} - Results'),
        actions: [
          // REFACTOR: Save button now shows the dialog.
          if (hasRecordedData)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _showSaveDialog,
              tooltip: 'Save Race Analysis',
            ),
        ],
      ),
      // REFACTOR: Body now directly builds the results view.
      body: hasRecordedData
          ? buildResultsView()
          : const Center(child: Text('No results to display.')),
    );
  }

  // Helper widget for displaying the results table.
  Widget buildResultsView() {
    final breakoutEstimate = raceDataAnalyzer.getBreakoutEstimate();
    final startTime = widget.recordedSegments.isNotEmpty
        ? widget.recordedSegments[0].splitTimeOfTotalRace
        : Duration.zero;
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;

    final List<DataColumn> columns = [
      const DataColumn(label: Text('Split')),
      const DataColumn(label: Text('Time')),
      if (!isBreaststroke) const DataColumn(label: Text('Kicks')),
      const DataColumn(label: Text('Strokes')),
      if (!isBreaststroke) const DataColumn(label: Text('Breaths')),
      const DataColumn(label: Text('Freq')),
      const DataColumn(label: Text('Length')),
    ];

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
                        onTap: index > 0 && index - 1 < _editableStrokeCounts.length
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
      ),
    );
  }
}
