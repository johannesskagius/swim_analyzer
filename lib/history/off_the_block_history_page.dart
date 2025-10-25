import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/history/compare_starts_page.dart';
import 'package:swim_apps_shared/objects/off_the_block_model.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/objects/user/user_types.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class OffTheBlockHistoryPage extends StatefulWidget {
  final AppUser appUser;

  const OffTheBlockHistoryPage({super.key, required this.appUser});

  @override
  State<OffTheBlockHistoryPage> createState() => _OffTheBlockHistoryPageState();
}

class _OffTheBlockHistoryPageState extends State<OffTheBlockHistoryPage> {
  late final Stream<List<OffTheBlockAnalysisData>> _analysesStream;
  Map<String, AppUser> _swimmers = {};
  bool _isLoadingSwimmers = false;
  final List<String> _selectedAnalysisIds = [];
  String? _selectedSwimmerId;

  bool get _isCoach => widget.appUser.userType == UserType.coach;

  @override
  void initState() {
    super.initState();
    // FIX: The stream must be initialized synchronously within initState before the
    // first build method is called. Using a post-frame callback here causes a
    // LateInitializationError because the build method tries to access the
    // stream before the callback has a chance to run.
    final analysisRepository = context.read<AnalyzesRepository>();
    if (_isCoach && widget.appUser.clubId != null) {
      _analysesStream = analysisRepository
          .getStreamOfOffTheBlockAnalysesForClub(widget.appUser.clubId!);
      final userRepository = context.read<UserRepository>();
      _fetchSwimmers(userRepository, widget.appUser.clubId!);
    } else {
      _analysesStream = analysisRepository
          .getStreamOfOffTheBlockAnalysesForUser(widget.appUser.id);
    }
  }

  Future<void> _fetchSwimmers(UserRepository repo, String clubId) async {
    if (_isLoadingSwimmers) return;
    if (mounted) {
      setState(() {
        _isLoadingSwimmers = true;
      });
    }

    try {
      final swimmersList = await repo.getUsersByClub(clubId).first;
      // Step 1: Process the list of swimmers into a map. This is a fast, synchronous operation.
      final swimmersMap = {for (var s in swimmersList) s.id: s};

      // Step 2: Check if the widget is still in the widget tree before updating its state.
      if (mounted) {
        // Step 3: Call setState with the fully prepared data to trigger a UI update.
        setState(() {
          _swimmers = swimmersMap;
        });
      }

    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(
        e,
        s,
        reason: 'Failed to fetch swimmers for club $clubId',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching swimmers: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSwimmers = false;
        });
      }
    }
  }

  void _toggleSelection(String analysisId) {
    setState(() {
      if (_selectedAnalysisIds.contains(analysisId)) {
        _selectedAnalysisIds.remove(analysisId);
      } else {
        _selectedAnalysisIds.add(analysisId);
      }
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedAnalysisIds.clear();
    });
  }

  void _navigateToComparison() {
    if (_selectedAnalysisIds.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompareStartsPage(
          appUser: widget.appUser,
          analysisIds: List.from(_selectedAnalysisIds),
        ),
      ),
    );
  }

  void _onSwimmerFilterChanged(String? newSwimmerId) {
    setState(() {
      _selectedSwimmerId = newSwimmerId;
      _clearSelections();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Analysis History'),
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
          if (_isCoach && !_isLoadingSwimmers) _buildSwimmerFilter(),
          Expanded(
            child: _buildAnalysesList(),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildSwimmerFilter() {
    if (_swimmers.isEmpty) return const SizedBox.shrink();

    final sortedSwimmers = _swimmers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: DropdownButtonFormField<String?>(
        value: _selectedSwimmerId,
        hint: const Text('Filter by swimmer'),
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          prefixIcon: const Icon(Icons.filter_list),
          suffixIcon: _selectedSwimmerId != null
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => _onSwimmerFilterChanged(null),
            tooltip: 'Clear filter',
          )
              : null,
        ),
        items: [
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

  Widget _buildAnalysesList() {
    return StreamBuilder<List<OffTheBlockAnalysisData>>(
      stream: _analysesStream,
      builder: (context, snapshot) {
        if (_isLoadingSwimmers ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          FirebaseCrashlytics.instance.recordError(
            snapshot.error,
            snapshot.stackTrace,
            reason: 'Error in _analysesStream',
          );
          debugPrint(snapshot.error.toString());
          return Center(child: Text('Error: ${snapshot.error}'));
        }

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

        final filteredAnalyses = _selectedSwimmerId == null
            ? allAnalyses
            : allAnalyses
            .where((analysis) => analysis.swimmerId == _selectedSwimmerId)
            .toList();

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

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: filteredAnalyses.length,
          itemBuilder: (context, index) {
            final analysis = filteredAnalyses[index];
            return _buildAnalysisListItem(analysis);
          },
        );
      },
    );
  }

  Widget _buildAnalysisListItem(OffTheBlockAnalysisData analysis) {
    final isSelected = _selectedAnalysisIds.contains(analysis.id);

    String subtitle;
    if (_isCoach) {
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