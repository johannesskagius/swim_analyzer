import 'package:flutter/material.dart';
import 'package:swim_analyzer/history/off_the_block_history_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class PickRaceHistoryPage extends StatelessWidget {
  final AppUser appUser;
  const PickRaceHistoryPage({super.key, required this.appUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ListView(
          padding: const EdgeInsets.all(8.0),
          children: <Widget>[
            Card(
              child: ListTile(
                leading: const Icon(Icons.emoji_events, size: 40),
                title: const Text('Race Analyses'),
                subtitle: const Text('View history of your race results and analyses.'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RaceHistoryPage(brandIconAssetPath: 'assets/icon/icon.png'),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.start, size: 40),
                title: const Text('Start Analyses'),
                subtitle: const Text('View history of your "Off the Block" start analyses.'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OffTheBlockHistoryPage(appUser: appUser),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
