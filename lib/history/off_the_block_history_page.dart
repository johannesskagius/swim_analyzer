import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/start/off_the_block_result.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

import '../analysis/start/off_the_block_analysis.dart';

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

  @override
  void initState() {
    super.initState();
    final analysisRepository = context.read<AnalyzesRepository>();
    final userRepository = context.read<UserRepository>();

    if (widget.appUser.userType == UserType.coach &&
        widget.appUser.clubId != null) {
      _analysesStream =
          analysisRepository.getStreamOfOffTheBlockAnalysesForClub(widget.appUser.clubId!);
      _fetchSwimmers(userRepository, widget.appUser.clubId!);
    } else {
      _analysesStream =
          analysisRepository.getStreamOfOffTheBlockAnalysesForUser(widget.appUser.id);
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
      // Handle error, e.g., show a snackbar
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

  @override
  Widget build(BuildContext context) {
    final analysisRepository = context.read<AnalyzesRepository>();

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
                child: Dismissible(
                  key: Key(analysis.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Confirm Deletion'),
                          content: const Text(
                              'Are you sure you want to delete this analysis?'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  onDismissed: (direction) {
                    analysisRepository.deleteOffTheBlockAnalysis(analysis.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${analysis.title} deleted')),
                    );
                  },
                  child: ListTile(
                    leading: const Icon(Icons.start, color: Colors.blueAccent),
                    title: Text(analysis.title),
                    subtitle: Text(subtitle),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      final Map<OffTheBlockEvent, Duration> timestamps =
                          analysis.markedTimestamps.map((key, value) {
                        final event = OffTheBlockEvent.values
                            .firstWhere((e) => e.name == key);
                        return MapEntry(event, Duration(milliseconds: value));
                      });

                      AppUser targetUser = widget.appUser;
                      if (widget.appUser.userType == UserType.coach) {
                        if (_swimmers.containsKey(analysis.swimmerId)) {
                          targetUser = _swimmers[analysis.swimmerId]!;
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Cannot open analysis: Swimmer not found.')),
                          );
                          return;
                        }
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OffTheBlockResultsPage(
                              markedTimestamps: timestamps,
                              id: analysis.id,
                              startDistance:
                                  analysis.startDistance.toStringAsFixed(2),
                              startHeight: analysis.startHeight,
                              jumpData: analysis.jumpData,
                              appUser: targetUser),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
