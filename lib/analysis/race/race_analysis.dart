// Added import for Firebase Crashlytics. It's assumed this is set up in your project.
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:swim_analyzer/analysis/race/race_analysis_modes.dart';
import 'package:swim_analyzer/analysis/race/results_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:video_player/video_player.dart';

import '../time_line_painter.dart';
import 'analysis_level.dart';

class RaceAnalysisView extends StatefulWidget {
  final AppUser appUser;
  const RaceAnalysisView({super.key, required this.appUser});

  @override
  State<RaceAnalysisView> createState() => _RaceAnalysisViewState();
}

class _RaceAnalysisViewState extends State<RaceAnalysisView> {
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();
  bool _isLoadingVideo = false;
  // Refactoring: Added a specific error state to show informative messages to the user.
  String? _errorMessage;

  AnalysisType? analysisType;
  Event? _currentEvent;

  final GlobalKey<_FullAnalysisUIState> _fullAnalysisKey = GlobalKey();
  final GlobalKey<_QuickAnalysisUIState> _quickAnalysisKey = GlobalKey();

  void _onChildStateChanged() {
    // This setState call is now safer as it checks if the widget is still in the tree.
    if (mounted) {
      setState(() {
        // This empty call is enough to trigger a rebuild of this widget,
        // which will re-evaluate _buildAppBarActions.
      });
    }
  }

  @override
  void dispose() {
    // FIX: Ensure the video controller is always disposed of to prevent resource leaks.
    _controller?.dispose();
    super.dispose();
  }

  // Refactoring: The video picking and initialization flow was complex and long.
  // It has been broken down into a more robust, sequential process with clear error handling.
  Future<void> _loadNewVideo() async {
    // Reset any previous error messages before starting.
    if (!mounted) return;
    setState(() {
      _isLoadingVideo = true;
      _errorMessage = null;
    });

    try {
      // Step 1: Request necessary permissions.
      final bool hasPermission = await _requestPermissions();
      if (!hasPermission || !mounted) {
        // User will be notified via a SnackBar within _requestPermissions.
        // If the widget is unmounted, we should stop.
        setState(() => _isLoadingVideo = false);
        return;
      }

      // Step 2: Pick the video file from the gallery.
      final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null || !mounted) {
        // If the user cancels the picker, it's not an error, just stop the process.
        setState(() => _isLoadingVideo = false);
        return;
      }

      // Step 3 & 4: Let the user select the analysis type and race details.
      final selectedAnalysisType = await _selectAnalysisType();
      if (selectedAnalysisType == null || !mounted) {
        setState(() => _isLoadingVideo = false);
        return; // User cancelled the dialog.
      }

      final selectedEvent = await _selectRace(selectedAnalysisType);
      if (selectedEvent == null || !mounted) {
        setState(() => _isLoadingVideo = false);
        return; // User cancelled the dialog.
      }

      // Step 5: Initialize the video player with all the selected info.
      await _initializeVideoPlayer(file, selectedAnalysisType, selectedEvent);
    } catch (e, s) {
      // Error Handling: A generic catch-all for any unexpected errors during the process.
      // This could be from the file picker, dialogs, or video initialization.
      print('Error loading video: $e');
      // Log the non-fatal error to Crashlytics for monitoring.
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed during video loading process');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _errorMessage =
          'An unexpected error occurred while loading the video. Please try again.';
        });
      }
    }
  }

  Future<bool> _requestPermissions() async {
    // Using a try-catch block to handle potential platform-specific errors from the permission handler.
    try {
      final status = await (Platform.isIOS
          ? Permission.photos.request()
          : Permission.videos.request());

      // Check for `mounted` before showing a SnackBar to prevent trying to show it on a disposed widget.
      if (!status.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permission is required to select a video.')),
        );
        return false;
      }
      return status.isGranted;
    } catch (e, s) {
      print('Error requesting permissions: $e');
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Permission request failed');
      return false;
    }
  }

  Future<AnalysisType?> _selectAnalysisType() {
    // This function was already quite clean, no major changes needed.
    return showDialog<AnalysisType>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Analysis Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Full Analysis'),
              subtitle:
              const Text('Record detailed splits, strokes, breaths, etc.'),
              onTap: () => Navigator.of(context).pop(AnalysisType.full),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Quick Analysis'),
              subtitle: const Text('Record splits and strokes per lap.'),
              onTap: () => Navigator.of(context).pop(AnalysisType.quick),
            ),
          ],
        ),
      ),
    );
  }

  // Refactoring: This function has been split into smaller, more manageable parts.
  Future<Event?> _selectRace(AnalysisType analysisType) async {
    final Type? selectedRaceType = await _showRaceDistanceDialog();
    if (selectedRaceType == null || !mounted) return null;

    final Stroke? selectedStroke = await _showStrokeDialog();
    if (selectedStroke == null || !mounted) return null;

    // By creating the event here, we ensure we only return a valid object or null.
    // This avoids complex if-else chains and makes the logic clearer.
    return _createEventFromSelection(selectedRaceType, selectedStroke);
  }

  // Refactored: Extracted the race distance dialog for better readability and separation of concerns.
  Future<Type?> _showRaceDistanceDialog() {
    return showDialog<Type>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Race Distance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  title: const Text('25m Race'),
                  onTap: () => Navigator.of(context).pop(TwentyFiveMeterRace),
                ),
                ListTile(
                  title: const Text('50m Race'),
                  onTap: () => Navigator.of(context).pop(FiftyMeterRace),
                ),
                ListTile(
                  title: const Text('100m Race'),
                  onTap: () => Navigator.of(context).pop(HundredMetersRace),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Refactored: Extracted the stroke selection dialog.
  Future<Stroke?> _showStrokeDialog() {
    return showDialog<Stroke>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Stroke'),
          content: SingleChildScrollView( // Added to prevent overflow with many strokes.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: Stroke.values.map((stroke) {
                return ListTile(
                  title: Text(stroke.description),
                  onTap: () => Navigator.of(context).pop(stroke),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // Refactored: A pure function to create an Event object. It is simple, predictable, and easy to test.
  Event? _createEventFromSelection(Type raceType, Stroke stroke) {
    if (raceType == TwentyFiveMeterRace) {
      return TwentyFiveMeterRace(stroke: stroke);
    } else if (raceType == FiftyMeterRace) {
      return FiftyMeterRace(stroke: stroke);
    } else if (raceType == HundredMetersRace) {
      return HundredMetersRace(stroke: stroke);
    }
    // This case should ideally not be reached if dialogs are set up correctly, but it's a safe fallback.
    return null;
  }

  Future<void> _initializeVideoPlayer(
      XFile file, AnalysisType type, Event event) async {
    // FIX: Dispose of the old controller *before* creating a new one.
    await _controller?.dispose();
    final newController = VideoPlayerController.file(File(file.path));

    try {
      await newController.initialize();
      // Stability: Crucial check to ensure the widget is still mounted after an async gap.
      if (!mounted) {
        newController.dispose(); // Clean up the new controller if we can't use it.
        return;
      }
      setState(() {
        _controller = newController;
        analysisType = type;
        _currentEvent = event;
        _isLoadingVideo = false;
        _errorMessage = null; // Clear any previous errors on success.
      });
    } catch (e, s) {
      // Error Handling: Video initialization can fail for many reasons (corrupt file, unsupported format).
      print('Error initializing video: $e');
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'VideoPlayerController.initialize failed');
      // Clean up the failed controller.
      newController.dispose();
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          // Provide a user-facing error message.
          _errorMessage =
          'Could not load this video. The file might be corrupt or in an unsupported format.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_buildAppBarTitle()),
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
      floatingActionButton: _buildFab(),
    );
  }

  String _buildAppBarTitle() {
    if (analysisType == null) return 'Swim Analyzer';
    // FIX: Use null-coalescing operator `??` for safer and cleaner access to _currentEvent.name.
    return analysisType == AnalysisType.full
        ? _currentEvent?.name ?? 'Full Analysis'
        : 'Quick Analysis';
  }

  List<Widget> _buildAppBarActions() {
    bool isFinished = false;
    VoidCallback? viewResults;

    // FIX: A safer way to access the child state. Added null checks for currentState.
    if (mounted) {
      final fullState = _fullAnalysisKey.currentState;
      final quickState = _quickAnalysisKey.currentState;

      if (analysisType == AnalysisType.full && fullState != null) {
        isFinished = fullState.isAnalysisFinished();
        viewResults = fullState._viewResults;
      } else if (analysisType == AnalysisType.quick && quickState != null) {
        isFinished = quickState.isAnalysisFinished();
        viewResults = quickState._viewResults;
      }
    }

    if (isFinished) {
      return [
        IconButton(
          icon: const Icon(Icons.list_alt),
          onPressed: viewResults,
          tooltip: 'View Results',
        ),
      ];
    }
    return [];
  }

  Widget _buildBody() {
    if (_isLoadingVideo) {
      return _buildLoadingIndicator();
    }
    // Show an error message if something went wrong.
    if (_errorMessage != null) {
      return _buildErrorPrompt(_errorMessage!);
    }
    // FIX: Use null-safe access `_controller?` and null-coalescing `?? false` for robustness.
    // Also ensures we have the required event and analysisType data.
    if (_controller?.value.isInitialized ?? false && _currentEvent != null && analysisType != null) {
      switch (analysisType) {
        case AnalysisType.full:
          return _FullAnalysisUI(
            key: _fullAnalysisKey,
            controller: _controller!, // Can safely use `!` here due to the checks above.
            event: _currentEvent!,
            onStateChanged: _onChildStateChanged,
            appUser: widget.appUser,
          );
        case AnalysisType.quick:
          return _QuickAnalysisUI(
            key: _quickAnalysisKey,
            controller: _controller!,
            event: _currentEvent!,
            onStateChanged: _onChildStateChanged,
            appUser: widget.appUser,
          );
        default:
        // This case should not happen if logic is correct, but it's a safe fallback.
          return _buildInitialPrompt();
      }
    }
    return _buildInitialPrompt();
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 50.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Preparing Video...', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  // Refactored: Created a dedicated widget to show error messages, improving user experience.
  Widget _buildErrorPrompt(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 80, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            const Text('Loading Failed',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }


  Widget _buildInitialPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined,
                size: 80, color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 16),
            const Text('Start Your Analysis',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
                'Tap the "Load Video" button below to select a race video from your device.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget? _buildFab() {
    // The FAB should only be visible when no video is loaded.
    if (_controller == null) {
      return FloatingActionButton.extended(
        onPressed: _isLoadingVideo ? null : _loadNewVideo,
        label: const Text('Load Video'),
        icon: const Icon(Icons.video_library),
      );
    }
    return null;
  }
}
