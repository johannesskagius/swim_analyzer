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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Analysis History'),
      ),
      body: StreamBuilder<List<OffTheBlockAnalysisData>>(
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

          final analyses = snapshot.data!;

          return ListView.builder(
            itemCount: analyses.length,
            itemBuilder: (context, index) {
              final analysis = analyses[index];
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
                margin:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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
                      ? Icon(Icons.check_circle,
                          color: Theme.of(context).primaryColor)
                      : const Icon(Icons.circle_outlined),
                ),
              );
            },
          );
        },
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