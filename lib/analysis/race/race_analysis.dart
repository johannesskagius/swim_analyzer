// ... imports remain the same

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

  AnalysisType? analysisType;
  Event? _currentEvent;

  final GlobalKey<_FullAnalysisUIState> _fullAnalysisKey = GlobalKey();
  final GlobalKey<_QuickAnalysisUIState> _quickAnalysisKey = GlobalKey();

  // FIX: Add a callback method to be triggered by child widgets.
  void _onChildStateChanged() {
    setState(() {
      // This empty call is enough to trigger a rebuild of this widget,
      // which will re-evaluate _buildAppBarActions.
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final isPermissionGranted = await _requestPermissions();
    if (!isPermissionGranted || !mounted) return;

    setState(() => _isLoadingVideo = true);

    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    final selectedAnalysisType = await _selectAnalysisType();
    if (selectedAnalysisType == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    final selectedEvent = await _selectRace();
    if (selectedEvent == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    await _initializeVideoPlayer(file, selectedAnalysisType, selectedEvent);
  }

  Future<bool> _requestPermissions() async {
    final status = await (Platform.isIOS
        ? Permission.photos.request()
        : Permission.videos.request());
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permission is required to select a video.')),
      );
      return false;
    }
    return true;
  }

  Future<AnalysisType?> _selectAnalysisType() {
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

  Future<Event?> _selectRace() async {
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
                title: Text('25m Race'),
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
        );
      },
    );

    if (selectedRaceType == null) return null;

    final selectedStroke = await showDialog<Stroke>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Stroke'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: Stroke.values.map((stroke) {
              return ListTile(
                title: Text(stroke.description),
                onTap: () => Navigator.of(context).pop(stroke),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selectedStroke == null) return null;
    if (selectedRaceType == TwentyFiveMeterRace) {
      return TwentyFiveMeterRace(stroke: selectedStroke);
    } else if (selectedRaceType == FiftyMeterRace) {
      return FiftyMeterRace(stroke: selectedStroke);
    } else if (selectedRaceType == HundredMetersRace) {
      return HundredMetersRace(stroke: selectedStroke);
    }
    return null;
  }

  Future<void> _initializeVideoPlayer(
      XFile file, AnalysisType type, Event event) async {
    _controller?.dispose();
    final newController = VideoPlayerController.file(File(file.path));

    try {
      await newController.initialize();
      if (!mounted) {
        newController.dispose();
        return;
      }
      setState(() {
        _controller = newController;
        analysisType = type;
        _currentEvent = event;
        _isLoadingVideo = false;
      });
    } catch (e) {
      print('Error initializing video: $e');
      if (mounted) setState(() => _isLoadingVideo = false);
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
    return analysisType == AnalysisType.full
        ? _currentEvent?.name ?? 'Full Analysis'
        : 'Quick Analysis';
  }

  List<Widget> _buildAppBarActions() {
    bool isFinished = false;
    VoidCallback? viewResults;

    if (mounted) {
      if (analysisType == AnalysisType.full &&
          _fullAnalysisKey.currentState != null) {
        isFinished = _fullAnalysisKey.currentState!.isAnalysisFinished();
        viewResults = _fullAnalysisKey.currentState!._viewResults;
      } else if (analysisType == AnalysisType.quick &&
          _quickAnalysisKey.currentState != null) {
        isFinished = _quickAnalysisKey.currentState!.isAnalysisFinished();
        viewResults = _quickAnalysisKey.currentState!._viewResults;
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
    if (_controller?.value.isInitialized ?? false) {
      switch (analysisType) {
        case AnalysisType.full:
          return _FullAnalysisUI(
            key: _fullAnalysisKey,
            controller: _controller!,
            event: _currentEvent!,
            onStateChanged: _onChildStateChanged, // FIX: Pass the callback down
            appUser: widget.appUser,
          );
        case AnalysisType.quick:
          return _QuickAnalysisUI(
            key: _quickAnalysisKey,
            controller: _controller!,
            event: _currentEvent!,
            onStateChanged: _onChildStateChanged, // FIX: Pass the callback down
            appUser: widget.appUser,
          );
        default:
          return _buildInitialPrompt();
      }
    }
    return _isLoadingVideo ? _buildLoadingIndicator() : _buildInitialPrompt();
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
    if (_controller == null) {
      return FloatingActionButton.extended(
        onPressed: _isLoadingVideo ? null : _pickVideo,
        label: const Text('Load Video'),
        icon: const Icon(Icons.video_library),
      );
    }
    return null;
  }
}

// BASE CLASS FOR SHARED UI AND LOGIC
abstract class _AnalysisUIBaseState<T extends StatefulWidget> extends State<T> {
  late final VideoPlayerController controller;
  late final Event event;

  // FIX: Add a property to hold the callback
  late final VoidCallback onStateChanged;

  final List<RaceSegment> recordedSegments = [];
  int currentCheckPointIndex = 0;
  List<GlobalKey> checkpointKeys = [];
  bool isScrubbing = false;
  bool isSlowMotion = false;
  late final ScrollController scrubberScrollController;
  static const double pixelsPerSecond = 200.0;

  @override
  void initState() {
    super.initState();
    scrubberScrollController = ScrollController();
    controller = _getControllerFromWidget();
    event = _getEventFromWidget();
    // FIX: Initialize the callback from the widget
    onStateChanged = _getOnStateChangedCallback();
    controller.addListener(_videoListener);
    resetAnalysisState();
  }

  @override
  void dispose() {
    controller.removeListener(_videoListener);
    scrubberScrollController.dispose();
    super.dispose();
  }

  // Abstract methods for subclasses
  VideoPlayerController _getControllerFromWidget();

  Event _getEventFromWidget();

  // FIX: Add abstract method to get the callback
  VoidCallback _getOnStateChangedCallback();

  void resetAnalysisState();

  bool isAnalysisFinished() {
    return recordedSegments.length >= event.checkPoints.length;
  }

  void _videoListener() {
    if (isScrubbing || !scrubberScrollController.hasClients) return;
    final videoPosition = controller.value.position;
    final scrollPosition =
        videoPosition.inMilliseconds / 1000.0 * pixelsPerSecond;
    scrubberScrollController.jumpTo(scrollPosition);
  }

  void recordCheckpoint() {
    HapticFeedback.mediumImpact();
    final position = controller.value.position;
    final nextCheckPoint = event.checkPoints[currentCheckPointIndex];

    setState(() {
      recordedSegments.add(RaceSegment(
          checkPoint: nextCheckPoint, splitTimeOfTotalRace: position));
      if (currentCheckPointIndex < event.checkPoints.length - 1) {
        currentCheckPointIndex++;

        if (currentCheckPointIndex >= 3) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final keyToScrollTo = checkpointKeys[currentCheckPointIndex - 1];
            final context = keyToScrollTo.currentContext;
            if (context != null) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: 0.5,
              );
            }
          });
        }
      }
      // FIX: Call the parent's callback to notify it of a state change.
      onStateChanged();
    });
  }

  void rewindAndUndo() {
    if (recordedSegments.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      recordedSegments.removeLast();
      if (currentCheckPointIndex > 0) {
        currentCheckPointIndex--;
      }
      // FIX: Call the parent's callback to notify it of a state change.
      onStateChanged();
    });
    final newPosition = controller.value.position - const Duration(seconds: 5);
    controller.seekTo(newPosition.isNegative ? Duration.zero : newPosition);
  }

  // ... rest of _AnalysisUIBaseState remains the same
  void toggleSlowMotion() {
    HapticFeedback.lightImpact();
    setState(() {
      isSlowMotion = !isSlowMotion;
      controller.setPlaybackSpeed(isSlowMotion ? 0.5 : 1.0);
    });
  }

  String formatScrubberDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Widget buildPrecisionScrubber() {
    final totalDuration = controller.value.duration;
    final timelineWidth =
        (totalDuration.inMilliseconds / 1000.0) * pixelsPerSecond;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          setState(() => isScrubbing = true);
          controller.pause();
        } else if (notification is ScrollUpdateNotification && isScrubbing) {
          final newPosition = Duration(
              milliseconds:
                  (notification.metrics.pixels / pixelsPerSecond * 1000)
                      .round());
          controller.seekTo(newPosition);
        } else if (notification is ScrollEndNotification && isScrubbing) {
          setState(() => isScrubbing = false);
        }
        return true;
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: 60,
            child: SingleChildScrollView(
              controller: scrubberScrollController,
              scrollDirection: Axis.horizontal,
              child: CustomPaint(
                painter: TimelinePainter(
                  totalDuration: totalDuration,
                  pixelsPerSecond: pixelsPerSecond,
                  formatDuration: formatScrubberDuration,
                ),
                size: Size(timelineWidth, 50),
              ),
            ),
          ),
          Container(width: 2, height: 60, color: Colors.red),
        ],
      ),
    );
  }

  Widget buildCheckpointGuide() {
    final colorScheme = Theme.of(context).colorScheme;
    List<Widget> guideItems = [];

    for (int i = 0; i < event.checkPoints.length; i++) {
      final cp = event.checkPoints[i];
      final isCurrent = i == currentCheckPointIndex;
      final isDone = i < currentCheckPointIndex;

      guideItems.add(
        Padding(
          key: checkpointKeys.length > i ? checkpointKeys[i] : null,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(getDistanceForCheckpoint(cp, i),
                  style: TextStyle(
                      color: isCurrent ? colorScheme.primary : Colors.white,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11)),
              const SizedBox(height: 4),
              Icon(
                  isDone
                      ? Icons.check_circle
                      : (isCurrent
                          ? Icons.flag_circle_rounded
                          : Icons.circle_outlined),
                  color: isDone
                      ? Colors.green.shade400
                      : (isCurrent ? colorScheme.primary : Colors.white54),
                  size: 20),
            ],
          ),
        ),
      );

      if (i < event.checkPoints.length - 1) {
        guideItems.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Divider(
                  color: isDone ? Colors.green.shade400 : Colors.white30,
                  thickness: 1.5),
            ),
          ),
        );
      }
    }
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(child: Row(children: guideItems)));
  }

  String getDistanceForCheckpoint(CheckPoint cp, int index) {
    int turnCount = 0;
    for (int i = 0; i < index; i++) {
      if (event.checkPoints[i] == CheckPoint.turn) {
        turnCount++;
      }
    }
    final lapLength = event.poolLength.distance;
    switch (cp) {
      case CheckPoint.start:
        return '0m';
      case CheckPoint.offTheBlock:
        return 'Off Block';
      case CheckPoint.breakOut:
        return 'Breakout';
      case CheckPoint.fifteenMeterMark:
        return '${turnCount * lapLength + 15}m';
      case CheckPoint.turn:
        return '${(turnCount + 1) * lapLength}m';
      case CheckPoint.finish:
        return '${event.distance}m';
    }
  }

  Widget buildTransportControls() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
                icon: const Icon(Icons.fast_rewind),
                iconSize: 32,
                color: Colors.white,
                onPressed: () => controller
                    .seekTo(value.position - const Duration(seconds: 2))),
            IconButton(
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                iconSize: 48,
                color: Colors.white,
                onPressed: () =>
                    value.isPlaying ? controller.pause() : controller.play()),
            IconButton(
                icon: const Icon(Icons.fast_forward),
                iconSize: 32,
                color: Colors.white,
                onPressed: () => controller
                    .seekTo(value.position + const Duration(seconds: 2))),
          ],
        );
      },
    );
  }
}

// FULL ANALYSIS UI
class _FullAnalysisUI extends StatefulWidget {
  final VideoPlayerController controller;
  final Event event;
  final AppUser appUser;

  // FIX: Add the callback property
  final VoidCallback onStateChanged;

  const _FullAnalysisUI({
    super.key,
    required this.controller,
    required this.event,
    required this.onStateChanged, // FIX: Make it required
    required this.appUser,
  });

  @override
  State<_FullAnalysisUI> createState() => _FullAnalysisUIState();
}

class _FullAnalysisUIState extends _AnalysisUIBaseState<_FullAnalysisUI> {
  // ... existing properties
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        Expanded(child: _buildControlsOverlay()),
      ],
    );
  }

  void _viewResults() {
    controller.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RaceResultsView(
          recordedSegments: recordedSegments,
          intervalAttributes: _intervalAttributes,
          event: widget.event,
          analysisType: AnalysisType.full,
          appUser: widget.appUser
        ),
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
            IconButton(onPressed: ()=>seekFrames(isForward: false, controller: controller), icon: Icon(Icons.arrow_back_outlined)),
            Expanded(child: buildPrecisionScrubber()),
            IconButton(onPressed: ()=>seekFrames(isForward: true, controller: controller), icon: Icon(Icons.arrow_forward_outlined)),
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

// QUICK ANALYSIS UI
class _QuickAnalysisUI extends StatefulWidget {
  final VideoPlayerController controller;
  final Event event;
  final AppUser appUser;

  // FIX: Add the callback property
  final VoidCallback onStateChanged;

  const _QuickAnalysisUI({
    super.key,
    required this.controller,
    required this.event,
    required this.onStateChanged, required this.appUser, // FIX: Make it required
  });

  @override
  State<_QuickAnalysisUI> createState() => _QuickAnalysisUIState();
}

class _QuickAnalysisUIState extends _AnalysisUIBaseState<_QuickAnalysisUI> {
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

  void _viewResults() {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
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

Future<void> seekFrames({required bool isForward, required VideoPlayerController controller}) async {
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