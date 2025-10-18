import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis_repository.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import '../analysis/stroke/stroke_analyze_result_view.dart';
import '../analysis/stroke/stroke_efficiency_event.dart';

class StrokeHistoryPage extends StatefulWidget {
  final AppUser appUser;

  const StrokeHistoryPage({super.key, required this.appUser});

  @override
  State<StrokeHistoryPage> createState() => _StrokeHistoryPageState();
}

class _StrokeHistoryPageState extends State<StrokeHistoryPage> {
  // The stream of analyses for the _selectedSwimmer.
  late Stream<List<StrokeAnalysis>> _analysesStream;
  // The swimmer whose analyses are currently being displayed.
  late AppUser _selectedSwimmer;
  // Future for fetching the list of swimmers if the user is a coach.
  Future<List<AppUser>>? _swimmersFuture;

  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      // Default to showing the logged-in user's analyses first.
      _selectedSwimmer = widget.appUser;

      final analyzesRepository =
      Provider.of<StrokeAnalysisRepository>(context, listen: false);
      _analysesStream =
          analyzesRepository.getAnalysesForSwimmer(_selectedSwimmer.id);

      // If the user is a coach, also fetch the list of their swimmers.
      if (widget.appUser.userType == UserType.coach) {
        final userRepository = Provider.of<UserRepository>(context, listen: false);
        if (widget.appUser.clubId != null && widget.appUser.clubId!.isNotEmpty) {
          _swimmersFuture = userRepository.getUsersByClub(widget.appUser.clubId!).first;
        } else {
          _swimmersFuture = userRepository.getUsersCreatedByMe().first;
        }
      }
      _isInitialized = true;
    }
  }

  /// Rebuilds the analysis stream when a new swimmer is selected.
  void _onSwimmerSelected(AppUser? swimmer) {
    if (swimmer != null && swimmer.id != _selectedSwimmer.id) {
      setState(() {
        _selectedSwimmer = swimmer;
        final analyzesRepository =
        Provider.of<StrokeAnalysisRepository>(context, listen: false);
        _analysesStream =
            analyzesRepository.getAnalysesForSwimmer(_selectedSwimmer.id);
      });
    }
  }

  /// Builds the dropdown selector for coaches.
  Widget _buildSwimmerSelector() {
    return FutureBuilder<List<AppUser>>(
      future: _swimmersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: LinearProgressIndicator(),
          );
        }

        // Combine the coach's own user with their list of swimmers.
        final swimmers = snapshot.data ?? [];
        final allSelectableUsers = [widget.appUser, ...swimmers];
        final uniqueUsers = allSelectableUsers.toSet().toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: DropdownButtonFormField<AppUser>(
            initialValue: _selectedSwimmer,
            decoration: const InputDecoration(
              labelText: 'Select Swimmer',
              border: OutlineInputBorder(),
            ),
            items: uniqueUsers.map((user) {
              return DropdownMenuItem<AppUser>(
                value: user,
                child: Text(
                    user.id == widget.appUser.id ? 'My Analyses' : user.name),
              );
            }).toList(),
            onChanged: _onSwimmerSelected,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stroke Analysis History'),
      ),
      body: Column(
        children: [
          // Show swimmer selector only for coaches
          if (widget.appUser.userType == UserType.coach)
            _buildSwimmerSelector(),

          // Display the list of analyses
          Expanded(
            child: StreamBuilder<List<StrokeAnalysis>>(
              stream: _analysesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  debugPrint(snapshot.error.toString());
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final analyses = snapshot.data;
                if (analyses == null || analyses.isEmpty) {
                  return const Center(child: Text('No stroke analyses found.'));
                }

                return ListView.builder(
                  itemCount: analyses.length,
                  itemBuilder: (context, index) {
                    final analysis = analyses[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      child: ListTile(
                        title: Text(analysis.title),
                        subtitle: Text(
                            '${analysis.stroke.name} - ${analysis.createdAt.toLocal().toString().split(' ')[0]}'),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) {
                                final markedTimestamps = analysis.markedTimestamps.map(
                                      (key, value) => MapEntry(
                                    StrokeEfficiencyEvent.values.byName(key),
                                    Duration(milliseconds: value),
                                  ),
                                );

                                final strokeTimestamps = analysis.strokeTimestamps
                                    .map((ms) => Duration(milliseconds: ms))
                                    .toList();

                                return StrokeAnalysisResultView(
                                  intensity: analysis.intensity,
                                  markedTimestamps: markedTimestamps,
                                  strokeTimestamps: strokeTimestamps,
                                  strokeFrequency: analysis.strokeFrequency,
                                  stroke: analysis.stroke,
                                  user: _selectedSwimmer, // Pass the selected swimmer
                                );
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}