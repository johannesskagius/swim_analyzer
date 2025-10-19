import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

  // Refactored: Encapsulated page configurations into a single data structure.
  // This makes it easier to add, remove, or reorder pages without causing
  // inconsistencies between titles, widgets, and navigation items.
  late final List<(_PageConfig, Widget)> _pageConfigs;

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

    // Initialization of page configurations.
    _pageConfigs = [
      (
      const _PageConfig(
        label: 'Analyze',
        icon: Icon(Icons.analytics_outlined),
        selectedIcon: Icon(Icons.analytics),
      ),
      PickAnalysis(appUser: widget.appUser)
      ),
      (
      const _PageConfig(
        label: 'History',
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
      ),
      PickRaceHistoryPage(appUser: widget.appUser)
      ),
      (
      const _PageConfig(
        label: 'Settings',
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
      ),
      SettingsPage(appUser: widget.appUser)
      ),
    ];
  }

  @override
  void dispose() {
    // It's important to dispose of the controller to prevent memory leaks.
    _pageController.dispose();
    super.dispose();
  }

  /// Handles tap events on the bottom navigation bar items.
  void _onItemTapped(int index) {
    // Non-fatal error handling: Check if the index is valid before proceeding.
    // This prevents a crash if an invalid index is somehow passed, which could
    // happen during complex state updates or bugs in the Flutter framework.
    if (index < 0 || index >= _pageConfigs.length) {
      // Log the non-fatal error to Crashlytics for monitoring.
      FirebaseCrashlytics.instance.recordError(
        'Invalid index tapped in HomePage navigation: $index',
        StackTrace.current,
        reason: 'An out-of-bounds index was received by _onItemTapped.',
      );
      return; // Stop execution to prevent a crash.
    }

    // Add haptic feedback for a more tactile response.
    HapticFeedback.mediumImpact();

    // Animate to the new page using the page controller.
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Updates the state when the user swipes between pages in the PageView.
  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Refactored: Builds the list of NavigationDestinations dynamically.
  /// This function makes the build method cleaner and ensures the navigation
  /// bar is always in sync with the page configurations.
  List<NavigationDestination> _buildDestinations() {
    return _pageConfigs.map((config) {
      return NavigationDestination(
        icon: config.$1.icon,
        selectedIcon: config.$1.selectedIcon,
        label: config.$1.label,
      );
    }).toList();
  }

  /// Refactored: Provides the current page title safely.
  /// This getter includes boundary checks to prevent a RangeError if `_selectedIndex`
  /// becomes invalid, returning a safe fallback title instead.
  String get _currentPageTitle {
    if (_selectedIndex >= 0 && _selectedIndex < _pageConfigs.length) {
      return _pageConfigs[_selectedIndex].$1.label;
    }
    // Log a non-fatal error if the index is out of bounds.
    FirebaseCrashlytics.instance.recordError(
      'Attempted to access page title with invalid index: $_selectedIndex',
      StackTrace.current,
      reason: 'State inconsistency in HomePage',
    );
    return 'Error'; // Fallback title to prevent a crash.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Use the safe getter for the title.
        title: Text(_currentPageTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        // PageView enables horizontal swiping between pages.
        child: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          // Dynamically provide the page widgets.
          children: _pageConfigs.map((config) => config.$2).toList(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        // Use the helper function to build destinations.
        destinations: _buildDestinations(),
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        indicatorColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }
}


/// A private helper class to encapsulate the configuration for a page.
/// This improves organization by grouping related properties (label, icons)
/// and ensures consistency.
class _PageConfig {
  final String label;
  final Icon icon;
  final Icon selectedIcon;

  const _PageConfig({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}
