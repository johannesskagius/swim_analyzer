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

  // --------------------------------------------------------------------------
  // 🧠 AI DETECTION LOGIC
  // --------------------------------------------------------------------------
  Future<void> _runAIDetection() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isDetecting = true);

    try {
      await _controller!.pause();

      final positionMs = _controller!.value.position.inMilliseconds;
      final videoPath = _controller!.dataSource.replaceAll('file://', '');
      final thumb = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: positionMs,
        quality: 100,
      );
      if (thumb == null) throw Exception('No frame extracted');

      final input = _imgToByteListFloat32(thumb, 128, 128);
      final interpreter = await Interpreter.fromAsset(
          'assets/models/detect_5m_marks_v3.tflite');

      var output = List.filled(4, 0.0).reshape([1, 4]);
      interpreter.run(input.reshape([1, 128, 128, 3]), output);
      final result = output[0]; // [x1, y1, x2, y2]

      final videoWidth = MediaQuery.of(context).size.width;
      final videoHeight = videoWidth / _controller!.value.aspectRatio;

      final leftMark = Offset(result[0] * videoWidth, result[1] * videoHeight);
      final rightMark = Offset(result[2] * videoWidth, result[3] * videoHeight);

      setState(() {
        _measurementPoints
          ..clear()
          ..addAll([
            leftMark.translate(-5, 0),
            leftMark.translate(5, 0),
            rightMark.translate(-5, 0),
            rightMark.translate(5, 0),
          ]);
        _measurementStep = 4;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ AI detected 5m marks automatically')),
      );
    } catch (e) {
      debugPrint('AI detection failed: $e');
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

        // For image >= 4.0
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        buffer[i++] = r / 255.0;
        buffer[i++] = g / 255.0;
        buffer[i++] = b / 255.0;
      }
    }

    return buffer; // ✅ Return Float32List, not Uint8List
  }




  // --------------------------------------------------------------------------
  // 🔹 EXISTING APP LOGIC (unchanged)
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

  Map<String, double>? _calculateJumpPhysics() {
    final startDistanceText = _startDistanceController.text;
    final leftBlockTime = _markedTimestamps[OffTheBlockEvent.leftBlock];
    final touchedWaterTime = _markedTimestamps[OffTheBlockEvent.touchedWater];
    if (startDistanceText.isEmpty ||
        leftBlockTime == null ||
        touchedWaterTime == null) return null;

    final double? horizontalDistance = double.tryParse(startDistanceText);
    if (horizontalDistance == null) return null;

    final flightTime =
        (touchedWaterTime.inMilliseconds - leftBlockTime.inMilliseconds) /
            1000.0;
    if (flightTime <= 0) return null;

    const double g = 9.81;
    final double velocityX = horizontalDistance / flightTime;
    final double initialVerticalVelocity =
        (0.5 * g * flightTime * flightTime - startHeight) / flightTime;
    final double jumpHeight =
        (initialVerticalVelocity * initialVerticalVelocity) / (2 * g);
    final double finalVerticalVelocity =
        initialVerticalVelocity - (g * flightTime);

    return {
      'jumpHeight': jumpHeight,
      'entryVelocityX': velocityX,
      'entryVelocityY': finalVerticalVelocity,
    };
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

  // (the rest of your long class is unchanged)
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
                        onPressed: () => _calculateJumpPhysics(),
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
