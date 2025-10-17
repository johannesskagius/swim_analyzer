import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/start/off_the_block_analysis.dart';
import 'package:swim_analyzer/analysis/start/off_the_block_result.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class OffTheBlockHistoryPage extends StatelessWidget {
  final AppUser appUser;

  const OffTheBlockHistoryPage({super.key, required this.appUser});

  @override
  Widget build(BuildContext context) {
    // Get user and repositories from providers
    final analysisRepository = context.read<AnalyzesRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Analysis History'),
      ),
      body: StreamBuilder<List<OffTheBlockAnalysisData>>(
        stream: analysisRepository
            .getStreamOfOffTheBlockAnalysesForUser(appUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
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
                    subtitle: Text(
                        '${DateFormat.yMMMd().format(analysis.date)} • ${analysis.startDistance.toStringAsFixed(2)}m distance'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      // Convert data back to the format expected by OffTheBlockResultsPage
                      final Map<OffTheBlockEvent, Duration> timestamps =
                          analysis.markedTimestamps.map((key, value) {
                        final event = OffTheBlockEvent.values.firstWhere(
                          (e) => e.name == key,
                          // Provide a fallback, though this should ideally not happen
                          orElse: () => OffTheBlockEvent.startSignal,
                        );
                        return MapEntry(event, Duration(milliseconds: value));
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OffTheBlockResultsPage(
                              markedTimestamps: timestamps,
                              // Pass the ID so the results page knows it's an existing record
                              startDistance:
                                  analysis.startDistance.toStringAsFixed(2),
                              startHeight: analysis.startHeight,
                              jumpData: analysis.jumpData,
                              appUser: appUser),
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
