
// QUICK ANALYSIS UI
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swim_analyzer/analysis/race/race_analysis_modes.dart';
import 'package:swim_analyzer/analysis/race/results_page.dart';
import 'package:swim_apps_shared/objects/interval_attributes.dart';
import 'package:swim_apps_shared/objects/race_segment.dart';
import 'package:swim_apps_shared/objects/stroke.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:swim_apps_shared/swim_session/events/checkpoint.dart';
import 'package:swim_apps_shared/swim_session/events/event.dart';
import 'package:video_player/video_player.dart';

import 'analysis_level.dart';
import 'analysis_ui_base.dart';

class QuickAnalysisUI extends StatefulWidget {
  final VideoPlayerController controller;
  final Event event;
  final AppUser appUser;

  // FIX: Add the callback property
  final VoidCallback onStateChanged;

  const QuickAnalysisUI({
    super.key,
    required this.controller,
    required this.event,
    required this.onStateChanged, required this.appUser, // FIX: Make it required
  });

  @override
  State<QuickAnalysisUI> createState() => QuickAnalysisUIState();
}

class QuickAnalysisUIState extends AnalysisUIBaseState<QuickAnalysisUI> {
  List<IntervalAttributes> _lapAttributes = [];
  int _currentLapForAttributes = 0;
  AnalysisMode _analysisMode = AnalysisMode.timing;

  @override
  VideoPlayerController _getControllerFromWidget() => widget.controller;

  @override
  Event _getEventFromWidget() => widget.event;

  // FIX: Implement the abstract method
  @override
  VoidCallback _getOnStateChangedCallback() => widget.onStateChanged;

  // ... rest of _QuickAnalysisUIState is unchanged.
  @override
  void resetAnalysisState() {
    HapticFeedback.heavyImpact();
    controller.seekTo(Duration.zero);
    controller.pause();
    setState(() {
      recordedSegments.clear();
      currentCheckPointIndex = 0;
      isSlowMotion = false;
      controller.setPlaybackSpeed(1.0);
      _currentLapForAttributes = 0;

      final lapCount = event.distance ~/ event.poolLength.distance;
      _lapAttributes = List.generate(lapCount, (_) => IntervalAttributes());

      checkpointKeys =
          List.generate(event.checkPoints.length, (_) => GlobalKey());
    });
  }

  void viewResults() {
    controller.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RaceResultsView(
          recordedSegments: recordedSegments,
          intervalAttributes: _lapAttributes,
          event: widget.event,
          analysisType: AnalysisType.quick,
          appUser: widget.appUser,
        ),
      ),
    );
  }

  Future<void> seekFrames(
      {required bool isForward,
        required VideoPlayerController controller}) async {
    final currentPosition = controller.value.position;

    // Assume 30 FPS if not known
    const frameRate = 30.0;
    final frameDuration = Duration(milliseconds: (1000 / frameRate).round());
    final int frames = isForward ? 1 : -1;
    final newPosition = currentPosition + frameDuration * frames;

    await controller.seekTo(newPosition);
    if (controller.value.isPlaying) {
      await controller.pause();
    }
  }

  void _seekToLapStart(int lapIndex) {
    if (lapIndex == 0) {
      final startSegment = recordedSegments.firstWhere(
              (s) => s.checkPoint == CheckPoint.start,
          orElse: () => recordedSegments.first);
      controller.seekTo(startSegment.splitTimeOfTotalRace);
      return;
    }

    final turnSegments =
    recordedSegments.where((s) => s.checkPoint == CheckPoint.turn).toList();
    if (lapIndex <= turnSegments.length) {
      controller.seekTo(turnSegments[lapIndex - 1].splitTimeOfTotalRace);
    }
  }

  void _changeAttributeLap(int delta) {
    HapticFeedback.lightImpact();
    final newIndex = _currentLapForAttributes + delta;
    final lapCount = event.distance ~/ event.poolLength.distance;
    if (newIndex >= 0 && newIndex < lapCount) {
      setState(() {
        _currentLapForAttributes = newIndex;
        _seekToLapStart(newIndex);
      });
    }
  }

  final TransformationController _zoomController = TransformationController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: InteractiveViewer(
            transformationController: _zoomController,
            panEnabled: true,
            scaleEnabled: true,
            minScale: 1.0,
            maxScale: 8.0,
            onInteractionEnd: (_) {
              // Optional: reset zoom if needed
              // _zoomController.value = Matrix4.identity();
            },
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Expanded(child: _buildControlsOverlay()),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    return Column(
      children: [
        const Spacer(),
        Row(
          children: [
            IconButton(onPressed: ()=>seekFrames(isForward: false, controller: controller), icon: Icon(Icons.arrow_back_outlined)),
            Expanded(child: buildPrecisionScrubber()),
            IconButton(onPressed: ()=>seekFrames(isForward: true,controller: controller), icon: Icon(Icons.arrow_forward_outlined)),
          ],
        ),
        Container(
          color: Colors.black.withAlpha(40),
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<AnalysisMode>(
                segments: const [
                  ButtonSegment(
                      value: AnalysisMode.timing,
                      icon: Icon(Icons.timer),
                      label: Text('Timing')),
                  ButtonSegment(
                      value: AnalysisMode.attributes,
                      icon: Icon(Icons.assessment),
                      label: Text('Attributes')),
                ],
                selected: {_analysisMode},
                onSelectionChanged: (selection) {
                  HapticFeedback.lightImpact();
                  setState(() => _analysisMode = selection.first);
                  if (_analysisMode == AnalysisMode.attributes) {
                    _seekToLapStart(0);
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_analysisMode == AnalysisMode.timing)
                _buildTimingControls()
              else
                _buildLapAttributeControls(),
              const SizedBox(height: 12),
              buildTransportControls(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimingControls() {
    final isFinished = isAnalysisFinished();
    final nextCheckPointName = isFinished
        ? 'Finished'
        : getDistanceForCheckpoint(
        event.checkPoints[currentCheckPointIndex], currentCheckPointIndex);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildCheckpointGuide(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.replay_5),
                  onPressed: rewindAndUndo,
                  iconSize: 40,
                  tooltip: 'Rewind & Undo',
                  color: Colors.white),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    onPressed: isFinished ? null : recordCheckpoint,
                    backgroundColor: isFinished
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                    heroTag: 'timingFAB',
                    child: Icon(isFinished ? Icons.check : Icons.flag),
                  ),
                  const SizedBox(height: 8),
                  Text('Record $nextCheckPointName',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: Icon(isSlowMotion
                    ? Icons.slow_motion_video_rounded
                    : Icons.slow_motion_video_outlined),
                onPressed: toggleSlowMotion,
                iconSize: 40,
                tooltip: 'Toggle Slow Motion',
                color: Colors.white,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLapAttributeControls() {
    final lapCount = event.distance ~/ event.poolLength.distance;
    if (!isAnalysisFinished()) {
      return const Text(
          'Complete all timing checkpoints before adding attributes.',
          style: TextStyle(color: Colors.white70));
    }

    final currentAttributes = _lapAttributes[_currentLapForAttributes];
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;

    String avgSpeedText = '-';
    String strokeFreqText = '-';
    String strokeLengthText = '-';

    RaceSegment? startOfLapSegment;
    RaceSegment? endOfLapSegment;

    if (_currentLapForAttributes == 0) {
      startOfLapSegment = recordedSegments.firstWhere(
              (s) => s.checkPoint == CheckPoint.start,
          orElse: () => recordedSegments.first);
    } else {
      final turnSegments = recordedSegments
          .where((s) => s.checkPoint == CheckPoint.turn)
          .toList();
      if (_currentLapForAttributes - 1 < turnSegments.length) {
        startOfLapSegment = turnSegments[_currentLapForAttributes - 1];
      }
    }

    final turnAndFinishSegments = recordedSegments
        .where((s) =>
    s.checkPoint == CheckPoint.turn ||
        s.checkPoint == CheckPoint.finish)
        .toList();
    if (_currentLapForAttributes < turnAndFinishSegments.length) {
      endOfLapSegment = turnAndFinishSegments[_currentLapForAttributes];
    }

    if (startOfLapSegment != null && endOfLapSegment != null) {
      final lapTime = endOfLapSegment.splitTimeOfTotalRace -
          startOfLapSegment.splitTimeOfTotalRace;
      final lapDistance = event.poolLength.distance.toDouble();

      if (lapTime > Duration.zero && currentAttributes.strokeCount > 0) {
        final speed = lapDistance / (lapTime.inMilliseconds / 1000.0);
        avgSpeedText = '${speed.toStringAsFixed(2)} m/s';

        final freq =
            currentAttributes.strokeCount / (lapTime.inMilliseconds / 1000.0);
        strokeFreqText = freq.toStringAsFixed(2);

        final length = lapDistance / currentAttributes.strokeCount;
        strokeLengthText = '${length.toStringAsFixed(2)} m';
      }
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentLapForAttributes > 0
                    ? () => _changeAttributeLap(-1)
                    : null,
                color: Colors.white),
            Text('EDITING LAP ${_currentLapForAttributes + 1}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentLapForAttributes < lapCount - 1
                    ? () => _changeAttributeLap(1)
                    : null,
                color: Colors.white),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAttributeCounter(
                label: 'Strokes',
                count: currentAttributes.strokeCount,
                onIncrement: () {
                  HapticFeedback.lightImpact();
                  setState(() => currentAttributes.strokeCount++);
                },
                onDecrement: () {
                  HapticFeedback.lightImpact();
                  setState(() => currentAttributes.strokeCount--);
                }),
            if (!isBreaststroke)
              _buildAttributeCounter(
                  label: 'Breaths',
                  count: currentAttributes.breathCount,
                  onIncrement: () {
                    HapticFeedback.lightImpact();
                    setState(() => currentAttributes.breathCount++);
                  },
                  onDecrement: () {
                    HapticFeedback.lightImpact();
                    setState(() => currentAttributes.breathCount--);
                  }),
            if (!isBreaststroke)
              _buildAttributeCounter(
                label: 'Kicks',
                count: currentAttributes.dolphinKickCount,
                onIncrement: () {
                  HapticFeedback.lightImpact();
                  setState(() => currentAttributes.dolphinKickCount++);
                },
                onDecrement: () {
                  HapticFeedback.lightImpact();
                  setState(() => currentAttributes.dolphinKickCount--);
                },
              ),
          ],
        ),
        // const SizedBox(height: 16),
        // Row(
        //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        //   children: [
        //     _buildMetricDisplay(label: 'Avg Speed', value: avgSpeedText),
        //     _buildMetricDisplay(label: 'Str. Freq', value: strokeFreqText),
        //     _buildMetricDisplay(label: 'Str. Length', value: strokeLengthText),
        //   ],
        // ),
      ],
    );
  }

  Widget _buildAttributeCounter(
      {required String label,
        required int count,
        required VoidCallback onIncrement,
        required VoidCallback onDecrement}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: count > 0 ? onDecrement : null,
                iconSize: 30,
                color: count > 0 ? Colors.white : Colors.white30),
            Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
            IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: onIncrement,
                iconSize: 30,
                color: Colors.white),
          ],
        ),
      ],
    );
  }
}