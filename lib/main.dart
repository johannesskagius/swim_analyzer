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

  // New data model for storing race progression
  final List<RaceSegment> _recordedSegments = [];

  // New data model for interval-based attribute tracking
  List<IntervalAttributes> _intervalAttributes = [];
  int _attributeEditingIntervalIndex = 0;

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
      _recordedSegments.clear();
      _currentCheckPointIndex = 0;
      _isSlowMotion = false;
      _controller?.setPlaybackSpeed(1.0);
      _attributeEditingIntervalIndex = 0;

      // Initialize attribute data for each interval.
      if (_currentEvent != null) {
        final intervalCount = _currentEvent!.checkPoints.length - 1;
        _intervalAttributes =
            List.generate(intervalCount, (_) => IntervalAttributes());
      } else {
        _intervalAttributes = [];
      }
    });
  }

  void _recordCheckpoint() {
    if (_controller == null || _currentEvent == null) return;
    final position = _controller!.value.position;
    final nextCheckPoint = _currentEvent!.checkPoints[_currentCheckPointIndex];

    HapticFeedback.mediumImpact();

    setState(() {
      final segment = RaceSegment(checkPoint: nextCheckPoint, time: position);
      _recordedSegments.add(segment);

      if (_currentCheckPointIndex < _currentEvent!.checkPoints.length - 1) {
        _currentCheckPointIndex++;
      }
    });
  }

  void _rewindAndUndo() {
    if (_recordedSegments.isEmpty) return;

    HapticFeedback.mediumImpact();

    setState(() {
      // We no longer clear attributes on undo. They will persist.
      _recordedSegments.removeLast();

      if (_currentCheckPointIndex > 0) {
        _currentCheckPointIndex--;
      }
    });

    final newPosition =
        _controller!.value.position - const Duration(seconds: 5);
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsPage(
          recordedSegments: _recordedSegments,
          intervalAttributes: _intervalAttributes,
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
          if (_recordedSegments.isNotEmpty)
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
    final isFinished =
        _recordedSegments.any((s) => s.checkPoint == CheckPoint.finish);
    final nextCheckPointName = isFinished
        ? 'Finished'
        : 'Record ${_getDistanceForCheckpoint(_currentEvent!.checkPoints[_currentCheckPointIndex], _currentCheckPointIndex)}';

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
                nextCheckPointName,
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

  String _getDistanceForCheckpoint(CheckPoint cp, int index) {
    if (_currentEvent == null) return cp.name;

    int turnCount = 0;
    // Count how many turns have been passed up to the checkpoint at 'index'.
    for (int i = 0; i < index; i++) {
      if (_currentEvent!.checkPoints[i] == CheckPoint.turn) {
        turnCount++;
      }
    }

    final lapLength = _currentEvent!.poolLength;

    switch (cp) {
      case CheckPoint.start:
        return '0m';
      case CheckPoint.offTheBlock:
        return 'Off Block';
      case CheckPoint.breakOut:
        // Use a simple name in timing mode, the results page will have the asterisk.
        return 'Breakout';
      case CheckPoint.fifteenMeterMark:
        return '${turnCount * lapLength + 15}m';
      case CheckPoint.turn:
        return '${(turnCount + 1) * lapLength}m';
      case CheckPoint.finish:
        return '${_currentEvent!.distance}m';
    }
  }

  void _seekToIntervalStart(int intervalIndex) {
    if (intervalIndex < _recordedSegments.length) {
      _controller?.seekTo(_recordedSegments[intervalIndex].time);
    }
  }

  void _changeAttributeInterval(int delta) {
    final newIndex = _attributeEditingIntervalIndex + delta;
    // You can only edit attributes for intervals that have been timed.
    // An interval exists between two recorded segments.
    if (newIndex >= 0 && newIndex < _recordedSegments.length - 1) {
      setState(() {
        _attributeEditingIntervalIndex = newIndex;
      });
      _seekToIntervalStart(newIndex);
    }
  }

  Widget _buildAttributeControls() {
    // Attribute editing is only possible if at least one interval (two checkpoints) has been recorded.
    if (_recordedSegments.length < 2 || _currentEvent == null) {
      return const Text('Record at least one interval to edit attributes.', style: TextStyle(color: Colors.white70));
    }

    final currentAttributes = _intervalAttributes[_attributeEditingIntervalIndex];
    final bool isBreaststroke = _currentEvent!.stroke == Stroke.breaststroke;

    final startCp = _currentEvent!.checkPoints[_attributeEditingIntervalIndex];
    final endCp = _currentEvent!.checkPoints[_attributeEditingIntervalIndex + 1];

    final startName = _getDistanceForCheckpoint(startCp, _attributeEditingIntervalIndex);
    final endName = _getDistanceForCheckpoint(endCp, _attributeEditingIntervalIndex + 1);

    final bool isUnderwater = (startCp == CheckPoint.offTheBlock || startCp == CheckPoint.turn) && endCp == CheckPoint.breakOut;
    final bool isSwimming = !isUnderwater && startCp != CheckPoint.start && endCp != CheckPoint.offTheBlock;


    return Column(
      children: [
        // Interval Navigator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _attributeEditingIntervalIndex > 0
                  ? () => _changeAttributeInterval(-1)
                  : null,
              color: Colors.white,
            ),
            Text(
              'EDITING: $startName -> $endName',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _attributeEditingIntervalIndex < _recordedSegments.length - 2
                  ? () => _changeAttributeInterval(1)
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
             if (isUnderwater && !isBreaststroke)
              _buildAttributeCounter(
                label: 'Dolphin Kicks',
                count: currentAttributes.dolphinKickCount,
                onIncrement: () => setState(() => currentAttributes.dolphinKickCount++),
                onDecrement: () => setState(() => currentAttributes.dolphinKickCount--),
              ),
            if (isSwimming)
              _buildAttributeCounter(
                label: 'Strokes',
                count: currentAttributes.strokeCount,
                onIncrement: () => setState(() => currentAttributes.strokeCount++),
                onDecrement: () => setState(() => currentAttributes.strokeCount--),
              ),
            if (isSwimming && !isBreaststroke)
              _buildAttributeCounter(
                label: 'Breaths',
                count: currentAttributes.breathCount,
                onIncrement: () => setState(() => currentAttributes.breathCount++),
                onDecrement: () => setState(() => currentAttributes.breathCount--),
              ),
          ],
        )
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
        Text(
          label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: count > 0 ? onDecrement : null,
              iconSize: 30,
              color: count > 0 ? Colors.white : Colors.white30,
            ),
            Text(
              '$count',
              style: const TextStyle(
                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onIncrement,
              iconSize: 30,
              color: Colors.white,
            ),
          ],
        ),
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
            color: Colors.white,
          ),
          IconButton(
            icon: Icon(_controller!.value.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled),
            onPressed: () {
              setState(() {
                _controller!.value.isPlaying
                    ? _controller!.pause()
                    : _controller!.play();
              });
            },
            iconSize: 50,
            tooltip: 'Play/Pause',
            color: Colors.white,
          ),
          IconButton(
            icon: const Icon(Icons.video_library),
            onPressed: _pickVideo,
            tooltip: 'Load New Video',
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}