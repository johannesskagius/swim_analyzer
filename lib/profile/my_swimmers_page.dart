import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class MySwimmersPage extends StatelessWidget {
  const MySwimmersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userRepo = Provider.of<UserRepository>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Swimmers'),
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: userRepo.getUsersCreatedByMe(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('An error occurred: ${snapshot.error}'));
          }

          // The stream now provides a List<AppUser>, so we can filter directly.
          final swimmers = snapshot.data
              ?.where((user) => user.userType == UserType.swimmer)
              .toList();

          if (swimmers == null || swimmers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'You have not added any swimmers yet. Swimmers you create will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: swimmers.length,
            itemBuilder: (context, index) {
              final swimmer = swimmers[index];
              final theme = Theme.of(context);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    swimmer.name.isNotEmpty ? swimmer.name[0].toUpperCase() : 'S',
                    style: TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                ),
                title: Text(swimmer.name),
                subtitle: Text(swimmer.email),
                onTap: () {
                  // Optional: Navigate to a detail page for the swimmer
                },
              );
            },
          );
        },
      ),
    );
  }
}
