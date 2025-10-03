import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import 'race_model.dart';
import 'results_page.dart';

void main() {
  runApp(const SwimAnalyzerApp());
}

class SwimAnalyzerApp extends StatelessWidget {
  const SwimAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swim Analyzer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RaceAnalysisPage(),
    );
  }
}

class RaceAnalysisPage extends StatefulWidget {
  const RaceAnalysisPage({super.key});

  @override
  State<RaceAnalysisPage> createState() => _RaceAnalysisPageState();
}

/// Enum to manage the user's current analysis focus.
enum _AnalysisMode { timing, attributes }

class _RaceAnalysisPageState extends State<RaceAnalysisPage> {
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();
  bool _isLoadingVideo = false;

  Event? _currentEvent;
  int _currentCheckPointIndex = 0;

  final Map<CheckPoint, Duration> _recordedTimes = {};
  Map<CheckPoint, LapData> _lapData = {};
  LapData _currentLapData = LapData();

  bool _isSlowMotion = false;

  // New state for managing the analysis mode
  _AnalysisMode _analysisMode = _AnalysisMode.timing;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    // Request the appropriate permission based on the platform.
    PermissionStatus status;
    if (Platform.isIOS) {
      // On iOS, Permission.photos is needed to access the gallery for videos.
      status = await Permission.photos.request();
    } else {
      // On Android 13+ this is correct. For older versions, Permission.storage
      // might be needed, but this is a common approach for modern apps.
      status = await Permission.videos.request();
    }

    if (!status.isGranted) {
      // Handle the case where the user denies the permission.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permission is required to select a video.')),
        );
      }
      return;
    }

    setState(() {
      _isLoadingVideo = true;
    });

    try {
      final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);

      if (file != null) {
        // After picking a video, prompt the user to select the race.
        final selectedEvent = await _selectRace();
        if (selectedEvent != null) {
          _initializeVideoPlayer(file, selectedEvent);
        } else {
          // User cancelled race selection, reset loading state.
          setState(() {
            _isLoadingVideo = false;
          });
        }
      } else {
        // User cancelled video picking.
        setState(() {
          _isLoadingVideo = false;
        });
      }
    } finally {
      // Ensure loading indicator is turned off if something fails during race selection
      if (mounted && _controller == null) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  Future<Event?> _selectRace() {
    return showDialog<Event>(
      context: context,
      barrierDismissible: false, // User must make a choice.
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Race Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: const Text('50m Race'),
                onTap: () {
                  Navigator.of(context).pop(const FiftyMeterRace());
                },
              ),
              ListTile(
                title: const Text('100m Race'),
                onTap: () {
                  Navigator.of(context).pop(const HundredMetersRace());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(null);
              },
            ),
          ],
        );
      },
    );
  }

  void _initializeVideoPlayer(XFile file, Event event) {
    // Dispose the old controller if it exists.
    _controller?.dispose();

    _controller = VideoPlayerController.file(File(file.path))
      ..initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized.
        setState(() {
          _currentEvent = event;
          _isLoadingVideo = false; // Turn off loading indicator
          _resetAnalysis(); // Reset state for the new video
        });
        _controller?.addListener(() {
          // This listener is useful if you want to react to video progress.
          // For instance, to update a progress bar. We can leave it empty for now.
          // setState(() {}); // This would rebuild the widget on every frame. Avoid unless necessary.
        });
      });
  }

  /// Resets the entire analysis state.
  void _resetAnalysis() {
    _controller?.seekTo(Duration.zero);
    _controller?.pause();
    HapticFeedback.heavyImpact();
    setState(() {
      _recordedTimes.clear();
      _lapData.clear();
      _currentLapData = LapData();
      _currentCheckPointIndex = 0;
      _isSlowMotion = false;
      _controller?.setPlaybackSpeed(1.0);
    });
  }

  void _recordCheckpoint() {
    if (_controller == null || _currentEvent == null) return;
    final position = _controller!.value.position;
    final nextCheckPoint = _currentEvent!.checkPoints[_currentCheckPointIndex];

    HapticFeedback.mediumImpact();

    setState(() {
      _recordedTimes[nextCheckPoint] = position;
      // If the checkpoint marks the end of a lap (turn or finish), store the lap data.
      if (nextCheckPoint == CheckPoint.turn ||
          nextCheckPoint == CheckPoint.finish) {
        _lapData[nextCheckPoint] = _currentLapData;
        _currentLapData = LapData(); // Reset for the next lap.
      }

      if (_currentCheckPointIndex < _currentEvent!.checkPoints.length - 1) {
        _currentCheckPointIndex++;
      }
    });
  }

  void _rewindAndUndo() {
    if (_currentCheckPointIndex == 0 && _recordedTimes.isEmpty) return;

    HapticFeedback.mediumImpact();

    // Determine the checkpoint to remove.
    // If we've recorded everything, the last one is at the end of the list.
    // Otherwise, the last recorded one is the one before the current index.
    CheckPoint checkpointToUndo;
    bool wasLastCheckpoint =
        _currentCheckPointIndex == _currentEvent!.checkPoints.length - 1 &&
            _recordedTimes.containsKey(
                _currentEvent!.checkPoints[_currentCheckPointIndex]);

    if (wasLastCheckpoint) {
      checkpointToUndo = _currentEvent!.checkPoints[_currentCheckPointIndex];
    } else {
      checkpointToUndo = _currentEvent!.checkPoints[_currentCheckPointIndex - 1];
    }

    setState(() {
      _recordedTimes.remove(checkpointToUndo);

      // If the undone checkpoint was the end of a lap, restore the lap data.
      if (_lapData.containsKey(checkpointToUndo)) {
        _currentLapData =
            _lapData.remove(checkpointToUndo) ?? LapData();
      }

      // If we're not at the start, decrement the index.
      if (!wasLastCheckpoint) {
        _currentCheckPointIndex--;
      }
    });

    // Corrected seek logic:
    final newPosition = _controller!.value.position - const Duration(seconds: 5);
    _controller?.seekTo(newPosition.isNegative ? Duration.zero : newPosition);
  }

  void _toggleSlowMotion() {
    if (_controller == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isSlowMotion = !_isSlowMotion;
      _controller!.setPlaybackSpeed(_isSlowMotion ? 0.5 : 1.0);
    });
  }

  void _viewResults() {
    if (_currentEvent == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsPage(
          recordedTimes: _recordedTimes,
          lapData: _lapData,
          event: _currentEvent!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentEvent?.name ?? 'Swim Analyzer'),
        actions: [
          if (_recordedTimes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list_alt),
              onPressed: _viewResults,
              tooltip: 'View Results',
            ),
        ],
      ),
      body: Center(
        child: _controller?.value.isInitialized ?? false
            ? AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  children: [
                    VideoPlayer(_controller!),
                    _buildControlsOverlay(),
                  ],
                ),
              )
            : Container(
                alignment: Alignment.center,
                child: _isLoadingVideo
                    ? const CircularProgressIndicator()
                    : const Text('No video selected.'),
              ),
      ),
      floatingActionButton: _controller == null
          ? FloatingActionButton.extended(
              onPressed: _isLoadingVideo ? null : _pickVideo,
              label: const Text('Load Video'),
              icon: const Icon(Icons.video_library),
            )
          : null,
    );
  }

  Widget _buildControlsOverlay() {
    final nextCheckPoint = _currentEvent!.checkPoints[_currentCheckPointIndex];
    final bool isFinished = _recordedTimes.containsKey(CheckPoint.finish);

    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Column(
        children: [
          VideoProgressIndicator(_controller!, allowScrubbing: true),
          const Spacer(),
          // Analysis Mode Toggle
          SegmentedButton<_AnalysisMode>(
            segments: const [
              ButtonSegment(
                  value: _AnalysisMode.timing,
                  icon: Icon(Icons.timer),
                  label: Text('Timing')),
              ButtonSegment(
                  value: _AnalysisMode.attributes,
                  icon: Icon(Icons.assessment),
                  label: Text('Attributes')),
            ],
            selected: {_analysisMode},
            onSelectionChanged: (selection) {
              setState(() {
                _analysisMode = selection.first;
              });
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Rewind 5s and Undo Button
                IconButton(
                  icon: const Icon(Icons.replay_5),
                  onPressed: _rewindAndUndo,
                  iconSize: 40,
                  tooltip: 'Rewind & Undo',
                ),

                // Center Area: Switches between Timing and Attribute controls
                if (_analysisMode == _AnalysisMode.timing)
                  _buildTimingButton(isFinished, nextCheckPoint)
                else
                  _buildAttributeButtons(),

                // Slow Motion Button
                IconButton(
                  icon: Icon(_isSlowMotion
                      ? Icons.slow_motion_video_rounded
                      : Icons.slow_motion_video_outlined),
                  onPressed: _toggleSlowMotion,
                  iconSize: 40,
                  tooltip: 'Toggle Slow Motion',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.restart_alt),
                  onPressed: _resetAnalysis,
                  tooltip: 'Reset Analysis',
                ),
                IconButton(
   
