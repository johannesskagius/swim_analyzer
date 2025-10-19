import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:swim_analyzer/analysis/time_line_painter.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:video_player/video_player.dart';

import 'measurement_painter.dart';
import 'off_the_block_enums.dart';
import 'off_the_block_result.dart';



class OffTheBlockAnalysisPage extends StatefulWidget {
  final AppUser appUser;

  const OffTheBlockAnalysisPage({super.key, required this.appUser});

  @override
  State<OffTheBlockAnalysisPage> createState() =>
      _OffTheBlockAnalysisPageState();
}

class _OffTheBlockAnalysisPageState extends State<OffTheBlockAnalysisPage> {
  final double startHeight = 0.75; //Todo set this in settings
  bool _isLoading = false;
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();

  final Map<OffTheBlockEvent, Duration> _markedTimestamps = {};
  final _startDistanceController = TextEditingController();

  // State for the precision scrubber
  late final ScrollController _scrubberScrollController;
  bool _isScrubbing = false;
  static const double _pixelsPerSecond = 150.0;

  // Controller for the zoomable video viewer.
  final TransformationController _transformationController =
      TransformationController();

  // State for the measurement feature
  bool _isMeasuring = false;
  int _measurementStep = 0;
  final List<Offset> _measurementPoints = [];
  int? _draggedPointIndex;
  bool _isPointDragInProgress = false;

  @override
  void initState() {
    super.initState();
    _scrubberScrollController = ScrollController();
  }



  // ### NEW METHOD: Calculates jump physics based on user input ###
  Map<String, double>? _calculateJumpPhysics() {
    // 1. --- GATHER AND VALIDATE INPUTS ---
    final startDistanceText = _startDistanceController.text;
    final leftBlockTime = _markedTimestamps[OffTheBlockEvent.leftBlock];
    final touchedWaterTime = _markedTimestamps[OffTheBlockEvent.touchedWater];

    // Ensure all required data is present
    if (startDistanceText.isEmpty ||
        leftBlockTime == null ||
        touchedWaterTime == null) {
      return null;
    }

    // Use tryParse for safe number conversion
    final double? horizontalDistance = double.tryParse(startDistanceText);

    if (horizontalDistance == null) {
      return null;
    }

    // Calculate flight time in seconds
    final flightTime =
        (touchedWaterTime.inMilliseconds - leftBlockTime.inMilliseconds) /
            1000.0;

    // Flight time must be positive
    if (flightTime <= 0) {
      return null;
    }

    // 2. --- PERFORM PHYSICS CALCULATIONS ---
    const double g = 9.81; // Gravity in m/s^2

    // Vx = d / t (Horizontal velocity is constant)
    final double velocityX = horizontalDistance / flightTime;

    // From the equation: displacement_y = Vi*t + 0.5*a*t^2
    // We solve for initial vertical velocity (Vi):
    // -startHeight = (initialVerticalVelocity * flightTime) - (0.5 * g * flightTime^2)
    final double initialVerticalVelocity =
        (0.5 * g * flightTime * flightTime - startHeight) / flightTime;

    // The peak height of the jump (above the block) occurs when vertical velocity is 0.
    // From the equation: Vf^2 = Vi^2 + 2*a*d
    // 0 = initialVerticalVelocity^2 - 2 * g * jumpHeight
    final double jumpHeight =
        (initialVerticalVelocity * initialVerticalVelocity) / (2 * g);

    // Final vertical velocity at water entry.
    // Vf = Vi + a*t
    final double finalVerticalVelocity =
        initialVerticalVelocity - (g * flightTime);

    // 3. --- RETURN RESULTS ---
    return {
      'jumpHeight': jumpHeight,
      'entryVelocityX': velocityX,
      'entryVelocityY': finalVerticalVelocity,
    };
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _scrubberScrollController.dispose();
    _startDistanceController.dispose();
    super.dispose();
  }

  void _videoListener() {
    if (mounted && !_isScrubbing && _controller != null) {
      final newScrollOffset = _controller!.value.position.inMilliseconds /
          1000.0 *
          _pixelsPerSecond;
      _scrubberScrollController.animateTo(
        newScrollOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isLoading = true;
      _markedTimestamps.clear();
      _transformationController.value = Matrix4.identity();
    });

    try {
      final XFile? pickedFile =
          await _picker.pickVideo(source: ImageSource.gallery);

      if (pickedFile == null) {
        setState(() => _isLoading = false);
        return;
      }

      _controller?.removeListener(_videoListener);
      await _controller?.dispose();

      final newController = VideoPlayerController.file(File(pickedFile.path));
      await newController.initialize();

      if (!mounted) {
        await newController.dispose();
        return;
      }

      setState(() {
        _controller = newController;
        _controller!.addListener(_videoListener);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error during video picking/initialization: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load video: ${e.toString()}')));
      setState(() {
        _isLoading = false;
        _controller = null;
      });
    }
  }

  void _markEvent(OffTheBlockEvent event) {
    if (_controller == null) return;
    setState(() {
      _markedTimestamps[event] = _controller!.value.position;
    });
  }

  Future<void> _seekFrames({required bool isForward}) async {
    if (_controller == null) return;

    final currentPosition = _controller!.value.position;

    // Assume 30 FPS if not known
    const frameRate = 30.0;
    final frameDuration = Duration(milliseconds: (1000 / frameRate).round());
    final int frames = isForward ? 1 : -1;
    final newPosition = currentPosition + frameDuration * frames;

    await _controller!.seekTo(newPosition);
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    }
  }

  void _calculateResults() {
    // Call the new physics calculation method
    final Map<String, double>? jumpData = _calculateJumpPhysics();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OffTheBlockResultsPage(
          markedTimestamps: _markedTimestamps,
          startDistance: _startDistanceController.text,
          startHeight: startHeight,
          jumpData: jumpData,
          // Pass the new data to the results page
          appUser: widget.appUser,
        ),
      ),
    );
  }

  String _formatScrubberDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Off the Block Analysis"),
      ),
      body: Column(
        children: <Widget>[
          if (_isMeasuring)
            Container(
              color: Colors.blue.withAlpha(10),
              width: double.infinity,
              height: 110.0,
              // Fixed height to prevent layout shifts when content changes.
              alignment: Alignment.center,
              // Center the co
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _getMeasurementInstruction().isNotEmpty
                      ? Text(
                          _getMeasurementInstruction(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        )
                      : const SizedBox.shrink(),
                  if (_measurementPoints.length == 6) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _calculateMeasuredDistance(showSnackbar: true),
                      icon: const Icon(Icons.straighten),
                      label: const Text('Calculate Distance'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _controller == null
                      ? _buildVideoSelectionPrompt()
                      : _buildVideoPlayer(),
            ),
          ),
          if (_controller != null && !_isLoading)
            Expanded(
              flex: 3,
              child: _buildMarkingInterface(),
            ),
          if (!_isLoading) _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildVideoSelectionPrompt() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.video_library_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('Please select a video of a start to begin.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
          ],
        ),
      );

  // ### Refactored Video Player with stable measurement gestures ###
  Widget _buildVideoPlayer() {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1.0,
      maxScale: 8.0,
      panEnabled: !_isMeasuring,
      scaleEnabled: !_isMeasuring,
      // Let the GestureDetector below handle all interactions during measurement.
      onInteractionStart: null,
      onInteractionUpdate: null,
      onInteractionEnd: null,
      child: GestureDetector(
        onTapUp: (details) {
          if (!_isMeasuring ||
              _isPointDragInProgress ||
              _measurementPoints.length >= 6) return;

          final sceneOffset =
              _transformationController.toScene(details.localPosition);
          // Don't add a point if tapping on an existing handle
          for (int i = 0; i < _measurementPoints.length; i++) {
            final handleCenter = _measurementPoints[i] +
                const Offset(0, MeasurementPainter.handleYOffset);
            if ((sceneOffset - handleCenter).distance <
                MeasurementPainter.handleTouchRadius) {
              return;
            }
          }
          setState(() {
            _measurementPoints.add(sceneOffset);
            _measurementStep++;
          });
        },
        onPanStart: (details) {
          if (!_isMeasuring) return;
          final sceneOffset =
              _transformationController.toScene(details.localPosition);
          int? hitIndex;
          // Check if the pan started on a handle (in reverse order for Z-index)
          for (int i = _measurementPoints.length - 1; i >= 0; i--) {
            final handleCenter = _measurementPoints[i] +
                const Offset(0, MeasurementPainter.handleYOffset);
            if ((sceneOffset - handleCenter).distance <
                MeasurementPainter.handleTouchRadius) {
              hitIndex = i;
              break;
            }
          }
          if (hitIndex != null) {
            setState(() {
              _draggedPointIndex = hitIndex;
              _isPointDragInProgress = true;
            });
          }
        },
        onPanUpdate: (details) {
          if (!_isPointDragInProgress || _draggedPointIndex == null) return;
          final sceneOffset =
              _transformationController.toScene(details.localPosition);
          setState(() {
            _measurementPoints[_draggedPointIndex!] =
                sceneOffset - const Offset(0, MeasurementPainter.handleYOffset);
          });
        },
        onPanEnd: (details) {
          if (!_isPointDragInProgress) return;
          setState(() {
            _draggedPointIndex = null;
            _isPointDragInProgress = false;
          });
        },
        // --- END GESTURE HANDLING ---
        onDoubleTap: () {
          // Allow double-tap to reset zoom only when NOT measuring.
          if (!_isMeasuring) {
            _transformationController.value = Matrix4.identity();
          }
        },
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                VideoPlayer(_controller!),
                if (_isMeasuring)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: MeasurementPainter(
                        points: _measurementPoints,
                        selectedPointIndex: _draggedPointIndex,
                      ),
                    ),
                  ),
                if (!_isMeasuring) _ControlsOverlay(controller: _controller!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarkingInterface() {
    final textTheme = Theme.of(context).textTheme;
    return AbsorbPointer(
      absorbing: _isMeasuring,
      child: Opacity(
        opacity: _isMeasuring ? 0.5 : 1.0,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPrecisionScrubber(),
                const Divider(height: 24),
                Text('Mark Key Events',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...OffTheBlockEvent.values
                    .map((event) => _buildEventMarkerTile(event)),
                const Divider(height: 24),
                Text('Optional Stats',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildOptionalStatsFields(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrecisionScrubber() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final totalDuration = _controller!.value.duration;
    final timelineWidth =
        (totalDuration.inMilliseconds / 1000.0) * _pixelsPerSecond;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => _seekFrames(isForward: false),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                setState(() => _isScrubbing = true);
                _controller!.pause();
              } else if (notification is ScrollUpdateNotification &&
                  _isScrubbing) {
                final newPosition = Duration(
                    milliseconds:
                        (notification.metrics.pixels / _pixelsPerSecond * 1000)
                            .round());
                _controller!.seekTo(newPosition);
              } else if (notification is ScrollEndNotification &&
                  _isScrubbing) {
                setState(() => _isScrubbing = false);
              }
              return true;
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 60,
                  child: SingleChildScrollView(
                    controller: _scrubberScrollController,
                    scrollDirection: Axis.horizontal,
                    child: CustomPaint(
                      painter: TimelinePainter(
                        totalDuration: totalDuration,
                        pixelsPerSecond: _pixelsPerSecond,
                        formatDuration: _formatScrubberDuration,
                      ),
                      size: Size(timelineWidth, 50),
                    ),
                  ),
                ),
                Container(width: 2, height: 60, color: Colors.red),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward_outlined),
          onPressed: () => _seekFrames(isForward: true),
        ),
      ],
    );
  }

  Widget _buildEventMarkerTile(OffTheBlockEvent event) {
    final markedTime = _markedTimestamps[event];
    final startSignalTime = _markedTimestamps[OffTheBlockEvent.startSignal];

    String timeText;
    if (markedTime != null) {
      if (startSignalTime != null) {
        final relativeTime = markedTime - startSignalTime;
        timeText =
            '${(relativeTime.inMilliseconds / 1000.0).toStringAsFixed(2)}s';
      } else {
        timeText =
            '${(markedTime.inMilliseconds / 1000.0).toStringAsFixed(2)}s (absolute)';
      }
    } else {
      timeText = 'Not marked';
    }

    return ListTile(
      title: Text(event.displayName),
      subtitle: Text(
        timeText,
        style:
            TextStyle(color: markedTime != null ? Colors.green : Colors.grey),
      ),
      trailing: ElevatedButton(
        onPressed: () => _markEvent(event),
        child: const Text('Mark'),
      ),
      dense: true,
    );
  }

  Widget _buildOptionalStatsFields() => Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _startDistanceController,
                  decoration: const InputDecoration(
                    labelText: 'Start Distance (m)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _controller != null
                    ? () {
                        setState(() {
                          if (_isMeasuring) {
                            _isMeasuring = false;
                            _measurementPoints.clear();
                            _measurementStep = 0;
                            _draggedPointIndex = null;
                            _isPointDragInProgress = false;
                          } else {
                            // When entering measurement mode:
                            _isMeasuring = true;
                            _transformationController.value =
                                Matrix4.identity(); // Reset zoom
                            _controller?.pause();
                          }
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 8)),
                child: Text(_isMeasuring ? 'Cancel' : 'Measure'),
              ),
            ],
          ),
        ],
      );

  String _getMeasurementInstruction() {
    if (_draggedPointIndex != null) {
      return 'Drag the handle to reposition the point';
    }
    switch (_measurementStep) {
      case 0:
        return '1/6: Tap start of 5m marker on LEFT lane rope';
      case 1:
        return '2/6: Tap end of 5m marker on LEFT lane rope';
      case 2:
        return '3/6: Tap start of 5m marker on RIGHT lane rope';
      case 3:
        return '4/6: Tap end of 5m marker on RIGHT lane rope';
      case 4:
        return '5/6: Tap the edge of the start block';
      case 5:
        return "6/6: Tap where the swimmer enters the water";
      default:
        return "";
    }
  }

  void _calculateMeasuredDistance({bool showSnackbar = true}) {
    if (_measurementPoints.length < 6) return;

    final ref1A = _measurementPoints[0];
    final ref1B = _measurementPoints[1];
    final ref2A = _measurementPoints[2];
    final ref2B = _measurementPoints[3];
    final start = _measurementPoints[4];
    final end = _measurementPoints[5];

    // Ensure reference lines have length
    if ((ref1A - ref1B).distance == 0 || (ref2A - ref2B).distance == 0) {
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error: A 5m reference line has zero length.')),
        );
      }
      return;
    }

    final pixelsPerMeter1 = (ref1A - ref1B).distance / 5.0;
    final pixelsPerMeter2 = (ref2A - ref2B).distance / 5.0;

    // Find the closest point on each reference line segment to the midpoint of the measured line
    final measuredMidpoint =
        Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

    final t1 = _getClosestPointOnSegment(measuredMidpoint, ref1A, ref1B);
    final t2 = _getClosestPointOnSegment(measuredMidpoint, ref2A, ref2B);

    final p1 = ref1A + (ref1B - ref1A) * t1;
    final p2 = ref2A + (ref2B - ref2A) * t2;

    // Find how far the measured line is between the two reference lines
    final totalDist = (p1 - p2).distance;
    if (totalDist < 1e-6) {
      // Avoid division by zero if lines are on top of each other
      final measuredMeters = (start - end).distance / pixelsPerMeter1;
      _updateDistance(measuredMeters, showSnackbar);
      return;
    }

    final distToP1 = (measuredMidpoint - p1).distance;
    final ratio = distToP1 / totalDist;

    // Interpolate the pixels-per-meter scale
    final interpolatedPixelsPerMeter =
        pixelsPerMeter1 + (pixelsPerMeter2 - pixelsPerMeter1) * ratio;

    if (interpolatedPixelsPerMeter == 0) return;

    final measuredMeters = (start - end).distance / interpolatedPixelsPerMeter;
    _updateDistance(measuredMeters, showSnackbar);
  }

  void _updateDistance(double measuredMeters, bool showSnackbar) {
    if (mounted) {
      setState(() {
        _startDistanceController.text = measuredMeters.toStringAsFixed(2);
      });
    }

    if (showSnackbar) {
      // Defer state change to avoid conflicts during build
      Future.delayed(Duration.zero, () {
        setState(() {
          _isMeasuring = false;
          _measurementPoints.clear();
          _measurementStep = 0;
          _draggedPointIndex = null;
          _isPointDragInProgress = false;
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Distance calculated: ${measuredMeters.toStringAsFixed(2)}m')),
      );
    }
  }

  // Helper to find the projection of a point onto a line segment
  double _getClosestPointOnSegment(Offset p, Offset a, Offset b) {
    final ap = p - a;
    final ab = b - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 == 0) return 0.0;
    final ap_dot_ab = ap.dx * ab.dx + ap.dy * ab.dy;
    final t = ap_dot_ab / ab2;
    return t.clamp(0.0, 1.0); // Clamp to the segment
  }

  Widget _buildActionButtons() {
    final allEventsMarked = OffTheBlockEvent.values
        .every((event) => _markedTimestamps.containsKey(event));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_library),
            label: Text(_controller == null
                ? 'Select Video'
                : 'Select Different Video'),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed:
                _controller?.value.isInitialized == true && allEventsMarked
                    ? _calculateResults
                    : null,
            icon: const Icon(Icons.analytics),
            label: const Text('Calculate Results'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final bool showPlayIcon = !controller.value.isPlaying &&
              controller.value.position == Duration.zero;

          if (showPlayIcon) {
            return Container(
              color: Colors.black26,
              child: const Center(
                child: Icon(Icons.play_arrow,
                    color: Colors.white, size: 100.0, semanticLabel: 'Play'),
              ),
            );
          } else {
            return const SizedBox.shrink();
          }
        },
      ),
    );
  }
}
