import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:swim_analyzer/analysis/pick_analysis.dart';
import 'package:swim_analyzer/auth_wrapper.dart';
import 'package:swim_analyzer/history/pick_race_history_page.dart';
import 'package:swim_analyzer/settings_page.dart';

class HomePage extends StatefulWidget {
  // No longer need to pass appUser here, it's in PermissionLevel
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late final PageController _pageController;
  late List<Widget> _pages;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Access the user from the provider to build the pages list.
    final permissions = context.watch<PermissionLevel>();
    final appUser = permissions.appUser;

    _pages = [
      PickAnalysis(appUser: appUser),
      PickRaceHistoryPage(appUser: appUser),
      SettingsPage(appUser: appUser),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      FirebaseCrashlytics.instance.recordError(
        'Invalid index tapped in HomePage navigation: $index',
        StackTrace.current,
        reason: 'An out-of-bounds index was received by _onItemTapped.',
      );
      return; 
    }

    HapticFeedback.mediumImpact();

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  List<NavigationDestination> _buildDestinations() {
    return const [
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
    ];
  }

  String get _currentPageTitle {
    if (_selectedIndex >= 0 && _selectedIndex < _pageTitles.length) {
      return _pageTitles[_selectedIndex];
    }
    FirebaseCrashlytics.instance.recordError(
      'Attempted to access page title with invalid index: $_selectedIndex',
      StackTrace.current,
      reason: 'State inconsistency in HomePage',
    );
    return 'Error';
  }

  @override
  Widget build(BuildContext context) {
    // You can now access permissions anywhere in this build method
    final permissions = context.watch<PermissionLevel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPageTitle),
        automaticallyImplyLeading: false,
        // Example: Only show an action button for coaches
        actions: [
          if (permissions.isCoach)
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () {
                // TODO: Implement coach-specific action
              },
            ),
        ],
      ),
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          children: _pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        destinations: _buildDestinations(),
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        indicatorColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }
}