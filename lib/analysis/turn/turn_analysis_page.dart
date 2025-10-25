import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:swim_analyzer/analysis/turn/turn_event.dart';
import 'package:swim_analyzer/analysis/turn/turn_result_page.dart';
import 'package:swim_apps_shared/objects/user/user.dart';
import 'package:video_player/video_player.dart';
import 'package:swim_analyzer/analysis/time_line_painter.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';

class TurnAnalysisPage extends StatefulWidget {
  final AppUser appUser;

  const TurnAnalysisPage({super.key, required this.appUser});

  @override
  State<TurnAnalysisPage> createState() => _TurnAnalysisPageState();
}

class _TurnAnalysisPageState extends State<TurnAnalysisPage> {
  bool _isLoading = false;
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();

  final Map<TurnEvent, Duration> _markedTimestamps = {};

  // Scrubber state
  late final ScrollController _scrubberScrollController;
  bool _isScrubbing = false;
  static const double _pixelsPerSecond = 150.0;

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
        SnackBar(content: Text('Failed to load video: ${e.toString()}')),
      );
      setState(() {
        _isLoading = false;
        _controller = null;
      });
    }
  }

  void _markEvent(TurnEvent event) {
    if (_controller == null) return;
    setState(() {
      _markedTimestamps[event] = _controller!.value.position;
    });
  }

  Future<void> _seekFrames({required bool isForward}) async {
    if (_controller == null) return;

    final currentPosition = _controller!.value.position;
    const frameRate = 30.0; // assume 30fps if not known
    final frameDuration = Duration(milliseconds: (1000 / frameRate).round());
    final int frames = isForward ? 1 : -1;
    final newPosition = currentPosition + frameDuration * frames;

    await _controller!.seekTo(newPosition);
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    }
  }

  String _formatScrubberDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void _calculateResults() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TurnResultPage(
          appUser: widget.appUser,
          markedTimestamps: _markedTimestamps,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Turn Analysis")),
      body: Column(
        children: [
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
    );
  }

  Widget _buildVideoSelectionPrompt() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.video_library_outlined, size: 80, color: Colors.grey),
        SizedBox(height: 16),
        Text('Select a video of a turn to begin.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
      ],
    ),
  );

  Widget _buildVideoPlayer() {
    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller!),
            _ControlsOverlay(controller: _controller!),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkingInterface() {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
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
            ...TurnEvent.values.map(_buildEventMarkerTile),
            const SizedBox(height: 16),
          ],
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

  Widget _buildEventMarkerTile(TurnEvent event) {
    final markedTime = _markedTimestamps[event];
    String timeText =
    markedTime != null ? '${(markedTime.inMilliseconds / 1000.0).toStringAsFixed(2)}s' : 'Not marked';

    return ListTile(
      title: Text(event.displayName),
      subtitle: Text(
        timeText,
        style: TextStyle(color: markedTime != null ? Colors.green : Colors.grey),
      ),
      trailing: ElevatedButton(
        onPressed: () => _markEvent(event),
        child: const Text('Mark'),
      ),
      dense: true,
    );
  }

  Widget _buildActionButtons() {
    final allEventsMarked = TurnEvent.values
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
            onPressed: _controller?.value.isInitialized == true && allEventsMarked
                ? _calculateResults
                : null,
            icon: const Icon(Icons.analytics),
            label: const Text('Calculate Turn Metrics'),
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
