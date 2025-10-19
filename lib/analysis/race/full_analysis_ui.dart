// FULL ANALYSIS UI
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swim_analyzer/analysis/race/race_analysis_modes.dart';
import 'package:swim_analyzer/analysis/race/results_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:video_player/video_player.dart';

import 'analysis_level.dart';
import 'analysis_ui_base.dart';

class FullAnalysisUI extends StatefulWidget {
  final VideoPlayerController controller;
  final Event event;
  final AppUser appUser;

  // FIX: Add the callback property
  final VoidCallback onStateChanged;

  const FullAnalysisUI({
    super.key,
    required this.controller,
    required this.event,
    required this.onStateChanged, // FIX: Make it required
    required this.appUser,
  });

  @override
  State<FullAnalysisUI> createState() => FullAnalysisUIState();
}

class FullAnalysisUIState extends AnalysisUIBaseState<FullAnalysisUI> {
  // ... existing properties
  final TransformationController _zoomController = TransformationController();
  List<IntervalAttributes> _intervalAttributes = [];
  int _attributeEditingIntervalIndex = 0;
  AnalysisMode _analysisMode = AnalysisMode.timing;

  @override
  VideoPlayerController _getControllerFromWidget() => widget.controller;

  @override
  Event _getEventFromWidget() => widget.event;

  // FIX: Implement the abstract method
  @override
  VoidCallback _getOnStateChangedCallback() => widget.onStateChanged;

  // ... rest of _FullAnalysisUIState is unchanged.
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
      _attributeEditingIntervalIndex = 0;
      final intervalCount = event.checkPoints.length - 1;
      _intervalAttributes =
          List.generate(intervalCount, (_) => IntervalAttributes());
      checkpointKeys =
          List.generate(event.checkPoints.length, (_) => GlobalKey());
    });
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

  void viewResults() {
    controller.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RaceResultsView(
            recordedSegments: recordedSegments,
            intervalAttributes: _intervalAttributes,
            event: widget.event,
            analysisType: AnalysisType.full,
            appUser: widget.appUser),
      ),
    );
  }

  void _changeAttributeInterval(int delta) {
    HapticFeedback.lightImpact();
    final newIndex = _attributeEditingIntervalIndex + delta;
    if (newIndex >= 0 && newIndex < recordedSegments.length - 1) {
      setState(() => _attributeEditingIntervalIndex = newIndex);
      _seekToIntervalStart(newIndex);
    }
  }

  void _seekToIntervalStart(int intervalIndex) {
    if (intervalIndex < recordedSegments.length) {
      controller.seekTo(recordedSegments[intervalIndex].splitTimeOfTotalRace);
    }
  }

  Widget _buildControlsOverlay() {
    return Column(
      children: [
        const Spacer(),
        Row(
          children: [
            IconButton(
                onPressed: () =>
                    seekFrames(isForward: false, controller: controller),
                icon: Icon(Icons.arrow_back_outlined)),
            Expanded(child: buildPrecisionScrubber()),
            IconButton(
                onPressed: () =>
                    seekFrames(isForward: true, controller: controller),
                icon: Icon(Icons.arrow_forward_outlined)),
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
                    _seekToIntervalStart(0);
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_analysisMode == AnalysisMode.timing)
                _buildTimingControls()
              else
                _buildAttributeControls(),
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

  Widget _buildAttributeControls() {
    if (recordedSegments.length < 2) {
      return const Text('Record at least one interval to edit attributes.',
          style: TextStyle(color: Colors.white70));
    }
    final currentAttributes =
        _intervalAttributes[_attributeEditingIntervalIndex];
    final bool isBreaststroke = widget.event.stroke == Stroke.breaststroke;
    final startCp = event.checkPoints[_attributeEditingIntervalIndex];
    final endCp = event.checkPoints[_attributeEditingIntervalIndex + 1];
    final startName =
        getDistanceForCheckpoint(startCp, _attributeEditingIntervalIndex);
    final endName =
        getDistanceForCheckpoint(endCp, _attributeEditingIntervalIndex + 1);
    final bool isUnderwater =
        (startCp == CheckPoint.offTheBlock || startCp == CheckPoint.turn) &&
            endCp == CheckPoint.breakOut;
    final bool isSwimming = !isUnderwater &&
        startCp != CheckPoint.start &&
        endCp != CheckPoint.offTheBlock;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _attributeEditingIntervalIndex > 0
                    ? () => _changeAttributeInterval(-1)
                    : null,
                color: Colors.white),
            Text('EDITING: $startName -> $endName',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed:
                    _attributeEditingIntervalIndex < recordedSegments.length - 2
                        ? () => _changeAttributeInterval(1)
                        : null,
                color: Colors.white),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (isUnderwater && !isBreaststroke)
              _buildAttributeCounter(
                  label: 'Dolphin Kicks',
                  count: currentAttributes.dolphinKickCount,
                  onIncrement: () =>
                      setState(() => currentAttributes.dolphinKickCount++),
                  onDecrement: () =>
                      setState(() => currentAttributes.dolphinKickCount--)),
            if (isSwimming)
              _buildAttributeCounter(
                  label: 'Strokes',
                  count: currentAttributes.strokeCount,
                  onIncrement: () =>
                      setState(() => currentAttributes.strokeCount++),
                  onDecrement: () =>
                      setState(() => currentAttributes.strokeCount--)),
            if (isSwimming && !isBreaststroke)
              _buildAttributeCounter(
                  label: 'Breaths',
                  count: currentAttributes.breathCount,
                  onIncrement: () =>
                      setState(() => currentAttributes.breathCount++),
                  onDecrement: () =>
                      setState(() => currentAttributes.breathCount--)),
          ],
        )
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
