
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/history/race_comparison_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';


class RaceHistoryPage extends StatefulWidget {
  const RaceHistoryPage({super.key});

  @override
  State<RaceHistoryPage> createState() => _RaceHistoryPageState();
}

class _RaceHistoryPageState extends State<RaceHistoryPage> {
  final List<String> _selectedRaceIds = [];

  void _toggleSelection(String raceId) {
    setState(() {
      if (_selectedRaceIds.contains(raceId)) {
        _selectedRaceIds.remove(raceId);
      } else {
        _selectedRaceIds.add(raceId);
      }
    });
  }

  void _navigateToComparison() {
    if (_selectedRaceIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least two races to compare.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RaceComparisonPage(raceIds: _selectedRaceIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raceRepository = Provider.of<RaceRepository>(context);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    print(userId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Race History'),
        actions: [
          if (_selectedRaceIds.length >= 2)
            IconButton(
              icon: const Icon(Icons.compare_arrows),
              onPressed: _navigateToComparison,
              tooltip: 'Compare Selected',
            ),
        ],
      ),
      body: userId == null
          ? const Center(child: Text('You must be logged in to view race history.'))
          : StreamBuilder<List<Race>>(
              stream: raceRepository.getRacesForUser(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No races found.'));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final races = snapshot.data!;

                return ListView.builder(
                  itemCount: races.length,
                  itemBuilder: (context, index) {
                    final race = races[index];
                    final isSelected = _selectedRaceIds.contains(race.id);
                    return ListTile(
                      title: Text(race.raceName),
                      subtitle: Text(
                        '${race.eventName} - ${DateFormat('yyyy-MM-dd').format(race.raceDate)}',
                      ),
                      onTap: () => _toggleSelection(race.id!),
                      tileColor: isSelected ? Colors.blue.withOpacity(0.2) : null,
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.blue)
                          : const Icon(Icons.circle_outlined),
                    );
                  },
                );
              },
            ),
      floatingActionButton: _selectedRaceIds.length >= 2
          ? FloatingActionButton.extended(
              onPressed: _navigateToComparison,
              label: const Text('Compare'),
              icon: const Icon(Icons.compare_arrows),
            )
          : null,
    );
  }
}
