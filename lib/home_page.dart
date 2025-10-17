import 'package:flutter/material.dart';
import 'package:swim_analyzer/history/pick_race_history_page.dart';
import 'package:swim_analyzer/settings_page.dart';
import 'package:swim_apps_shared/src/objects/user.dart';

import 'analysis/pick_analysis.dart';

class HomePage extends StatefulWidget {
  final AppUser appUser;
  const HomePage({super.key, required this.appUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppUser appUser;
  int _selectedIndex = 0;

  late List<Widget> _widgetOptions;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  @override
  void initState() {
    appUser = widget.appUser;
    _widgetOptions = <Widget>[
      PickAnalysis(appUser: appUser),
      PickRaceHistoryPage(appUser: appUser),
      SettingsPage(appUser: appUser),
    ];
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: _widgetOptions,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analyze',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed, // To show all labels
      ),
    );
  }
}
