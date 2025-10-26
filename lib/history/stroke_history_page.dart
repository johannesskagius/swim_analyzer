import 'package:collection/collection.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis.dart';
// Corrected: The new comparison page is imported.
import 'package:swim_analyzer/analysis/stroke/stroke_analysis_comparison_page.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analysis_repository.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/objects/user/user_types.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import '../analysis/stroke/stroke_analyze_result_view.dart';
import '../analysis/stroke/stroke_efficiency_event.dart';

// Removed: The old, incorrect placeholder page import is gone.
// import 'stroke_comparison_page.dart';

class StrokeHistoryPage extends StatefulWidget {
  final AppUser appUser;

  const StrokeHistoryPage({super.key, required this.appUser});

  @override
  State<StrokeHistoryPage> createState() => _StrokeHistoryPageState();
}

class _StrokeHistoryPageState extends State<StrokeHistoryPage> {
  // State variables are now initialized directly where possible.
  late Stream<List<StrokeAnalysis>> _analysesStream;
  late AppUser _selectedSwimmer;
  Future<List<AppUser>>? _swimmersFuture;

  // State for handling selections
  final List<StrokeAnalysis> _selectedAnalyses = [];

  @override
  void initState() {
    super.initState();
    // Refactoring: All initial setup is now done in initState.
    // This is the correct lifecycle method for one-time initialization.
    _initializeForSwimmer(widget.appUser);

    // Fetch the list of swimmers only if the user is a coach.
    if (widget.appUser.userType == UserType.coach) {
      _fetchCoachSwimmers();
    }
  }

  /// Initializes or updates the analysis stream for a given swimmer.
  void _initializeForSwimmer(AppUser swimmer) {
    // This function can be called safely multiple times.
    _selectedSwimmer = swimmer;
    final analyzesRepository =
        Provider.of<StrokeAnalysisRepository>(context, listen: false);
    _analysesStream =
        analyzesRepository.getAnalysesForSwimmer(_selectedSwimmer.id);
  }

  /// Fetches the list of swimmers for a coach. Includes error handling.
  void _fetchCoachSwimmers() {
    // This logic is extracted into its own method for clarity.
    try {
      final userRepository =
          Provider.of<UserRepository>(context, listen: false);
      final clubId = widget.appUser.clubId;

      if (clubId != null && clubId.isNotEmpty) {
        _swimmersFuture = userRepository.getUsersByClub(clubId).first;
      } else {
        // Fallback for coaches not assigned to a club.
        _swimmersFuture = userRepository.getUsersCreatedByMe().first;
      }
    } catch (e, s) {
      debugPrint("Error fetching coach's swimmers: $e");
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Failed to fetch swimmers in StrokeHistoryPage');
      // Set future to an error state so the UI can react.
      setState(() {
        _swimmersFuture = Future.error("Could not load swimmers.");
      });
    }
  }

  /// Handles the selection of a new swimmer from the dropdown.
  void _onSwimmerSelected(AppUser? swimmer) {
    if (swimmer != null && swimmer.id != _selectedSwimmer.id) {
      // When a new swimmer is selected, update the state.
      setState(() {
        _initializeForSwimmer(swimmer);
        // Clear any previous selections.
        _selectedAnalyses.clear();
      });
    }
  }

  // --- Selection and Navigation Logic (from previous refactoring) ---

  void _toggleSelection(StrokeAnalysis analysis) {
    setState(() {
      if (_selectedAnalyses.contains(analysis)) {
        _selectedAnalyses.remove(analysis);
      } else if (_selectedAnalyses.length < 3) {
        _selectedAnalyses.add(analysis);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can select a maximum of 3 analyses to compare.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedAnalyses.clear();
    });
  }

  void _navigateToNextView() {
    if (_selectedAnalyses.isEmpty) return;

    if (_selectedAnalyses.length == 1) {
      _navigateToResultView(_selectedAnalyses.first);
    } else {
      _navigateToComparisonView();
    }
  }

  void _navigateToResultView(StrokeAnalysis analysis) {
    try {
      final markedTimestamps = analysis.markedTimestamps.map(
        (key, value) => MapEntry(
          StrokeEfficiencyEvent.values.byName(key),
          Duration(milliseconds: value),
        ),
      );
      final strokeTimestamps = analysis.strokeTimestamps
          .map((ms) => Duration(milliseconds: ms))
          .toList();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StrokeAnalysisResultView(
            intensity: analysis.intensity,
            markedTimestamps: markedTimestamps,
            strokeTimestamps: strokeTimestamps,
            strokeFrequency: analysis.strokeFrequency,
            stroke: analysis.stroke,
            user: _selectedSwimmer,
          ),
        ),
      );
    } catch (e, s) {
      debugPrint("Error navigating to result view: $e");
      FirebaseCrashlytics.instance.recordError(e, s,
          reason: 'Failed to parse data for StrokeAnalysisResultView');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open analysis. Data may be corrupt.')),
      );
    }
  }

  // FIXED: This method now navigates to the correct comparison page.
  void _navigateToComparisonView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        // The builder now creates an instance of StrokeAnalysisComparisonPage.
        builder: (context) => StrokeAnalysisComparisonPage(
          analyses: _selectedAnalyses,
          // Note: The user parameter is removed as StrokeAnalysisComparisonPage does not require it.
          // If your actual implementation of StrokeAnalysisComparisonPage *does* need the user,
          // you can add it back like this:
          // user: _selectedSwimmer,
        ),
      ),
    );
  }

  /// Builds the dropdown selector for coaches.
  Widget _buildSwimmerSelector() {
    // Return a SizedBox if the future isn't set (e.g., not a coach).
    if (_swimmersFuture == null) return const SizedBox.shrink();

    return FutureBuilder<List<AppUser>>(
      future: _swimmersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: LinearProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Error loading swimmers: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }

        final swimmers = snapshot.data ?? [];
        final uniqueUserMap = {
          widget.appUser.id: widget.appUser,
          for (var user in swimmers) user.id: user,
        };
        final uniqueUsers = uniqueUserMap.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        return Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: DropdownButtonFormField<AppUser>(
            // Use firstWhereOrNull for safety, falling back to the current user.
            value: uniqueUsers
                    .firstWhereOrNull((u) => u.id == _selectedSwimmer.id) ??
                widget.appUser,
            decoration: const InputDecoration(
              labelText: 'Select Swimmer',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12.0),
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
        actions: [
          if (_selectedAnalyses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Selection',
              onPressed: _clearSelection,
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.appUser.userType == UserType.coach)
            _buildSwimmerSelector(),
          Expanded(
            child: StreamBuilder<List<StrokeAnalysis>>(
              stream: _analysesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  debugPrint(snapshot.error.toString());
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          textAlign: TextAlign.center));
                }
                final analyses = snapshot.data;
                if (analyses == null || analyses.isEmpty) {
                  return const Center(
                      child:
                          Text('No stroke analyses found for this swimmer.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  // Space for the FAB
                  itemCount: analyses.length,
                  itemBuilder: (context, index) {
                    final analysis = analyses[index];
                    final isSelected = _selectedAnalyses.contains(analysis);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      elevation: isSelected ? 4.0 : 1.0,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: ListTile(
                        title: Text(analysis.title),
                        subtitle: Text(
                            '${analysis.stroke.name} - ${analysis.createdAt.toLocal().toString().split(' ')[0]}'),
                        trailing: Icon(isSelected
                            ? Icons.check_circle
                            : Icons.circle_outlined),
                        onTap: () => _toggleSelection(analysis),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedAnalyses.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _navigateToNextView,
              label: Text(_selectedAnalyses.length == 1
                  ? 'View'
                  : 'Compare (${_selectedAnalyses.length})'),
              icon: Icon(_selectedAnalyses.length == 1
                  ? Icons.visibility
                  : Icons.compare_arrows),
            )
          : null,
    );
  }
}
