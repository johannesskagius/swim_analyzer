import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imgLib;
import 'package:image_picker/image_picker.dart';
import 'package:swim_analyzer/analysis/start/start_analysis_controls_overlay.dart';
import 'package:swim_analyzer/analysis/time_line_painter.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

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
  bool _isDetecting = false;

  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();

  final Map<OffTheBlockEvent, Duration> _markedTimestamps = {};
  final _startDistanceController = TextEditingController();

  late final ScrollController _scrubberScrollController;
  bool _isScrubbing = false;
  static const double _pixelsPerSecond = 150.0;

  final TransformationController _transformationController =
  TransformationController();

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

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _scrubberScrollController.dispose();
    _startDistanceController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 🧠 AI DETECTION LOGIC
  // --------------------------------------------------------------------------
  Future<void> _runAIDetection() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isDetecting = true);

    try {
      await _controller!.pause();

      // 1️⃣ Extract a frame at the current position
      final positionMs = _controller!.value.position.inMilliseconds;
      final videoPath = _controller!.dataSource.replaceAll('file://', '');
      final thumb = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: positionMs,
        quality: 100,
      );
      if (thumb == null) throw Exception('No frame extracted');

      // 2️⃣ Prepare tensor input
      final input = _imgToByteListFloat32(thumb, 128, 128);
      final interpreter = await Interpreter.fromAsset(
          'assets/models/detect_5m_marks_v5.tflite');

      // ⚙️ Updated for 8 outputs (v5 model)
      final output = List.filled(8, 0.0).reshape([1, 8]);
      interpreter.run(input.reshape([1, 128, 128, 3]), output);
      final result = output[0]; // [Lx1, Ly1, Lx2, Ly2, Rx1, Ry1, Rx2, Ry2]

      final videoSize = _controller!.value.size;
      final videoWidth = videoSize.width;
      final videoHeight = videoSize.height;

      debugPrint(
          'Real video frame: ${videoWidth.toStringAsFixed(0)}×${videoHeight.toStringAsFixed(0)}');
      debugPrint('AI raw output: $result');

      // 3️⃣ Detect coordinate scale (normalized 0–1 vs absolute)
      final normalized = result.every((v) => v >= 0.0 && v <= 1.0);
      final scaleX = normalized ? videoWidth : videoWidth / 128.0;
      final scaleY = normalized ? videoHeight : videoHeight / 128.0;

      // 4️⃣ Convert AI coords to pixel space
      final leftStart = Offset(result[0] * scaleX, result[1] * scaleY);
      final leftEnd = Offset(result[2] * scaleX, result[3] * scaleY);
      final rightStart = Offset(result[4] * scaleX, result[5] * scaleY);
      final rightEnd = Offset(result[6] * scaleX, result[7] * scaleY);

      // 5️⃣ Log outputs
      debugPrint('Left lane:  $leftStart → $leftEnd');
      debugPrint('Right lane: $rightStart → $rightEnd');

      // 6️⃣ Compute span and perspective info
      final leftLengthPx = (leftStart - leftEnd).distance;
      final rightLengthPx = (rightStart - rightEnd).distance;
      final avgPpm = ((leftLengthPx / 5.0) + (rightLengthPx / 5.0)) / 2.0;

      debugPrint('Pixels per meter ≈ ${avgPpm.toStringAsFixed(1)}');

      // 7️⃣ Update overlay points - CORRECTED for screen padding
      final displayWidth = MediaQuery.of(context).size.width - 32.0;
      final displayHeight = displayWidth / _controller!.value.aspectRatio;

      double scaleDisplayX = displayWidth / videoWidth;
      double scaleDisplayY = displayHeight / videoHeight;

      final leftStartDisplay =
      Offset(leftStart.dx * scaleDisplayX, leftStart.dy * scaleDisplayY);
      final leftEndDisplay =
      Offset(leftEnd.dx * scaleDisplayX, leftEnd.dy * scaleDisplayY);
      final rightStartDisplay =
      Offset(rightStart.dx * scaleDisplayX, rightStart.dy * scaleDisplayY);
      final rightEndDisplay =
      Offset(rightEnd.dx * scaleDisplayX, rightEnd.dy * scaleDisplayY);

      setState(() {
        _measurementPoints
          ..clear()
          ..addAll([
            leftStartDisplay,
            leftEndDisplay,
            rightStartDisplay,
            rightEndDisplay,
          ]);
        _measurementStep = 4; // Ready for auto-calc

        // --- AUTO-ADD START BLOCK POINT ---
        final autoY =
            (leftStartDisplay.dy + rightStartDisplay.dy) / 2.0;
        final autoX =
            (leftStartDisplay.dx + rightStartDisplay.dx) / 2.0;

        _measurementPoints.add(Offset(autoX, autoY)); // This is points[4]
        _measurementStep = 5; // Ready for final tap
      });

      // 8️⃣ Show a brief summary
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            'AI detected 2 lanes | ${avgPpm.toStringAsFixed(1)} px/m',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('AI detection failed: $e $st');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('AI detection failed: $e')));
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Float32List _imgToByteListFloat32(Uint8List bytes, int w, int h) {
    final img = imgLib.decodeImage(bytes)!;
    final resized = imgLib.copyResize(img, width: w, height: h);

    final buffer = Float32List(w * h * 3);
    int i = 0;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = resized.getPixel(x, y);

        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        buffer[i++] = r / 255.0;
        buffer[i++] = g / 255.0;
        buffer[i++] = b / 255.0;
      }
    }

    return buffer;
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

  void _markEvent(OffTheBlockEvent event) {
    if (_controller == null) return;
    setState(() {
      _markedTimestamps[event] = _controller!.value.position;
    });
  }

  Future<void> _seekFrames({required bool isForward}) async {
    if (_controller == null) return;

    final currentPosition = _controller!.value.position;
    const frameRate = 30.0;
    final frameDuration = Duration(milliseconds: (1000 / frameRate).round());
    final int frames = isForward ? 1 : -1;
    final newPosition = currentPosition + frameDuration * frames;

    await _controller!.seekTo(newPosition);
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    }
  }

  String _getMeasurementInstruction() {
    if (_draggedPointIndex != null) {
      if (_draggedPointIndex! < 4) {
        return 'Drag the handle to reposition the point'; // Lane marks
      }
      // This is now index 5, the Water (Entry) point
      return 'Drag to set position (free movement)';
    }
    switch (_measurementStep) {
      case 0:
        return '1/5: Tap start of the closet lane rope';
      case 1:
        return '2/5: Tap 5m mark of the closet lane rope';
      case 2:
        return '3/5: Tap start of the furthest lane rope';
      case 3:
        return '4/5: Tap 5m mark of the furthest lane rope';
      case 4:
      // This step is now skipped as Start (Block) is auto-added
        return 'Calculating block position...';
      case 5:
        return '5/5: Tap where swimmer ENTERS THE WATER (free tap)';
      default:
        return "Use the handles to adjust the points.";
    }
  }

  void _calculateResults() {
    final Map<String, double>? jumpData = _calculateJumpPhysics();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OffTheBlockResultsPage(
          markedTimestamps: _markedTimestamps,
          startDistance: _startDistanceController.text,
          startHeight: startHeight,
          jumpData: jumpData,
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

  // --------------------------------------------------------------------------
  // 🧠 AI & MEASUREMENT HELPERS (NEW)
  // --------------------------------------------------------------------------


  // --- DELETED _getExtrapolatedLaneBoundaries and _getCenterlineX ---
  // They are no longer needed for the new logic.

  Widget _buildVideoSelectionPrompt() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.video_library_outlined, size: 80, color: Colors.grey),
        SizedBox(height: 16),
        Text(
          'Please select a video of a start to begin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      ],
    ),
  );

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

  Widget _buildVideoPlayer() {
    final previewMeters = _previewJumpMeters();

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1.0,
      maxScale: 8.0,
      panEnabled: !_isMeasuring,
      scaleEnabled: !_isMeasuring,
      onInteractionStart: null,
      onInteractionUpdate: null,
      onInteractionEnd: null,
      child: GestureDetector(
        onTapUp: (details) {
          print('MeasurementStep: $_measurementStep');
          print('MeasurementPoints length: ${_measurementPoints.length}');
          // 1. Check guards
          if (!_isMeasuring ||
              _isPointDragInProgress ||
              _measurementPoints.length >= 6) {
            return;
          }

          // 2. Get tap position in scene coordinates
          final sceneOffset =
          _transformationController.toScene(details.localPosition);

          // 3. Check for handle tap (to prevent adding a new point)
          // --- FIX: Define a larger, more generous touch radius for grabbing handles ---
          const double largerHandleTouchRadius = 30.0;

          for (int i = 0; i < _measurementPoints.length; i++) {
            // Special case: DON'T allow tapping handle 4
            if (i == 4) continue;

            final handleCenter = _measurementPoints[i] +
                const Offset(0, MeasurementPainter.handleYOffset);

            // --- FIX: Use the larger touch radius ---
            if ((sceneOffset - handleCenter).distance <
                largerHandleTouchRadius) {
              return; // User tapped a handle, do nothing.
            }
          }

          // 4. Determine the new point's position
          if (_measurementStep < 3) {
            // --- LOGIC FOR LANE MARKS (Steps 0, 1, 2) ---
            setState(() {
              _measurementPoints.add(sceneOffset);
              _measurementStep++;
            });
          } else if (_measurementStep == 3) {
            // --- LOGIC FOR 4th LANE MARK (Step 3) ---
            setState(() {
              _measurementPoints.add(sceneOffset); // This is points[3]
              _measurementStep = 4; // Step is now 4

              // --- AUTO-ADD START BLOCK POINT ---
              final p0 = _measurementPoints[0];
              final p2 = _measurementPoints[2];
              final autoY = (p0.dy + p2.dy) / 2.0;
              final autoX = (p0.dx + p2.dx) / 2.0;

              _measurementPoints.add(Offset(autoX, autoY)); // This is points[4]
              _measurementStep = 5; // Step is now 5
            });
          } else if (_measurementStep == 5) {
            // --- LOGIC FOR WATER (ENTRY) (Step 5) ---
            setState(() {
              _measurementPoints.add(sceneOffset); // This is points[5]
              _measurementStep = 6; // Step is now 6 (locked)
            });
          }
        },
        onPanStart: (details) {
          if (!_isMeasuring) return;
          final sceneOffset =
          _transformationController.toScene(details.localPosition);
          int? hitIndex;

          // --- FIX: Define a larger, more generous touch radius for grabbing handles ---
          const double largerHandleTouchRadius = 30.0;

          // Check all points EXCEPT index 4 (auto-point)
          for (int i = _measurementPoints.length - 1; i >= 0; i--) {
            if (i == 4) {
              //_measurementStep++;
              continue; // skip auto point
            }

            // --- FIX ---
            // The original code was not checking the handle's visual position.
            // This logic now matches the handle's *actual* centered position
            // (using the Y offset) and uses the larger, forgiving touch radius.
            final handleCenter = _measurementPoints[i] +
                const Offset(0, MeasurementPainter.handleYOffset);

            if ((sceneOffset - handleCenter).distance < largerHandleTouchRadius) {
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

          // We've already guarded against _draggedPointIndex being 4 in onPanStart,
          // so we only need one logic path.

          final sceneOffset =
          _transformationController.toScene(details.localPosition);
          final handleOffset = const Offset(0, MeasurementPainter.handleYOffset);

          Offset newPointPosition = sceneOffset - handleOffset;

          setState(() {
            _measurementPoints[_draggedPointIndex!] = newPointPosition;
          });
        },
        onPanEnd: (details) {
          if (!_isPointDragInProgress) return;
          setState(() {
            _draggedPointIndex = null;
            _isPointDragInProgress = false;
          });
        },
        onDoubleTap: () {
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
                if (_isMeasuring && _measurementPoints.length >= 4)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _JumpOverlayPainter(
                        points: _measurementPoints,
                        previewMeters: previewMeters,
                      ),
                    ),
                  ),
                if (!_isMeasuring) ControlsOverlay(controller: _controller!),
              ],
            ),
          ),
        ),
      ),
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

      if (!mounted) return;

      setState(() {
        _controller = newController;
        _controller!.addListener(_videoListener);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading video: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load video: $e')));
      setState(() {
        _isLoading = false;
        _controller = null;
      });
    }
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
                ? () async {
              if (_isMeasuring) {
                setState(() {
                  _isMeasuring = false;
                  _measurementPoints.clear();
                  _measurementStep = 0;
                  _draggedPointIndex = null;
                  _isPointDragInProgress = false;
                });
              } else {
                setState(() {
                  _isMeasuring = true;
                  _transformationController.value =
                      Matrix4.identity();
                });
                _controller?.pause();
                //await _runAIDetection();
              }
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

  Map<String, double>? _calculateJumpPhysics() {
    // --- Guard Clauses ---
    // Ensure necessary timestamps and measurement points exist
    if (_markedTimestamps[OffTheBlockEvent.leftBlock] == null ||
        _markedTimestamps[OffTheBlockEvent.touchedWater] == null ||
        _measurementPoints.length < 6) { // Need 6 points total now
      debugPrint("Calculation failed: Missing timestamps or measurement points.");
      return null;
    }

    // --- Input Data Extraction ---
    final Offset jumpStartPoint = _measurementPoints[4]; // Auto-calculated block edge
    final Offset waterEntry = _measurementPoints[5];     // User-tapped water entry
    final double flightTimeSeconds =
        (_markedTimestamps[OffTheBlockEvent.touchedWater]! -
            _markedTimestamps[OffTheBlockEvent.leftBlock]!)
            .inMilliseconds / 1000.0;

    // Avoid division by zero or nonsensical times
    if (flightTimeSeconds <= 0) {
      debugPrint("Calculation failed: Invalid flight time ($flightTimeSeconds s).");
      return null;
    }

    // --- Pixels Per Meter Calculation ---
    // Calculate PPM at the average Y depth of the 2D jump line
    final double jumpMidY = (jumpStartPoint.dy + waterEntry.dy) / 2.0;
    final ppmAtJumpDepth = _getPixelsPerMeterAtDepth(jumpMidY);
    if (ppmAtJumpDepth == null || ppmAtJumpDepth <= 0) {
      debugPrint("Calculation failed: Could not determine PPM at depth $jumpMidY.");
      return null;
    }

    // --- Core Metrics ---
    // Calculate 2D distance in pixels and meters
    final double jumpDistancePx = (waterEntry - jumpStartPoint).distance;
    final double jumpDistanceMeters = (jumpDistancePx / ppmAtJumpDepth)+0.15;

    // Calculate average horizontal velocity (constant vx, ignoring air resistance)
    final double horizontalVelocity = jumpDistanceMeters / flightTimeSeconds;

    // --- Vertical Motion Calculation ---
    const double gravity = 9.81; // m/s^2

    // Calculate initial vertical velocity (vy0) using standard kinematic equation:
    // y_final = y_initial + vy0*t + 0.5*a*t^2
    // 0 = startHeight + vy0*flightTimeSeconds - 0.5*gravity*flightTimeSeconds^2
    final double initialVerticalVelocity = (0.5 * gravity * math.pow(flightTimeSeconds, 2) - startHeight) / flightTimeSeconds;

    // --- Trajectory Peak Calculation (Corrected) ---
    double maxJumpHeight = 0.0;          // Height above block
    double timeToPeakHeight = 0.0;       // Time after leaving block
    double distanceToPeakHeight = 0.0;   // Horizontal distance from block

    // Only calculate a peak if the swimmer is initially moving UPWARDS (vy0 > 0)
    if (initialVerticalVelocity > 0) {
      // Time to peak (when vertical velocity becomes 0): t_peak = vy0 / g
      timeToPeakHeight = initialVerticalVelocity / gravity;
      // Calculate max height above water using: y_max = y0 + vy0*t_peak + 0.5*a*t_peak^2
      final maxHeightAboveWater = startHeight + initialVerticalVelocity * timeToPeakHeight - 0.5 * gravity * math.pow(timeToPeakHeight, 2);
      // Max height above block
      maxJumpHeight = maxHeightAboveWater - startHeight;
      // Horizontal distance covered to reach peak: d_peak = vx * t_peak
      distanceToPeakHeight = horizontalVelocity * timeToPeakHeight;
    }
    // Otherwise, the peak height *above the block* is 0, and time/distance to peak are 0.

    // --- Entry Velocity Calculation ---
    // Horizontal velocity at entry (vx remains constant)
    final double entryVelocityX = horizontalVelocity;
    // Vertical velocity at entry using: vy_final = vy0 + a*t
    final double entryVelocityY = initialVerticalVelocity - gravity * flightTimeSeconds;

    // --- Speed and Angle Calculations ---
    // Initial speed (magnitude of initial velocity vector)
    final double initialVelocityMagnitude = math.sqrt(math.pow(horizontalVelocity, 2) + math.pow(initialVerticalVelocity, 2));
    // Launch angle relative to horizontal (degrees)
    final double launchAngle = math.atan2(initialVerticalVelocity, horizontalVelocity) * (180 / math.pi); // Use atan2 for quadrant correctness
    // Entry speed (magnitude of entry velocity vector)
    final double entryVelocityMagnitude = math.sqrt(math.pow(entryVelocityX, 2) + math.pow(entryVelocityY, 2));
    // Entry angle relative to horizontal (degrees)
    final double entryAngleHorizontal = math.atan2(entryVelocityY, entryVelocityX) * (180 / math.pi); // Use atan2
    // Entry angle relative to water surface (degrees)
    final double entryAngleWater = 90.0 - entryAngleHorizontal.abs();


    // --- Result Map ---
    return {
      // Core Metrics
      'jumpDistance': jumpDistanceMeters,
      'flightTime': flightTimeSeconds,
      'maxJumpHeight': maxJumpHeight, // Corrected

      // Velocity Components
      'horizontalVelocity': horizontalVelocity,
      'initialVerticalVelocity': initialVerticalVelocity,
      'entryVelocityX': entryVelocityX,
      'entryVelocityY': entryVelocityY,

      // Magnitudes (Speed)
      'initialVelocityMagnitude': initialVelocityMagnitude,
      'entryVelocityMagnitude': entryVelocityMagnitude,

      // Angles (relative to horizontal/water)
      'launchAngle': launchAngle,
      'entryAngleHorizontal': entryAngleHorizontal,
      'entryAngleWater': entryAngleWater,

      // Trajectory Shape Metrics
      'timeToPeakHeight': timeToPeakHeight, // Corrected
      'distanceToPeakHeight': distanceToPeakHeight, // Corrected

      // Reference
      'pixelsPerMeter': ppmAtJumpDepth,
    };
  }

  double? _previewJumpMeters() {
    // MODIFIED: Need 6 points to preview
    if (_measurementPoints.length < 6) return null;

    // MODIFIED:
    // point[4] is the block edge
    // point[5] is the water entry
    final jumpStart = _measurementPoints[4];
    final jumpEnd = _measurementPoints[5];
    final jumpY = (jumpStart.dy + jumpEnd.dy) / 2;

    final ppm = _getPixelsPerMeterAtDepth(jumpY);
    if (ppm == null) return null;

    // Use the 2D line distance
    final jumpDistancePx = (jumpEnd - jumpStart).distance;

    return jumpDistancePx / ppm;
  }

  void _calculateMeasuredDistance({bool showSnackbar = true}) {
    // MODIFIED: Check for 6 points
    if (_measurementPoints.length < 6) {
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please mark all 5 steps.')),
        );
      }
      return;
    }

    final jumpDistance = _previewJumpMeters();
    if (jumpDistance == null) {
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
              Text('Could not calculate distance. Check reference marks.')),
        );
      }
      return;
    }
    debugPrint('Jump pixels: → ${jumpDistance.toStringAsFixed(2)} m');

    if (mounted) {
      setState(() {
        _startDistanceController.text = jumpDistance.toStringAsFixed(2);
      });
    }

    if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Jump length: ${jumpDistance.toStringAsFixed(2)} m'),
        ),
      );
    }

    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      setState(() {
        _isMeasuring = false;
        _measurementStep = 0;
        _draggedPointIndex = null;
        _isPointDragInProgress = false;
      });
    });
  }

  double? _getPixelsPerMeterAtDepth(double y) {
    if (_measurementPoints.length < 4) return null;

    final ropes = [
      {
        'y': (_measurementPoints[0].dy + _measurementPoints[1].dy) / 2,
        'dist': (_measurementPoints[0] - _measurementPoints[1]).distance
      },
      {
        'y': (_measurementPoints[2].dy + _measurementPoints[3].dy) / 2,
        'dist': (_measurementPoints[2] - _measurementPoints[3]).distance
      }
    ];
    ropes.sort((a, b) => (a['y'] as double).compareTo(b['y'] as double));

    final yFar = ropes[0]['y'] as double;
    final yNear = ropes[1]['y'] as double;
    final distFar = ropes[0]['dist'] as double;
    final distNear = ropes[1]['dist'] as double;

    if (distFar == 0 || distNear == 0 || yNear == yFar) return null;

    final ppmFar = distFar / 5.0;
    final ppmNear = distNear / 5.0;

    final slope = (ppmNear - ppmFar) / (yNear - yFar);
    final ppmAtY = ppmFar + slope * (y - yFar);

    return ppmAtY > 0 ? ppmAtY : null;
  }

  Widget _buildActionButtons() {
    final allEventsMarked = OffTheBlockEvent.values
        .every((event) => _markedTimestamps.containsKey(event));

    final isVideoLoaded = _controller?.value.isInitialized == true;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          if (!isVideoLoaded)
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text('Select Video'),
            ),

          if (isVideoLoaded && allEventsMarked)
            ElevatedButton.icon(
              onPressed: _calculateResults,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Calculate'),
            ),

          if (_isMeasuring && _measurementStep != 6)
            ElevatedButton.icon(
              onPressed: (){
                _measurementPoints.clear();
                setState(() {
                  _isMeasuring = false;
                  _measurementStep = 0;
                });
              },
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Exit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.black,
              ),
            ),

          if (_isMeasuring && _measurementPoints.isNotEmpty)
            ElevatedButton.icon(
              onPressed: (){
                setState(() {
                  ///Step four is autogenerated hence the user should never end up there
                  if(_measurementPoints.length == 6){
                    _measurementStep=4;
                    _measurementPoints.removeLast();
                    _measurementPoints.removeLast();
                  }else{
                    _measurementStep--;
                    _measurementPoints.removeLast();
                  }
                });
              },
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
              ),
            ),

          if (_isMeasuring && _measurementPoints.length == 6)
            ElevatedButton.icon(
              onPressed: _calculateMeasuredDistance,
              icon: const Icon(Icons.straighten),
              label: const Text('Set Distance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Off the Block Analysis")),
      body: Column(
        children: [
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width / 1.78, // ≈ 16:9 ratio
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _controller == null
                  ? _buildVideoSelectionPrompt()
                  : _buildVideoPlayer(),
            ),
          ),

          Divider(),
          if (_isMeasuring)
            Container(
              color: Colors.blue.withAlpha(10),
              width: double.infinity,
              height: 110.0,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12.0),
              child: SingleChildScrollView(
                // FIX: Prevents overflow
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_getMeasurementInstruction().isNotEmpty)
                      Text(_getMeasurementInstruction(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            ),
          if (_controller != null && !_isLoading)
            Expanded(flex: 3, child: _buildMarkingInterface()),
          if (!_isLoading) _buildActionButtons(),
        ],
      ),
    );
  }
}

class _JumpOverlayPainter extends CustomPainter {
  final List<Offset> points;
  final double? previewMeters;

  _JumpOverlayPainter({
    required this.points,
    required this.previewMeters,
  });

  void _drawLabel(Canvas canvas, Offset pos, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, backgroundColor: Colors.black54, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + const Offset(6, -20));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --- PAINTS ---
    final aiMarkPaint = Paint()
      ..color = Colors.redAccent.withAlpha(80)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final aiConnectorPaint = Paint()
      ..color = Colors.redAccent.withAlpha(60)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final aiFillPaint = Paint()
      ..color = Colors.red.withAlpha(15)
      ..style = PaintingStyle.fill;

    final jumpPaint = Paint()
      ..color = Colors.greenAccent.withAlpha(90)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final handlePaint = Paint()
      ..color = Colors.white.withAlpha(90)
      ..style = PaintingStyle.fill;

    // === 1. DRAW AI RHOMBUS (the 5m surface) ===
    if (points.length >= 4) {
      final leftStart = points[0];
      final leftEnd = points[1];
      final rightStart = points[2];
      final rightEnd = points[3];

      // Create a path for the rhombus fill
      final surfacePath = Path()
        ..moveTo(leftStart.dx, leftStart.dy)
        ..lineTo(leftEnd.dx, leftEnd.dy)
        ..lineTo(rightEnd.dx, rightEnd.dy)
        ..lineTo(rightStart.dx, rightStart.dy)
        ..close();

      // Fill the path
      canvas.drawPath(surfacePath, aiFillPaint);

      // Draw the 4 border lines
      canvas.drawLine(leftStart, leftEnd, aiMarkPaint); // Main left line
      canvas.drawLine(rightStart, rightEnd, aiMarkPaint); // Main right line
      canvas.drawLine(leftStart, rightStart, aiConnectorPaint); // Connector
      canvas.drawLine(leftEnd, rightEnd, aiConnectorPaint); // Connector

      // Draw circles at the corners for visibility
      canvas.drawCircle(leftStart, 6, aiMarkPaint);
      canvas.drawCircle(leftEnd, 6, aiMarkPaint);
      canvas.drawCircle(rightStart, 6, aiMarkPaint);
      canvas.drawCircle(rightEnd, 6, aiMarkPaint);
    }

    // === 2. DRAW JUMP LINES (MODIFIED) ===

    // Draw "Start" (block edge) point
    if (points.length >= 5) {
      final start = points[4];
      canvas.drawCircle(start, 5, handlePaint);
      _drawLabel(canvas, start, 'Start (Block)', Colors.greenAccent);
    }

    // Draw "Water Entry" point and horizontal jump line
    if (points.length >= 6) {
      final start = points[4]; // This is the start of the jump
      final entry = points[5]; // This is the end

      // This is the main measurement line
      canvas.drawLine(start, entry, jumpPaint);

      canvas.drawCircle(entry, 5, handlePaint);
      _drawLabel(canvas, entry, 'Entry', Colors.greenAccent);

      // Draw the distance label
      if (previewMeters != null) {
        final mid =
        Offset((start.dx + entry.dx) / 2, (start.dy + entry.dy) / 2);
        final tp = TextPainter(
          text: TextSpan(
            text: '${previewMeters!.toStringAsFixed(2)} m',
            style: const TextStyle(
              color: Colors.white,
              backgroundColor: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid + const Offset(10, -25));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _JumpOverlayPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.previewMeters != previewMeters;
  }
}