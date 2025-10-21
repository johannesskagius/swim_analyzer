import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/history/compare_starts_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class OffTheBlockHistoryPage extends StatefulWidget {
  final AppUser appUser;

  const OffTheBlockHistoryPage({super.key, required this.appUser});

  @override
  State<OffTheBlockHistoryPage> createState() => _OffTheBlockHistoryPageState();
}

class _OffTheBlockHistoryPageState extends State<OffTheBlockHistoryPage> {
  // A single Stream that is initialized in initState based on user type.
  late final Stream<List<OffTheBlockAnalysisData>> _analysesStream;
  // State for holding swimmer data for coaches.
  Map<String, AppUser> _swimmers = {};
  bool _isLoadingSwimmers = false;
  // Holds the IDs of analyses selected by the user for comparison.
  final List<String> _selectedAnalysisIds = [];
  // Holds the ID of the swimmer selected in the filter dropdown.
  String? _selectedSwimmerId;

  // A getter to determine if the user is a coach, improving readability.
  bool get _isCoach => widget.appUser.userType == UserType.coach;

  @override
  void initState() {
    super.initState();
    // Initialize data streams and fetch necessary data.
    // This is safer than using context.read directly inside initState in some cases.
    // It also allows for a cleaner separation of concerns.
    _initializeStreams();
  }

  /// Refactored Logic: Initializes data streams and fetches initial data.
  /// This helps keep initState clean and organizes the data-loading logic.
  void _initializeStreams() {
    // Using a post-frame callback ensures the context is fully available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Defensive check in case the widget is disposed before this callback runs.
      if (!mounted) return;

      final analysisRepository = context.read<AnalyzesRepository>();

      if (_isCoach && widget.appUser.clubId != null) {
        _analysesStream = analysisRepository
            .getStreamOfOffTheBlockAnalysesForClub(widget.appUser.clubId!);
        final userRepository = context.read<UserRepository>();
        // Fetch the list of swimmers for the coach's club.
        _fetchSwimmers(userRepository, widget.appUser.clubId!);
      } else {
        _analysesStream = analysisRepository
            .getStreamOfOffTheBlockAnalysesForUser(widget.appUser.id);
      }
      // Calling setState ensures the UI rebuilds once the stream is assigned.
      setState(() {});
    });
  }

  /// Fetches the list of swimmers for a given club.
  /// Includes robust error handling and loading state management.
  Future<void> _fetchSwimmers(UserRepository repo, String clubId) async {
    // Prevent starting a new fetch if one is already in progress.
    if (_isLoadingSwimmers) return;

    // Set loading state safely by checking if the widget is still mounted.
    if (mounted) {
      setState(() {
        _isLoadingSwimmers = true;
      });
    }

    try {
      final swimmersList = await repo.getSwimmersForClub(clubId: clubId);
      // Update state only if the widget is still part of the widget tree.
      if (mounted) {
        setState(() {
          // Efficiently create a map of swimmers by their ID for quick lookups.
          _swimmers = {for (var s in swimmersList) s.id: s};
        });
      }
    } catch (e, s) {
      // Error Handling: Log the error to Crashlytics for monitoring.
      // This helps developers track non-fatal issues occurring in the wild.
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: 'Failed to fetch swimmers for club $clubId',
      );

      // Inform the user that something went wrong.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching swimmers: ${e.toString()}')),
        );
      }
    } finally {
      // Cleanup: Always ensure the loading state is turned off, even if an
      // error occurred. Check if mounted before calling setState.
      if (mounted) {
        setState(() {
          _isLoadingSwimmers = false;
        });
      }
    }
  }

  /// Toggles the selection state of a given analysis ID.
  void _toggleSelection(String analysisId) {
    setState(() {
      if (_selectedAnalysisIds.contains(analysisId)) {
        _selectedAnalysisIds.remove(analysisId);
      } else {
        _selectedAnalysisIds.add(analysisId);
      }
    });
  }

  /// Clears all selected analyses.
  void _clearSelections() {
    setState(() {
      _selectedAnalysisIds.clear();
    });
  }

  /// Navigates to the comparison page with the selected analysis IDs.
  void _navigateToComparison() {
    // Prevent navigation if no analyses are selected. This is a safeguard.
    if (_selectedAnalysisIds.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompareStartsPage(
          appUser: widget.appUser,
          analysisIds: List.from(_selectedAnalysisIds), // Pass a copy
        ),
      ),
    );
  }

  /// Handles changes from the swimmer filter dropdown.
  void _onSwimmerFilterChanged(String? newSwimmerId) {
    setState(() {
      _selectedSwimmerId = newSwimmerId;
      // Refactored: Clear selections when the filter changes to avoid
      // confusion and potential state inconsistencies.
      _clearSelections();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Analysis History'),
        // Add a clear selection button when items are selected for better UX.
        actions: [
          if (_selectedAnalysisIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Selection',
              onPressed: _clearSelections,
            ),
        ],
      ),
      body: Column(
        children: [
          // The filter is only shown for coaches after swimmers have been loaded.
          if (_isCoach && !_isLoadingSwimmers) _buildSwimmerFilter(),
          Expanded(
            child: _buildAnalysesList(),
          ),
        ],
      ),
      // Use a dedicated builder method for the FAB for better readability.
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /// Refactored Widget: Builds the swimmer filter dropdown.
  /// This isolates the UI logic for the filter, making it easier to manage.
  Widget _buildSwimmerFilter() {
    // Don't show the filter if there are no swimmers to choose from.
    if (_swimmers.isEmpty) return const SizedBox.shrink();

    // Create a sorted list of swimmers for a user-friendly dropdown order.
    final sortedSwimmers = _swimmers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: DropdownButtonFormField<String?>(
        initialValue: _selectedSwimmerId,
        hint: const Text('Filter by swimmer'),
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          prefixIcon: const Icon(Icons.filter_list),
          // Adding a clear button directly to the filter improves usability.
          suffixIcon: _selectedSwimmerId != null
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => _onSwimmerFilterChanged(null),
            tooltip: 'Clear filter',
          )
              : null,
        ),
        items: [
          // An explicit option to show analyses for all swimmers.
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All Swimmers'),
          ),
          ...sortedSwimmers.map((swimmer) => DropdownMenuItem<String?>(
            value: swimmer.id,
            child: Text(swimmer.name),
          )),
        ],
        onChanged: _onSwimmerFilterChanged,
      ),
    );
  }

  /// Refactored Widget: Builds the list of analyses using a StreamBuilder.
  /// This separates the main content body from the Scaffold structure.
  Widget _buildAnalysesList() {
    return StreamBuilder<List<OffTheBlockAnalysisData>>(
      stream: _analysesStream,
      builder: (context, snapshot) {
        // Handle loading state for both the stream and the swimmer fetch.
        if (_isLoadingSwimmers ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Handle stream errors gracefully.
        if (snapshot.hasError) {
          // Error Handling: Log stream errors to Crashlytics for diagnosis.
          FirebaseCrashlytics.instance.recordError(
            snapshot.error,
            snapshot.stackTrace,
            reason: 'Error in _analysesStream',
          );
          debugPrint(snapshot.error.toString());
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        // Use a null-safe check on the data and handle the empty case.
        final allAnalyses = snapshot.data ?? [];
        if (allAnalyses.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No start analyses found.\nGo to the Analysis tab to record one!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }

        // Apply the swimmer filter to the list of analyses.
        final filteredAnalyses = _selectedSwimmerId == null
            ? allAnalyses
            : allAnalyses
            .where((analysis) => analysis.swimmerId == _selectedSwimmerId)
            .toList();

        // Show a message if the filter results in an empty list.
        if (filteredAnalyses.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No analyses found for the selected swimmer.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }

        // Build the list view with the filtered data.
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80), // Avoid FAB overlap
          itemCount: filteredAnalyses.length,
          itemBuilder: (context, index) {
            final analysis = filteredAnalyses[index];
            return _buildAnalysisListItem(analysis);
          },
        );
      },
    );
  }

  /// Refactored Widget: Builds a single list item for an analysis.
  /// This makes the ListView builder more concise and easier to read.
  Widget _buildAnalysisListItem(OffTheBlockAnalysisData analysis) {
    final isSelected = _selectedAnalysisIds.contains(analysis.id);

    // Determine the subtitle based on the user type.
    String subtitle;
    if (_isCoach) {
      // Stability: Use a null-safe lookup for the swimmer's name and provide
      // a fallback default value to prevent null reference errors.
      final swimmerName =
          _swimmers[analysis.swimmerId]?.name ?? 'Unknown Swimmer';
      subtitle = '$swimmerName • ${DateFormat.yMMMd().format(analysis.date)}';
    } else {
      subtitle =
      '${DateFormat.yMMMd().format(analysis.date)} • ${analysis.startDistance.toStringAsFixed(2)}m distance';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.transparent,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => _toggleSelection(analysis.id),
        tileColor:
        isSelected ? Theme.of(context).primaryColor.withAlpha(15) : null,
        leading: const Icon(Icons.start, color: Colors.blueAccent),
        title: Text(analysis.title),
        subtitle: Text(subtitle),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
            : const Icon(Icons.circle_outlined),
      ),
    );
  }

  /// Refactored Widget: Builds the FloatingActionButton based on selection state.
  /// Returns null if no items are selected, hiding the button.
  Widget? _buildFloatingActionButton() {
    if (_selectedAnalysisIds.isEmpty) {
      return null;
    }

    final selectionCount = _selectedAnalysisIds.length;
    final isSingleSelection = selectionCount == 1;

    return FloatingActionButton.extended(
      heroTag: 'off_the_block_history_fab',
      onPressed: _navigateToComparison,
      label: Text(isSingleSelection ? 'View' : 'Compare ($selectionCount)'),
      icon: Icon(isSingleSelection ? Icons.visibility : Icons.compare_arrows),
    );
  }
}
