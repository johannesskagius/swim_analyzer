import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swim_analyzer/analysis/pick_analysis.dart';
import 'package:swim_analyzer/history/pick_race_history_page.dart';
import 'package:swim_analyzer/settings_page.dart';
import 'package:swim_apps_shared/src/objects/user.dart';

class HomePage extends StatefulWidget {
  final AppUser appUser;
  const HomePage({super.key, required this.appUser});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late final PageController _pageController;
  late final List<Widget> _widgetOptions;

  // A list of titles for the AppBar corresponding to each page.
  static const List<String> _pageTitles = <String>[
    'Analyze',
    'History',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _widgetOptions = <Widget>[
      PickAnalysis(appUser: widget.appUser),
      PickRaceHistoryPage(appUser: widget.appUser),
      SettingsPage(appUser: widget.appUser),
    ];
  }

  @override
  void dispose() {
    // It's important to dispose of the controller when the widget is removed.
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    // Add haptic feedback for a more tactile response.
    HapticFeedback.mediumImpact();

    // Animate to the new page.
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  /// This function is called when the user swipes between pages.
  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitles[_selectedIndex]),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        // PageView enables horizontal swiping between pages.
        child: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          children: _widgetOptions,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analyze',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        indicatorColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }
}