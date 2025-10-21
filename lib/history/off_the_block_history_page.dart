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
  late final Stream<List<OffTheBlockAnalysisData>> _analysesStream;
  Map<String, AppUser> _swimmers = {};
  bool _isLoadingSwimmers = false;
  final List<String> _selectedAnalysisIds = [];

  // --- NEW: State for the swimmer filter ---
  String? _selectedSwimmerId;

  @override
  void initState() {
    super.initState();
    final analysisRepository = context.read<AnalyzesRepository>();
    final userRepository = context.read<UserRepository>();

    if (widget.appUser.userType == UserType.coach &&
        widget.appUser.clubId != null) {
      _analysesStream = analysisRepository
          .getStreamOfOffTheBlockAnalysesForClub(widget.appUser.clubId!);
      _fetchSwimmers(userRepository, widget.appUser.clubId!);
    } else {
      _analysesStream = analysisRepository
          .getStreamOfOffTheBlockAnalysesForUser(widget.appUser.id);
    }
  }

  Future<void> _fetchSwimmers(UserRepository repo, String clubId) async {
    setState(() {
      _isLoadingSwimmers = true;
    });
    try {
      final swimmersList = await repo.getSwimmersForClub(clubId: clubId);
      if (mounted) {
        setState(() {
          _swimmers = {for (var s in swimmersList) s.id: s};
          _isLoadingSwimmers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSwimmers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching swimmers: ${e.toString()}')),
        );
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

  void _navigateToComparison() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompareStartsPage(
          appUser: widget.appUser,
          analysisIds: _selectedAnalysisIds,
        ),
      ),
    );
  }

  // --- NEW: A widget to build the swimmer filter dropdown ---
  Widget _buildSwimmerFilter() {
    // Don't show the filter if there are no swimmers.
    if (_swimmers.isEmpty) return const SizedBox.shrink();

    // Create a sorted list of swimmers first for clarity and correctness.
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
        ),
        items: [
          // Add an option to show all swimmers
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All Swimmers'),
          ),
          ...sortedSwimmers.map((swimmer) => DropdownMenuItem<String?>(
            value: swimmer.id,
            child: Text(swimmer.name),
          )),
        ],
        onChanged: (String? newValue) {
          setState(() {
            _selectedSwimmerId = newValue;
            // Clear selections when the filter changes to avoid confusion
            _selectedAnalysisIds.clear();
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCoach = widget.appUser.userType == UserType.coach;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Analysis History'),
      ),
      // --- MODIFIED: Use a Column to stack the filter and the list ---
      body: Column(
        children: [
          if (isCoach && !_isLoadingSwimmers) _buildSwimmerFilter(),
          Expanded(
            child: StreamBuilder<List<OffTheBlockAnalysisData>>(
              stream: _analysesStream,
              builder: (context, snapshot) {
                if (_isLoadingSwimmers ||
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  debugPrint(snapshot.error.toString());
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
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

                // --- MODIFIED: Apply the filter to the data ---
                final allAnalyses = snapshot.data!;
                final filteredAnalyses = _selectedSwimmerId == null
                    ? allAnalyses
                    : allAnalyses
                    .where(
                        (analysis) => analysis.swimmerId == _selectedSwimmerId)
                    .toList();

                // If the filter results in an empty list, show a message
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
                  itemCount: filteredAnalyses.length,
                  itemBuilder: (context, index) {
                    final analysis = filteredAnalyses[index];
                    final isSelected = _selectedAnalysisIds.contains(analysis.id);
                    String subtitle;
                    if (widget.appUser.userType == UserType.coach) {
                      final swimmerName =
                          _swimmers[analysis.swimmerId]?.name ?? 'Unknown Swimmer';
                      subtitle =
                      '$swimmerName • ${DateFormat.yMMMd().format(analysis.date)}';
                    } else {
                      subtitle =
                      '${DateFormat.yMMMd().format(analysis.date)} • ${analysis.startDistance.toStringAsFixed(2)}m distance';
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
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
                        tileColor: isSelected
                            ? Theme.of(context).primaryColor.withAlpha(15)
                            : null,
                        leading:
                        const Icon(Icons.start, color: Colors.blueAccent),
                        title: Text(analysis.title),
                        subtitle: Text(subtitle),
                        trailing: isSelected
                            ? Icon(Icons.check_circle,
                            color: Theme.of(context).primaryColor)
                            : const Icon(Icons.circle_outlined),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedAnalysisIds.isNotEmpty
          ? FloatingActionButton.extended(
        heroTag: 'off_the_block_history_fab',
        onPressed: _navigateToComparison,
        label: Text(
            _selectedAnalysisIds.length == 1 ? 'View' : 'Compare'),
        icon: Icon(_selectedAnalysisIds.length == 1
            ? Icons.visibility
            : Icons.compare_arrows),
      )
          : null,
    );
  }
}