import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_analyze_result_view.dart';
import 'package:swim_analyzer/analysis/stroke/stroke_efficiency_event.dart';
import 'package:swim_analyzer/analysis/time_line_painter.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:video_player/video_player.dart';

import 'analysis_step.dart';

class StrokeAnalysisPage extends StatefulWidget {
  final AppUser appUser;
  const StrokeAnalysisPage({super.key, required this.appUser});

  @override
  State<StrokeAnalysisPage> createState() => _StrokeAnalysisPageState();
}

class _StrokeAnalysisPageState extends State<StrokeAnalysisPage> {
  // State for the multi-step flow
  AnalysisStep _currentStep = AnalysisStep.pickVideo;
  bool _isLoadingVideo = false;

  // State for analysis data
  IntensityZone? _selectedIntensity;
  Stroke? _selectedStroke;
  VideoPlayerController? _videoController;
  final Map<StrokeEfficiencyEvent, Duration> _markedTimestamps = {};
  final List<Duration> _strokeTimestamps = [];

  // State for precision scrubber
  late final ScrollController scrubberScrollController;
  late final ExpansibleController _timeEventsController;
  bool isScrubbing = false;
  static const double pixelsPerSecond = 200.0;

  @override
  void initState() {
    super.initState();
    scrubberScrollController = ScrollController();
    _timeEventsController = ExpansibleController();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    scrubberScrollController.dispose();
    _timeEventsController.dispose();
    super.dispose();
  }

  void _videoListener() {
    if (isScrubbing || !scrubberScrollController.hasClients || !mounted) return;
    final videoPosition = _videoController!.value.position;
    final scrollPosition = videoPosition.inMilliseconds / 1000.0 * pixelsPerSecond;
    scrubberScrollController.jumpTo(scrollPosition);
    setState(() {}); // Keep UI in sync
  }

  Future<void> _pickVideo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    setState(() => _isLoadingVideo = true);

    try {
      await _videoController?.dispose();
      _videoController?.removeListener(_videoListener);

      final newController = VideoPlayerController.file(File(video.path));
      await newController.initialize();

      setState(() {
        _videoController = newController;
        _videoController!.addListener(_videoListener);
        _markedTimestamps.clear();
        _strokeTimestamps.clear();
        _isLoadingVideo = false;
        _currentStep = AnalysisStep.pickDetails;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading video: $e')),
        );
        _resetFlow();
      }
    }
  }

  void _markEvent(StrokeEfficiencyEvent event) {
    if (_videoController == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _markedTimestamps[event] = _videoController!.value.position;

      // When all events are marked, collapse the tile.
      if (_markedTimestamps.length == StrokeEfficiencyEvent.values.length) {
        _timeEventsController.collapse();
      }
    });
  }

  void _markStroke() {
    if (_videoController == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _strokeTimestamps.add(_videoController!.value.position);
    });
  }

  void _resetStrokes() {
    setState(() {
      _strokeTimestamps.clear();
    });
  }

  double? get _strokeFrequency {
    if (_selectedStroke == null || _strokeTimestamps.length < 2) return null;
    _strokeTimestamps.sort();
    final totalDuration = _strokeTimestamps.last - _strokeTimestamps.first;
    if (totalDuration.inMilliseconds <= 0) return null;

    double cycles;
    if (_selectedStroke == Stroke.breaststroke || _selectedStroke == Stroke.butterfly) {
      // For double-tap strokes, 3 taps (e.g., high-glide-high) form 1 cycle.
      cycles = (_strokeTimestamps.length - 1) / 2.0;
    } else {
      // For single-tap strokes, 2 taps form 1 cycle.
      cycles = (_strokeTimestamps.length - 1).toDouble();
    }

    if (cycles <= 0) return null;

    return cycles / (totalDuration.inMilliseconds / 1000.0) * 60;
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'Not Marked';
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    String threeDigitMillis =
    (duration.inMilliseconds.remainder(1000) / 10).round().toString().padLeft(2, "0");
    return "$twoDigitMinutes:$twoDigitSeconds.$threeDigitMillis";
  }

  void _resetFlow() {
    setState(() {
      _isLoadingVideo = false;
      _videoController?.removeListener(_videoListener);
      _videoController?.dispose();
      _videoController = null;
      _selectedIntensity = null;
      _selectedStroke = null;
      _markedTimestamps.clear();
      _strokeTimestamps.clear();
      if (_timeEventsController.isExpanded) {
        _timeEventsController.collapse();
      }
      _currentStep = AnalysisStep.pickVideo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoadingVideo ? 'Loading Video...' : _getAppBarTitle()),
        leading: _currentStep != AnalysisStep.pickVideo && !_isLoadingVideo
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _resetFlow, // Reset the flow instead of popping
        )
            : null,
      ),
      body: _isLoadingVideo
          ? const Center(child: CircularProgressIndicator())
          : _buildCurrentStep(),
    );
  }

  String _getAppBarTitle() {
    switch (_currentStep) {
      case AnalysisStep.pickVideo:
        return "Step 1: Select Video";
      case AnalysisStep.pickDetails:
        return "Step 2: Select Swim Details";
      case AnalysisStep.analyze:
        return "Step 3: Analyze Swim";
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case AnalysisStep.pickVideo:
        return _buildVideoPickerStep();
      case AnalysisStep.pickDetails:
        return _buildDetailsPickerStep();
      case AnalysisStep.analyze:
        return _buildAnalysisStep();
    }
  }

  Widget _buildVideoPickerStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined, size: 100, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Start by selecting a 25m video to analyze.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text('Select Video'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seekFrames({required bool isForward}) async {
    if (_videoController == null) return;

    final currentPosition = _videoController!.value.position;
    const frameRate = 30.0;
    final frameDuration = Duration(milliseconds: (1000 / frameRate).round());
    final newPosition = currentPosition + (isForward ? frameDuration : -frameDuration);

    await _videoController!.seekTo(newPosition);
    if (_videoController!.value.isPlaying) {
      await _videoController!.pause();
    }
  }

  Widget _buildDetailsPickerStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pool, size: 100, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Next, specify the details for this swim.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<Stroke>(
              initialValue: _selectedStroke,
              decoration: const InputDecoration(
                labelText: 'Stroke',
                border: OutlineInputBorder(),
              ),
              items: Stroke.values.map((stroke) {
                return DropdownMenuItem(
                  value: stroke,
                  child: Text(stroke.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedStroke = value;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<IntensityZone>(
              initialValue: _selectedIntensity,
              decoration: const InputDecoration(
                labelText: 'Swim Intensity',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedIntensity = value;
                });
              },
              items: IntensityZone.values.map((intensity) {
                return DropdownMenuItem(
                  value: intensity,
                  child: Text(intensity.name),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_selectedIntensity != null && _selectedStroke != null)
                  ? () {
                setState(() {
                  _currentStep = AnalysisStep.analyze;
                });
              }
                  : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isAnalysisComplete() {
    final allEventsMarked = _markedTimestamps.length == StrokeEfficiencyEvent.values.length;
    final hasEnoughStrokes = _strokeTimestamps.length >= 2;
    return allEventsMarked && hasEnoughStrokes;
  }

  void _calculateAndShowResult() {
    final frequency = _strokeFrequency;
    if (frequency == null || _selectedStroke == null || _selectedIntensity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not calculate frequency or some details are missing.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StrokeAnalysisResultView(
          intensity: _selectedIntensity!,
          stroke: _selectedStroke!,
          markedTimestamps: Map.from(_markedTimestamps),
          strokeTimestamps: List.from(_strokeTimestamps),
          strokeFrequency: frequency,
          user: widget.appUser,
        ),
      ),
    );
  }


  Widget _buildAnalysisStep() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildVideoMarkingSection(),
        const SizedBox(height: 24),
        if (_isAnalysisComplete())
          ElevatedButton.icon(
            onPressed: _calculateAndShowResult,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('View Results'),
          ),
      ],
    );
  }

  String formatScrubberDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Widget buildPrecisionScrubber() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const SizedBox(height: 60);
    }
    final totalDuration = _videoController!.value.duration;
    final timelineWidth =
    max(MediaQuery.of(context).size.width, (totalDuration.inMilliseconds / 1000.0) * pixelsPerSecond);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && notification.dragDetails != null) {
          setState(() => isScrubbing = true);
          _videoController!.pause();
        } else if (notification is ScrollUpdateNotification && isScrubbing) {
          final newPosition =
          Duration(milliseconds: (notification.metrics.pixels / pixelsPerSecond * 1000).round());
          _videoController!.seekTo(newPosition);
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

  String _getStrokeInstructionText() {
    switch (_selectedStroke) {
      case Stroke.butterfly:
        return 'Tap twice per stroke: first on hands stretched backwards, second on hands stretched forward.';
      case Stroke.breaststroke:
        return 'Tap twice per stroke: first on the highest position in the cycle, and second just when the swimmer has entered the glide phase.';
      case Stroke.backstroke:
      case Stroke.freestyle:
        return 'Tap once every time an arm is at the start of the stroke.';
      default:
        return 'Tap the button for each stroke.';
    }
  }

  Widget _buildVideoMarkingSection() {
    final frequency = _strokeFrequency;
    final allEventsMarked = _markedTimestamps.length == StrokeEfficiencyEvent.values.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_videoController != null && _videoController!.value.isInitialized)
            Column(
              children: [
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(onPressed: () => _seekFrames(isForward: false), icon: const Icon(Icons.arrow_back_ios)),
                    Expanded(child: buildPrecisionScrubber()),
                    IconButton(onPressed: () => _seekFrames(isForward: true), icon: const Icon(Icons.arrow_forward_ios))
                  ],
                ),
              ],
            )
          else
            Container(
              height: 200,
              color: Colors.black,
              child: const Center(
                child: Text('Video will appear here.', style: TextStyle(color: Colors.white)),
              ),
            ),
          const SizedBox(height: 16),
          ExpansionTile(
            controller: _timeEventsController,
            initiallyExpanded: true,
            title: const Text('Time Events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            tilePadding: EdgeInsets.zero,
            children: StrokeEfficiencyEvent.values.map((event) {
              final markedTime = _markedTimestamps[event];
              return ListTile(
                dense: true,
                leading: Icon(markedTime != null ? Icons.check_circle : Icons.add_circle_outline,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(event.name),
                subtitle: Text(_formatDuration(markedTime)),
                onTap: () => _markEvent(event),
                contentPadding: const EdgeInsets.only(left: 16.0),
              );
            }).toList(),
          ),
          if (allEventsMarked) ...[
            const Divider(height: 32),
            const Text('Stroke Frequency', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Stroke Count: ${_strokeTimestamps.length}', style: const TextStyle(fontSize: 16)),
                          if (frequency != null)
                            Text('Frequency: ${frequency.toStringAsFixed(1)} str/min',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(onPressed: _resetStrokes, icon: const Icon(Icons.refresh), tooltip: 'Reset Strokes'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_getStrokeInstructionText(), style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _markStroke,
                      icon: const Icon(Icons.touch_app),
                      label: const Text('Mark Stroke'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
        ],
      ),
    );
  }
}