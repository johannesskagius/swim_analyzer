// BASE CLASS FOR SHARED UI AND LOGIC
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swim_analyzer/analysis/time_line_painter.dart';
import 'package:swim_apps_shared/objects/race_segment.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:swim_apps_shared/swim_session/events/checkpoint.dart';
import 'package:swim_apps_shared/swim_session/events/event.dart';
import 'package:video_player/video_player.dart';

abstract class AnalysisUIBaseState<T extends StatefulWidget> extends State<T> {
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