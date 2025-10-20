import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imgLib;
import 'package:image_picker/image_picker.dart';
import 'package:swim_analyzer/analysis/start/start_analysis_controls_overlay.dart';
import 'package:swim_analyzer/analysis/time_line_painter.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
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
  bool _isDetecting = false; // NEW: AI loading flag

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

  Offset _sceneToVideo(Offset sceneOffset) {
    final videoSize = _controller!.value.size;
    final displayWidth = MediaQuery.of(context).size.width;
    final displayHeight = displayWidth / _controller!.value.aspectRatio;

    return Offset(
      sceneOffset.dx * videoSize.width / displayWidth,
      sceneOffset.dy * videoSize.height / displayHeight,
    );
  }


  // --------------------------------------------------------------------------
  // 🧠 AI DETECTION LOGIC
  // --------------------------------------------------------------------------
  Future<void> _runAIDetection() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isDetecting = true);

    try {
      await _controller!.pause();

      // 1️⃣ Extract a frame at current position
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
          'assets/models/detect_5m_marks_v4.tflite');

      var output = List.filled(4, 0.0).reshape([1, 4]);
      interpreter.run(input.reshape([1, 128, 128, 3]), output);
      final result = output[0]; // [x1, y1, x2, y2]

      final Size videoSize = _controller!.value.size;
      final double videoWidth = videoSize.width;
      final double videoHeight = videoSize.height;
      debugPrint('Real video frame: ${videoWidth.toStringAsFixed(0)}×${videoHeight.toStringAsFixed(0)}');



      // 3️⃣ Detect coordinate scale automatically (0–1 vs 0–128)
      bool normalized = result.every((v) => v >= 0.0 && v <= 1.0);
      debugPrint("AI output: $result (normalized=$normalized)");

      double scaleX = normalized ? videoWidth : videoWidth / 128.0;
      double scaleY = normalized ? videoHeight : videoHeight / 128.0;

      final leftMark = Offset(result[0] * scaleX, result[1] * scaleY);
      final rightMark = Offset(result[2] * scaleX, result[3] * scaleY);

      // 4️⃣ Make lines big enough to see clearly
      const halfSpanPx = 120.0;
      final leftStart = leftMark.translate(-halfSpanPx, 0);
      final leftEnd = leftMark.translate(halfSpanPx, 0);
      final rightStart = rightMark.translate(-halfSpanPx, 0);
      final rightEnd = rightMark.translate(halfSpanPx, 0);

      // 5️⃣ Compute and log scale info
      final leftLengthPx = (leftStart - leftEnd).distance;
      final rightLengthPx = (rightStart - rightEnd).distance;

      // Perspective compensation: closer mark (smaller y) appears longer
      final perspectiveFactor = rightMark.dy / leftMark.dy; // < 1.0 if rightMark higher
      final correctedLeftLengthPx = leftLengthPx * perspectiveFactor.clamp(0.6, 1.0);

// Weighted average: nearer lane dominates scale
      final weightedAvgPxPerMeter = (correctedLeftLengthPx + rightLengthPx * 1.5) / (5.0 * 2.5);
      debugPrint('Perspective factor = ${perspectiveFactor.toStringAsFixed(2)} '
          '→ corrected L span ${correctedLeftLengthPx.toStringAsFixed(1)} px');
      debugPrint('Weighted pixels per meter ≈ ${weightedAvgPxPerMeter.toStringAsFixed(1)}');

      final ppmLeft = leftLengthPx / 5.0;
      final ppmRight = rightLengthPx / 5.0;
      final avgPpm = (ppmLeft + ppmRight) / 2.0;

      debugPrint('Video size: ${videoWidth.toStringAsFixed(0)}×${videoHeight.toStringAsFixed(0)}');
      debugPrint('AI leftMark: ${leftMark.dx.toStringAsFixed(1)}, ${leftMark.dy.toStringAsFixed(1)}');
      debugPrint('AI rightMark: ${rightMark.dx.toStringAsFixed(1)}, ${rightMark.dy.toStringAsFixed(1)}');
      debugPrint('AI left span ≈ ${leftLengthPx.toStringAsFixed(1)} px');
      debugPrint('AI right span ≈ ${rightLengthPx.toStringAsFixed(1)} px');
      debugPrint('Pixels per meter ≈ ${avgPpm.toStringAsFixed(1)}');

      // 6️⃣ Update overlay
      setState(() {
        _measurementPoints
          ..clear()
          ..addAll([
            leftStart,
            leftEnd,
            rightStart,
            rightEnd,
          ]);
        _measurementStep = 4;
      });

      // 7️⃣ Show visible debug info
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            'AI ${normalized ? "normalized" : "pixel"} coords '
                '| ${avgPpm.toStringAsFixed(1)} px/m  '
                '| L:${leftLengthPx.toStringAsFixed(0)}px R:${rightLengthPx.toStringAsFixed(0)}px',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('AI detection failed: $e\n$st');
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

        // image >= 4.0 returns Pixel
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        buffer[i++] = r / 255.0;
        buffer[i++] = g / 255.0;
        buffer[i++] = b / 255.0;
      }
    }

    return buffer; // Float32List for a float model
  }

  // --------------------------------------------------------------------------
  // 🔹 EXISTING APP LOGIC (unchanged except where noted)
  // --------------------------------------------------------------------------
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

  void _calculateResults() {
    // Existing physics calc flow unchanged
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
    // compute a live preview distance (no state changes)
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
          if (!_isMeasuring ||
              _isPointDragInProgress ||
              _measurementPoints.length >= 6) return;

          final sceneOffset =
          _transformationController.toScene(details.localPosition);
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
                // NEW: draw AI 5m marks + jump line + label on top while measuring
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

  // 🧩 Only change here: trigger AI on Measure
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
                await _runAIDetection(); // 🚀 Run AI when Measure pressed
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

  // --------------------------------------------------------------------------
  // 🖼 EVERYTHING BELOW IS YOUR ORIGINAL CODE (unchanged)
  // --------------------------------------------------------------------------

  // Performs the final physics calculations for the jump.
  Map<String, double>? _calculateJumpPhysics() {
    if (_markedTimestamps[OffTheBlockEvent.leftBlock] == null ||
        _markedTimestamps[OffTheBlockEvent.touchedWater] == null ||
        _measurementPoints.length < 6) {
      return null;
    }

    // 1. Calculate jump distance from measurement points
    final jumpStartPoint = _measurementPoints[4]; // block edge
    final waterEntry = _measurementPoints[5]; // water entry
    final jumpMidY = (jumpStartPoint.dy + waterEntry.dy) / 2;

    final ppmAtJumpDepth = _getPixelsPerMeterAtDepth(jumpMidY);
    if (ppmAtJumpDepth == null) return null;

    final jumpDistancePx = (waterEntry.dx - jumpStartPoint.dx).abs();
    final jumpDistanceMeters = jumpDistancePx / ppmAtJumpDepth;

    // 2. Calculate flight time from marked events
    final flightTimeDuration =
        _markedTimestamps[OffTheBlockEvent.touchedWater]! -
            _markedTimestamps[OffTheBlockEvent.leftBlock]!;
    final flightTimeSeconds = flightTimeDuration.inMilliseconds / 1000.0;

    if (flightTimeSeconds <= 0) return null;

    // 3. Calculate horizontal velocity
    final horizontalVelocity = jumpDistanceMeters / flightTimeSeconds;

    return {
      'jumpDistance': jumpDistanceMeters,
      'flightTime': flightTimeSeconds,
      'horizontalVelocity': horizontalVelocity,
      'pixelsPerMeter': ppmAtJumpDepth,
    };
  }

  // NEW: AI-scaled measurement using the 5 m marks
  void _calculateMeasuredDistance({bool showSnackbar = true}) {
    if (_measurementPoints.length < 6) {
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please mark start and water entry.')),
        );
      }
      return;
    }

    // 0–3 = AI 5m marks; 4 = start block; 5 = water entry
    final leftA = _sceneToVideo(_measurementPoints[0]);
    final leftB = _sceneToVideo(_measurementPoints[1]);
    final rightA = _sceneToVideo(_measurementPoints[2]);
    final rightB = _sceneToVideo(_measurementPoints[3]);
    final start = _sceneToVideo(_measurementPoints[4]);
    final entry = _sceneToVideo(_measurementPoints[5]);

    final ppmLeft = (leftA - leftB).distance / 5.0;
    final ppmRight = (rightA - rightB).distance / 5.0;
    final pixelsPerMeter = (ppmLeft + ppmRight) / 2.0;

    if (pixelsPerMeter <= 0) {
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid reference scale.')),
        );
      }
      return;
    }

    final jumpPixels = (entry - start).distance;
    final jumpMeters = jumpPixels / pixelsPerMeter;
    debugPrint('Jump pixels: ${jumpPixels.toStringAsFixed(1)} → ${jumpMeters.toStringAsFixed(2)} m');


    if (mounted) {
      setState(() {
        _startDistanceController.text = jumpMeters.toStringAsFixed(2);
      });
    }

    if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
          Text('Jump length: ${jumpMeters.toStringAsFixed(2)} m'),
        ),
      );
    }

    // Optionally exit measuring; keep points if you prefer
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
  void _clearMeasurement() {
    setState(() {
      _measurementPoints.clear();
      _measurementStep = 0;
      _draggedPointIndex = null;
    });
  }

  // Calculates the scale (pixels per meter) at a given vertical depth (y-coordinate)
// using linear interpolation between the two 5m reference markers.
  double? _getPixelsPerMeterAtDepth(double y) {
    if (_measurementPoints.length < 4) return null;

    // Ensure points are sorted by y-value to correctly identify near/far ropes
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

    // Linear interpolation/extrapolation for ppm at depth y
    final slope = (ppmNear - ppmFar) / (yNear - yFar);
    final ppmAtY = ppmFar + slope * (y - yFar);

    return ppmAtY > 0 ? ppmAtY : null;
  }


// Provides a live preview of the jump distance as the user marks points.
  double? _previewJumpMeters() {
    if (_measurementPoints.length < 6) return null;

    final jumpStart = _measurementPoints[4];
    final jumpEnd = _measurementPoints[5];
    final jumpY = (jumpStart.dy + jumpEnd.dy) / 2;

    final ppm = _getPixelsPerMeterAtDepth(jumpY);
    if (ppm == null) return null;

    // The jump is primarily horizontal in this camera view.
    final jumpDistancePx = (jumpEnd.dx - jumpStart.dx).abs();

    return jumpDistancePx / ppm;
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

  // --------------------------------------------------------------------------
  // 🧭 BUILD UI WRAPPED WITH DETECTION OVERLAY
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Scaffold(
        appBar: AppBar(title: const Text("Off the Block Analysis")),
        body: Column(
          children: [
            if (_isMeasuring)
              Container(
                color: Colors.blue.withAlpha(10),
                width: double.infinity,
                height: 110.0,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_getMeasurementInstruction().isNotEmpty)
                      Text(_getMeasurementInstruction(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    if (_measurementPoints.length == 6) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        // FIX: use the AI-scaled measurement
                        onPressed: () => _calculateMeasuredDistance(),
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
              Expanded(flex: 3, child: _buildMarkingInterface()),
            if (!_isLoading) _buildActionButtons(),
          ],
        ),
      ),
      if (_isDetecting)
        Container(
          color: Colors.black45,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text("Analyzing 5m marks...",
                    style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
    ]);
  }
}

// --------------------------------------------------------------------------
// 🎨 Overlay painter: draws AI 5m marks + jump line + distance label
// --------------------------------------------------------------------------
class _JumpOverlayPainter extends CustomPainter {
  final List<Offset> points; // expects: 0-3 AI marks, 4 start, 5 entry
  final double? previewMeters;

  _JumpOverlayPainter({
    required this.points,
    required this.previewMeters,
  });

  void _drawLabel(Canvas canvas, Offset pos, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, backgroundColor: Colors.black87, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + const Offset(4, -16));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final aiMarkPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final jumpPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // === DRAW AI MARKS (big visible lines + circles) ===
    if (points.length >= 2) {
      canvas.drawLine(points[0], points[1], aiMarkPaint);
      canvas.drawCircle(points[0], 6, aiMarkPaint);
      canvas.drawCircle(points[1], 6, aiMarkPaint);
      _drawLabel(canvas, points[1], '5 m ref (L)', Colors.redAccent);
    }
    if (points.length >= 4) {
      canvas.drawLine(points[2], points[3], aiMarkPaint);
      canvas.drawCircle(points[2], 6, aiMarkPaint);
      canvas.drawCircle(points[3], 6, aiMarkPaint);
      _drawLabel(canvas, points[3], '5 m ref (R)', Colors.redAccent);
    }

    // === DRAW JUMP LINE ===
    if (points.length >= 5) {
      final start = points[4];
      canvas.drawCircle(start, 5, handlePaint);
      _drawLabel(canvas, start, 'Start', Colors.greenAccent);
    }
    if (points.length >= 6) {
      final start = points[4];
      final entry = points[5];
      canvas.drawLine(start, entry, jumpPaint);
      canvas.drawCircle(entry, 5, handlePaint);
      _drawLabel(canvas, entry, 'Entry', Colors.greenAccent);

      if (previewMeters != null) {
        final mid = Offset((start.dx + entry.dx) / 2, (start.dy + entry.dy) / 2);
        final tp = TextPainter(
          text: TextSpan(
            text: '${previewMeters!.toStringAsFixed(2)} m',
            style: const TextStyle(
              color: Colors.white,
              backgroundColor: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid + const Offset(10, -25));
      }
    }
    _drawLabel(canvas, points[1], '5 m ref (L, corr)', Colors.orangeAccent);
    _drawLabel(canvas, points[3], '5 m ref (R, main)', Colors.redAccent);
  }

  @override
  bool shouldRepaint(covariant _JumpOverlayPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.previewMeters != previewMeters;
  }
}
