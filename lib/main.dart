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

  // New data model for lap-based attribute tracking
  List<LapData> _lapData = [];
  int _lapCount = 0;
  int _attributeEditingLapIndex = 0;

  bool _isSlowMotion = false;
  _AnalysisMode _analysisMode = _AnalysisMode.timing;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    PermissionStatus status;
    if (Platform.isIOS) {
      status = await Permission.photos.request();
    } else {
      status = await Permission.videos.request();
    }

    if (!status.isGranted) {
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
        final selectedEvent = await _selectRace();
        if (selectedEvent != null) {
          _initializeVideoPlayer(file, selectedEvent);
        } else {
          setState(() {
            _isLoadingVideo = false;
          });
        }
      } else {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    } finally {
      if (mounted && _controller == null) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  Future<Stroke?> _selectStroke() {
    return showDialog<Stroke>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Stroke'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: Stroke.values.map((stroke) {
              return ListTile(
                title: Text(stroke.displayName),
                onTap: () {
                  Navigator.of(context).pop(stroke);
                },
              );
            }).toList(),
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

  Future<Event?> _selectRace() async {
    // Stage 1: Select Distance
    final selectedRaceType = await showDialog<Type>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Race Distance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ],
        );
      },
    );

    if (selectedRaceType == null) return null;

    // Stage 2: Select Stroke
    final selectedStroke = await _selectStroke();

    if (selectedStroke == null) return null;

    // Stage 3: Construct and return the event
    if (selectedRaceType == FiftyMeterRace) {
      return FiftyMeterRace(stroke: selectedStroke);
    } else if (selectedRaceType == HundredMetersRace) {
      return HundredMetersRace(stroke: selectedStroke);
    }

    return null;
  }

  void _initializeVideoPlayer(XFile file, Event event) {
    _controller?.dispose();
    _controller = VideoPlayerController.file(File(file.path))
      ..initialize().then((_) {
        setState(() {
          _currentEvent = event;
          _isLoadingVideo = false;
          _resetAnalysis();
        });
        _controller?.addListener(() {
          setState(() {});
        });
      });
  }

  void _resetAnalysis() {
    _controller?.seekTo(Duration.zero);
    _controller?.pause();
    HapticFeedback.heavyImpact();
    setState(() {
      _recordedTimes.clear();
      _currentCheckPointIndex = 0;
      _isSlowMotion = false;
      _controller?.setPlaybackSpeed(1.0);
      _attributeEditingLapIndex = 0;

      // Initialize lap data based on the event
      _lapCount =
          _currentEvent?.checkPoints.where((cp) => cp == CheckPoint.turn).length ?? 0;
      _lapCount += 1; // Add the final lap to the finish
      _lapData = List.generate(_lapCount, (_) => LapData(), growable: false);
    });
  }

  void _recordCheckpoint() {
    if (_controller == null || _currentEvent == null) return;
    final position = _controller!.value.position;
    final nextCheckPoint = _currentEvent!.checkPoints[_currentCheckPointIndex];

    HapticFeedback.mediumImpact();

    setState(() {
      _recordedTimes[nextCheckPoint] = position;
      if (_currentCheckPointIndex < _currentEvent!.checkPoints.length - 1) {
        _currentCheckPointIndex++;
      }
    });
  }

  void _rewindAndUndo() {
    if (_currentCheckPointIndex == 0 && _recordedTimes.isEmpty) return;

    HapticFeedback.mediumImpact();

    CheckPoint checkpointToUndo;
    bool wasLastCheckpoint =
        _currentCheckPointIndex == _currentEvent!.checkPoints.length - 1 &&
            _recordedTimes
                .containsKey(_currentEvent!.checkPoints[_currentCheckPointIndex]);

    if (wasLastCheckpoint) {
      checkpointToUndo = _currentEvent!.checkPoints[_currentCheckPointIndex];
    } else {
      checkpointToUndo = _currentEvent!.checkPoints[_currentCheckPointIndex - 1];
    }

    setState(() {
      _recordedTimes.remove(checkpointToUndo);
      if (!wasLastCheckpoint) {
        _currentCheckPointIndex--;
      }
      // Note: This simple undo doesn't clear attribute data for the undone lap.
      // A more robust implementation might be needed if this becomes an issue.
    });

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
    _controller?.pause();

    // Convert our List<LapData> to the Map<CheckPoint, LapData> that ResultsPage expects.
    final lapDataForResults = <CheckPoint, LapData>{};
    final lapEndCheckpoints = _currentEvent!.checkPoints
        .where((cp) => cp == CheckPoint.turn || cp == CheckPoint.finish)
        .toList();

    for (int i = 0; i < _lapData.length; i++) {
      if (i < lapEndCheckpoints.length) {
        lapDataForResults[lapEndCheckpoints[i]] = _lapData[i];
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsPage(
          recordedTimes: _recordedTimes,
          lapData: lapDataForResults,
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
      body: _controller?.value.isInitialized ?? false
          ? Stack(
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
                _buildControlsOverlay(),
              ],
            )
          : Center(
              child: _isLoadingVideo
                  ? const CircularProgressIndicator()
                  : const Text('No video selected.'),
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
    return Column(
      children: [
        VideoProgressIndicator(_controller!, allowScrubbing: true),
        const Spacer(),
        Container(
          color: Colors.black.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                onSelectionChanged: (selection) =>
                    setState(() => _analysisMode = selection.first),
              ),
              const SizedBox(height: 16),
              if (_analysisMode == _AnalysisMode.timing)
                _buildTimingControls()
              else
                _buildAttributeControls(),
              const SizedBox(height: 12),
              _buildTransportControls(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimingControls() {
    final nextCheckPoint = _currentEvent!.checkPoints[_currentCheckPointIndex];
    final isFinished = _recordedTimes.containsKey(CheckPoint.finish);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.replay_5),
            onPressed: _rewindAndUndo,
            iconSize: 40,
            tooltip: 'Rewind & Undo',
            color: Colors.white,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                onPressed: isFinished ? null : _recordCheckpoint,
                backgroundColor: isFinished
                    ? Colors.grey
                    : Theme.of(context).colorScheme.primary,
                heroTag: 'timingFAB',
                child: Icon(isFinished ? Icons.check : Icons.flag),
              ),
              const SizedBox(height: 8),
              Text(
                isFinished ? 'Finished' : 'Record ${nextCheckPoint.name}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: Icon(_isSlowMotion
                ? Icons.slow_motion_video_rounded
                : Icons.slow_motion_video_outlined),
            onPressed: _toggleSlowMotion,
            iconSize: 40,
            tooltip: 'Toggle Slow Motion',
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  void _seekToLapStart(int lapIndex) {
    if (_currentEvent == null) return;

    final turns =
        _currentEvent!.checkPoints.where((cp) => cp == CheckPoint.turn).toList();
    CheckPoint startCheckpoint;

    if (lapIndex == 0) {
      startCheckpoint = CheckPoint.start;
    } else if (lapIndex > 0 && lapIndex <= turns.length) {
      startCheckpoint = turns[lapIndex - 1];
    } else {
      return; // Invalid lap index
    }

    final seekTime = _recordedTimes[startCheckpoint];
    if (seekTime != null) {
      _controller?.seekTo(seekTime);
    }
  }

  void _changeAttributeLap(int delta) {
    final newIndex = _attributeEditingLapIndex + delta;
    if (newIndex >= 0 && newIndex < _lapCount) {
      setState(() {
        _attributeEditingLapIndex = newIndex;
      });
      _seekToLapStart(newIndex);
    }
  }

  Widget _buildAttributeControls() {
    if (_lapData.isEmpty || _currentEvent == null) return const SizedBox.shrink();
    final currentLap = _lapData[_attributeEditingLapIndex];
    final bool isBreaststroke = _currentEvent!.stroke == Stroke.breaststroke;

    return Column(
      children: [
        // Lap Navigator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _attributeEditingLapIndex > 0
                  ? () => _changeAttributeLap(-1)
                  : null,
              color: Colors.white,
            ),
            Text(
              'EDITING LAP ${_attributeEditingLapIndex + 1}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _attributeEditingLapIndex < _lapCount - 1
                  ? () => _changeAttributeLap(1)
                  : null,
              color: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Attribute Counters
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (!isBreaststroke)
              _buildAttributeCounter(
                label: 'Dolphin Kicks',
                count: currentLap.dolphinKickCount,
                onIncrement: () => setState(() => currentLap.dolphinKickCount++),
                onDecrement: () => setState(() => currentLap.dolphinKickCount--),
              ),
            _buildAttributeCounter(
              label: 'Strokes',
              count: currentLap.strokeCount,
              onIncrement: () => setState(() => currentLap.strokeCount++),
              onDecrement: () => setState(() => currentLap.strokeCount--),
            ),
            if (!isBreaststroke)
              _buildAttributeCounter(
                label: 'Breaths',
                count: currentLap.breathCount,
                onIncrement: () => setState(() => currentLap.breathCount++),
                onDecrement: () => setState(() => currentLap.breathCount--),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAttributeCounter({
    required String label,
    required int count,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
        Text('$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: count > 0 ? onDecrement : null,
                iconSize: 24,
                color: Colors.white),
            IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: onIncrement,
                iconSize: 24,
                color: Colors.white),
          ],
        )
      ],
    );
  }

  Widget _buildTransportControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
              icon: const Icon(Icons.restart_alt),
              onPressed: _resetAnalysis,
              tooltip: 'Reset Analysis',
              color: Colors.white),
          IconButton(
            icon: Icon(_controller!.value.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled),
            onPressed: () => setState(() {
              _controller!.value.isPlaying
                  ? _controller!.pause()
                  : _controller!.play();
            }),
            iconSize: 50,
            tooltip: 'Play/Pause',
            color: Colors.white,
          ),
          IconButton(
              icon: const Icon(Icons.video_library),
              onPressed: _pickVideo,
              tooltip: 'Load New Video',
              color: Colors.white),
        ],
      ),
    );
  }
}
