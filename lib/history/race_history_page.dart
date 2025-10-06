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

  // State variables to manage user roles and selections
  AppUser? _currentUser;
  List<AppUser> _swimmers = [];
  String? _selectedSwimmerId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  /// Fetches the current user\'s profile and, if they are a coach, their list of swimmers.
  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      final userRepo = Provider.of<UserRepository>(context, listen: false);
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final currentUser = await userRepo.getMyProfile();
      if (!mounted) return;

      if (currentUser is Coach) {
        final swimmers =
            await userRepo.getAllSwimmersFromCoach(coachId: currentUser.id);
        if (!mounted) return;
        setState(() {
          _currentUser = currentUser;
          _swimmers = swimmers;
          _isLoading = false;
        });
      } else if (currentUser is Swimmer) {
        setState(() {
          _currentUser = currentUser;
          _selectedSwimmerId = currentUser.id;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
      }
    }
  }

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
        const SnackBar(
            content: Text('Please select at least two races to compare.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            RaceComparisonPage(raceIds: List.from(_selectedRaceIds)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raceRepository = Provider.of<AnalyzesRepository>(context);

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
      body: _buildBody(raceRepository),
      floatingActionButton: _selectedRaceIds.length >= 2
          ? FloatingActionButton.extended(
              heroTag: 'race_history_fab',
              onPressed: _navigateToComparison,
              label: const Text('Compare'),
              icon: const Icon(Icons.compare_arrows),
            )
          : null,
    );
  }

  /// Builds the main body of the page based on the user\'s role and loading state.
  Widget _buildBody(AnalyzesRepository raceRepository) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentUser == null) {
      return const Center(
          child: Text('You must be logged in to view race history.'));
    }

    // If the user is a coach, show a swimmer selector dropdown.
    if (_currentUser is Coach) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              value: _selectedSwimmerId,
              hint: const Text('Select a Swimmer'),
              isExpanded: true,
              items: _swimmers.map((swimmer) {
                return DropdownMenuItem(
                  value: swimmer.id,
                  child: Text(swimmer.name),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedSwimmerId = newValue;
                  _selectedRaceIds
                      .clear(); // Reset selection when swimmer changes
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          if (_swimmers.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'You do not have any swimmers assigned to you.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else if (_selectedSwimmerId == null)
            const Expanded(
              child: Center(
                child:
                    Text('Please select a swimmer to view their race history.'),
              ),
            )
          else
            Expanded(
              child: _buildRacesList(raceRepository, _selectedSwimmerId!),
            ),
        ],
      );
    }

    // If the user is a swimmer, directly show their race list.
    return _buildRacesList(raceRepository, _selectedSwimmerId!);
  }

  Widget _buildRacesList(AnalyzesRepository raceRepository, String userId) {
    return StreamBuilder<List<RaceAnalysis>>(
      stream: raceRepository.getStreamOfRacesForUser(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No races found for this swimmer.'));
        }

        final races = snapshot.data!;

        // Use LayoutBuilder to switch between list and grid view based on width.
        return LayoutBuilder(builder: (context, constraints) {
          // Use a grid for wider screens (landscape or tablet)
          if (constraints.maxWidth > 600) {
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 4 / 1,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: races.length,
              itemBuilder: (context, index) {
                final race = races[index];
                final isSelected = _selectedRaceIds.contains(race.id);
                // For grid view, wrap the tile in a Card for better visual separation.
                return Card(
                  clipBehavior: Clip.antiAlias,
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
                  child: _buildRaceTile(race, isSelected),
                );
              },
            );
          } else {
            // Use the standard list for narrower screens (portrait)
            return ListView.builder(
              itemCount: races.length,
              itemBuilder: (context, index) {
                final race = races[index];
                final isSelected = _selectedRaceIds.contains(race.id);
                return _buildRaceTile(race, isSelected);
              },
            );
          }
        });
      },
    );
  }

  /// Builds the list tile for a single race.
  Widget _buildRaceTile(RaceAnalysis race, bool isSelected) {
    final raceDateFormatted = race.raceDate != null
        ? DateFormat.yMMMd().format(race.raceDate!)
        : 'No Date';

    final strokeName = race.stroke?.name ?? 'Unknown Stroke';
    final titleText = '${race.distance}m $strokeName';
    final subtitleText = '${race.eventName ?? 'Practice'} • $raceDateFormatted';

    return ListTile(
      title: Text(titleText),
      subtitle: Text(subtitleText),
      onTap: () => _toggleSelection(race.id!),
      tileColor:
          isSelected ? Theme.of(context).primaryColor.withOpacity(0.15) : null,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
          : const Icon(Icons.circle_outlined),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
