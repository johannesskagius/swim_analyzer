import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:swim_analyzer/results_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:video_player/video_player.dart';

class RaceAnalysisView extends StatefulWidget {
  const RaceAnalysisView({super.key});

  @override
  State<RaceAnalysisView> createState() => _RaceAnalysisViewState();
}

/// Enum to manage the user\'s current analysis focus.
enum _AnalysisMode { timing, attributes }

class _RaceAnalysisViewState extends State<RaceAnalysisView> {
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();
  bool _isLoadingVideo = false;
  String _loadingDetails = '';

  Event? _currentEvent;
  int _currentCheckPointIndex = 0;

  final List<RaceSegment> _recordedSegments = [];
  List<IntervalAttributes> _intervalAttributes = [];
  int _attributeEditingIntervalIndex = 0;

  bool _isSlowMotion = false;
  _AnalysisMode _analysisMode = _AnalysisMode.timing;

  // --- UX Improvement: Keys for scrolling the checkpoint guide ---
  List<GlobalKey> _checkpointKeys = [];

  //precision scroller
  late final ScrollController _scrubberScrollController;
  bool _isScrubbing = false;
  static const double _pixelsPerSecond = 200.0; // Adjust for zoom level

  //Audio wave form
  // Add these for the audio waveform display
  List<double>? _audioWaveform;
  bool _isProcessingWaveform = false;
  bool userPressedPlay = false;

  void _videoListener() {
    // This line correctly prevents the listener from running during a user scrub.
    if (_isScrubbing || !_scrubberScrollController.hasClients) return;

    final videoPosition = _controller!.value.position;
    final scrollPosition =
        videoPosition.inMilliseconds / 1000.0 * _pixelsPerSecond;

    _scrubberScrollController.jumpTo(scrollPosition);
  }

  String _formatScrubberDuration(Duration d) {
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  /// --- Audio Waveform Generation (Full Implementation) ---
  /// Extracts audio from the video file using FFmpeg, then processes the
  /// raw audio into a normalized waveform List<double>.
  // Future<void> _processAudioWaveform(String videoPath) async {
  //   setState(() => _isProcessingWaveform = true);
  //
  //   final Directory tempDir = await getTemporaryDirectory();
  //   final String rawAudioPath = '${tempDir.path}/raw_audio.pcm';
  //   final File rawAudioFile = File(rawAudioPath);
  //
  //   // Delete a previous temp file if it exists to avoid conflicts.
  //   if (await rawAudioFile.exists()) {
  //     await rawAudioFile.delete();
  //   }
  //
  //   // This FFmpeg command extracts the audio into a raw format.
  //   final String command =
  //       '-i "$videoPath" -f s16le -ac 1 -ar 44100 "$rawAudioPath"';
  //
  //   final session = await FFmpegKit.execute(command);
  //   final returnCode = await session.getReturnCode();
  //
  //   // BUG FIX: Corrected to use the class name from the new package.
  //   if (!ReturnCode.isSuccess(returnCode)) {
  //     print("FFmpeg failed to extract audio. Return code: $returnCode");
  //     final logs = await session.getLogsAsString();
  //     print("FFmpeg logs: $logs");
  //     if (mounted) setState(() => _isProcessingWaveform = false);
  //     return;
  //   }
  //
  //   // Read the raw audio bytes from the temporary file.
  //   if (!await rawAudioFile.exists()) {
  //     print("Error: Raw audio file was not created by FFmpeg.");
  //     if (mounted) setState(() => _isProcessingWaveform = false);
  //     return;
  //   }
  //   final bytes = await rawAudioFile.readAsBytes();
  //   await rawAudioFile.delete(); // Clean up the temp file immediately.
  //
  //   if (!mounted || bytes.isEmpty) {
  //     if (mounted) setState(() => _isProcessingWaveform = false);
  //     return;
  //   }
  //
  //   // Process the raw bytes. Each sample is 2 bytes (16-bit).
  //   final ByteData byteData = bytes.buffer.asByteData();
  //   final List<double> waveform = [];
  //   const double maxAmplitude = 32767.0;
  //
  //   for (int i = 0; i < byteData.lengthInBytes; i += 2) {
  //     final int sample = byteData.getInt16(i, Endian.little);
  //     waveform.add(sample / maxAmplitude);
  //   }
  //
  //   setState(() {
  //     _audioWaveform = waveform;
  //     _isProcessingWaveform = false;
  //   });
  // }

// The main widget for the precision scrubber
  Widget _buildPrecisionScrubber() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container();
    }
    final totalDuration = _controller!.value.duration;
    final timelineWidth =
        (totalDuration.inMilliseconds / 1000.0) * _pixelsPerSecond;

    // PERFORMANCE FIX: This is the most critical change for smooth playback.
    // The logic is now much stricter to differentiate user drags from programmatic scrolls.
    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        // 1. A user DRAG starts. Pause the video and set the scrubbing flag.
        if (scrollNotification is ScrollStartNotification &&
            scrollNotification.dragDetails != null) {
          setState(() {
            _isScrubbing = true;
            _controller?.pause();
          });
        }
        // 2. The user is DRAGGING. Seek the video only if we are in a scrubbing state.
        else if (scrollNotification is ScrollUpdateNotification &&
            _isScrubbing) {
          final newPosition = Duration(
              milliseconds:
                  (scrollNotification.metrics.pixels / _pixelsPerSecond * 1000)
                      .round());
          _controller?.seekTo(newPosition);
        }
        // 3. The user STOPS dragging. Unset the scrubbing flag.
        else if (scrollNotification is ScrollEndNotification && _isScrubbing) {
          setState(() {
            _isScrubbing = false;
          });
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  //_buildAudioWaveform(),
                  CustomPaint(
                    painter: _TimelinePainter(
                      totalDuration: totalDuration,
                      pixelsPerSecond: _pixelsPerSecond,
                      formatDuration: _formatScrubberDuration,
                    ),
                    size: Size(timelineWidth, 50),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 2,
            height: 60,
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrubberScrollController = ScrollController();
    // PERFORMANCE OPTIMIZATION: Do not add listener here.
    // It is added in _initializeVideoPlayer to avoid duplication.
    // _controller?.addListener(_videoListener);
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _scrubberScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    PermissionStatus status;
    if (Platform.isIOS) {
      status = await Permission.photos.request();
    } else {
      status = await Permission.videos.request();
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Permission is required to select a video.')),
        );
      }
      return;
    }

    setState(() {
      _isLoadingVideo = true;
      _loadingDetails = ''; // Reset details on new pick
    });

    final XFile? file;
    try {
      file = await _picker.pickVideo(source: ImageSource.gallery);
    } catch (e) {
      print("Error picking video: $e");
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    if (file == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    final selectedEvent = await _selectRace();
    if (selectedEvent == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    await _initializeVideoPlayer(file, selectedEvent);
  }

  Future<Stroke?> _selectStroke() {
    return showDialog<Stroke>(
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
                onTap: () {
                  Navigator.of(context).pop(stroke);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(null);
              },
            ),
          ],
        );
      },
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
                title: const Text('50m Race'),
                onTap: () => Navigator.of(context).pop(FiftyMeterRace),
              ),
              ListTile(
                title: const Text('100m Race'),
                onTap: () => Navigator.of(context).pop(HundredMetersRace),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ],
        );
      },
    );

    if (selectedRaceType == null) return null;
    final selectedStroke = await _selectStroke();
    if (selectedStroke == null) return null;

    if (selectedRaceType == FiftyMeterRace) {
      return FiftyMeterRace(stroke: selectedStroke);
    } else if (selectedRaceType == HundredMetersRace) {
      return HundredMetersRace(stroke: selectedStroke);
    }

    return null;
  }

  Future<void> _initializeVideoPlayer(XFile file, Event event) async {
    // Clean up old controller first
    _controller?.removeListener(_videoListener);
    _controller?.dispose();

    final fileSizeInBytes = await file.length();
    final fileSizeInMB = fileSizeInBytes / (1024 * 1024);
    if (mounted) {
      setState(() {
        _loadingDetails = '(${fileSizeInMB.toStringAsFixed(1)} MB)';
      });
    }

    final newController = VideoPlayerController.file(File(file.path));
    // Add the listener ONCE to the new controller
    newController.addListener(_videoListener);
    _controller = newController;

    try {
      await newController.initialize();
      if (!mounted) {
        newController.dispose();
        return;
      }
      //_processAudioWaveform(file.path);
      setState(() {
        _currentEvent = event;
        _isLoadingVideo = false;
        _loadingDetails = '';
        _resetAnalysisState();
      });
    } catch (e) {
      print('Error initializing video: $e');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
          _loadingDetails = '';
          _controller = null;
        });
      }
    }
  }

  /// Resets the analysis state without touching the video controller itself.
  void _resetAnalysisState() {
    _controller?.seekTo(Duration.zero);
    _controller?.pause();
    HapticFeedback.heavyImpact();

    setState(() {
      _recordedSegments.clear();
      _currentCheckPointIndex = 0;
      _isSlowMotion = false;
      _controller?.setPlaybackSpeed(1.0);
      _attributeEditingIntervalIndex = 0;

      if (_currentEvent != null) {
        final intervalCount = _currentEvent!.checkPoints.length - 1;
        _intervalAttributes =
            List.generate(intervalCount, (_) => IntervalAttributes());
        _checkpointKeys = List.generate(
            _currentEvent!.checkPoints.length, (_) => GlobalKey());
      } else {
        _intervalAttributes = [];
        _checkpointKeys = [];
      }
    });
  }

  /// --- UX Improvement: Updated to handle auto-scrolling ---
  void _recordCheckpoint() {
    if (_controller == null || _currentEvent == null) return;
    final position = _controller!.value.position;
    final nextCheckPoint = _currentEvent!.checkPoints[_currentCheckPointIndex];

    HapticFeedback.mediumImpact();

    setState(() {
      final segment = RaceSegment(
          checkPoint: nextCheckPoint, splitTimeOfTotalRace: position);
      _recordedSegments.add(segment);

      if (_currentCheckPointIndex < _currentEvent!.checkPoints.length - 1) {
        _currentCheckPointIndex++;

        if (_currentCheckPointIndex >= 4) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_checkpointKeys.length > (_currentCheckPointIndex - 3)) {
              final keyToScrollTo =
                  _checkpointKeys[_currentCheckPointIndex - 3];
              final context = keyToScrollTo.currentContext;
              if (context != null) {
                Scrollable.ensureVisible(
                  context,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  alignment: 0.1,
                );
              }
            }
          });
        }
      }
    });
  }

  /// --- UX Improvement: Updated to handle auto-scrolling ---
  void _rewindAndUndo() {
    if (_recordedSegments.isEmpty) return;
    HapticFeedback.mediumImpact();
    final oldIndex = _currentCheckPointIndex;

    setState(() {
      _recordedSegments.removeLast();
      if (_currentCheckPointIndex > 0) {
        _currentCheckPointIndex--;
      }
    });

    if (oldIndex >= 4 && _currentCheckPointIndex >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_checkpointKeys.length > (_currentCheckPointIndex - 3)) {
          final keyToScrollTo = _checkpointKeys[_currentCheckPointIndex - 3];
          final context = keyToScrollTo.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        }
      });
    }

    final newPosition =
        _controller!.value.position - const Duration(seconds: 5);
    _controller?.seekTo(newPosition.isNegative ? Duration.zero : newPosition);
  }

  void _toggleSlowMotion() {
    if (_controller == null) return;
    HapticFeedback.mediumImpact();
    _isSlowMotion = !_isSlowMotion;
    _controller!.setPlaybackSpeed(_isSlowMotion ? 0.5 : 1.0);
    setState(() {});
  }

  void _viewResults() {
    if (_currentEvent == null) return;
    _controller?.pause();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RaceResultsView(
          recordedSegments: _recordedSegments,
          intervalAttributes: _intervalAttributes,
          event: _currentEvent!,
        ),
      ),
    );
  }

  // Widget _buildAudioWaveform() {
  //   if (_isProcessingWaveform) {
  //     return const Padding(
  //       padding: EdgeInsets.symmetric(vertical: 20.0),
  //       child: Row(
  //         mainAxisAlignment: MainAxisAlignment.center,
  //         children: [
  //           SizedBox(
  //               width: 16,
  //               height: 16,
  //               child: CircularProgressIndicator(strokeWidth: 2)),
  //           SizedBox(width: 12),
  //           Text('Analyzing Audio...', style: TextStyle(color: Colors.white70)),
  //         ],
  //       ),
  //     );
  //   }
  //
  //   if (_audioWaveform == null ||
  //       _audioWaveform!.isEmpty ||
  //       _controller == null ||
  //       !_controller!.value.isInitialized) {
  //     return const SizedBox.shrink();
  //   }
  //
  //   final totalDuration = _controller!.value.duration;
  //   final waveformWidth =
  //       (totalDuration.inMilliseconds / 1000.0) * _pixelsPerSecond;
  //
  //   return CustomPaint(
  //     painter: _WaveformPainter(
  //       waveformData: _audioWaveform!,
  //       totalWidth: waveformWidth,
  //     ),
  //     size: Size(waveformWidth, 60), // Set the height of the waveform
  //   );
  // }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to Analyze a Race'),
        content: SingleChildScrollView(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
              children: const <TextSpan>[
                TextSpan(
                    text: 'Follow these two main steps:\n\n',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(
                    text: '1. TIMING MODE\n',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(
                    text:
                        'Play the video and use the large central button to record the exact time for each checkpoint (e.g., Start, Breakout, Turn, Finish). Use the slow-motion and rewind buttons for precision.\n\n'),
                TextSpan(
                    text: '2. ATTRIBUTES MODE\n',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(
                    text:
                        'After all timing points are recorded, switch to this mode. The video will jump to each lap, allowing you to use the counters to record strokes, breaths, and underwater kicks for each interval.\n\n'),
                TextSpan(
                    text: 'VIEW RESULTS\n',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(
                    text:
                        'Once you are done, tap the results icon in the top bar to see the complete analysis and save the race.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRace() async {
    final newEvent = await _selectRace();
    if (newEvent != null && mounted) {
      setState(() {
        _currentEvent = newEvent;
        _resetAnalysisState();
      });
    }
  }

  /// --- UX Improvement: Build a visual guide for recording checkpoints ---
  Widget _buildCheckpointGuide() {
    if (_currentEvent == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    List<Widget> guideItems = [];

    for (int i = 0; i < _currentEvent!.checkPoints.length; i++) {
      final cp = _currentEvent!.checkPoints[i];
      final isCurrent = i == _currentCheckPointIndex;
      final isDone = i < _currentCheckPointIndex;

      guideItems.add(
        Padding(
          key: _checkpointKeys.isNotEmpty ? _checkpointKeys[i] : null,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getDistanceForCheckpoint(cp, i),
                style: TextStyle(
                  color: isCurrent ? colorScheme.primary : Colors.white,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  fontSize: 11,
                ),
              ),
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
                size: 20,
              ),
            ],
          ),
        ),
      );

      if (i < _currentEvent!.checkPoints.length - 1) {
        guideItems.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Divider(
                color: isDone ? Colors.green.shade400 : Colors.white30,
                thickness: 1.5,
              ),
            ),
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: Row(children: guideItems),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentEvent?.name ?? 'Swim Analyzer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showHelpDialog,
            tooltip: 'How to Analyze',
          ),
          if (_currentEvent != null)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _recordedSegments.isEmpty ? _changeRace : null,
              tooltip: _recordedSegments.isEmpty
                  ? 'Change Race Type'
                  : 'Cannot change race after analysis has started',
            ),
          if (_recordedSegments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list_alt),
              onPressed: _viewResults,
              tooltip: 'View Results',
            ),
        ],
      ),
      body: _controller?.value.isInitialized ?? false
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
                Expanded(child: _buildControlsOverlay()),
              ],
            )
          : Center(
              child: _isLoadingVideo
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 50.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Preparing Video... $_loadingDetails',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          const LinearProgressIndicator(),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.video_library_outlined,
                            size: 80,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Start Your Analysis',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap the "Load Video" button below to select a race video from your device.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
      floatingActionButton: _controller == null
          ? FloatingActionButton.extended(
              onPressed: _isLoadingVideo ? null : _pickVideo,
              label: const Text('Load Video'),
              icon: const Icon(Icons.video_library),
            )
          : null,
    );
  }

  Widget _buildControlsOverlay() {
    return Column(
      children: [
        const Spacer(),
        if (_controller != null) ...[
          _buildPrecisionScrubber(),
        ],
        Container(
          color: Colors.black.withAlpha(40),
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_AnalysisMode>(
                segments: const [
                  ButtonSegment(
                      value: _AnalysisMode.timing,
                      icon: Icon(Icons.timer),
                      label: Text('Timing')),
                  ButtonSegment(
                      value: _AnalysisMode.attributes,
                      icon: Icon(Icons.assessment),
                      label: Text('Attributes')),
                ],
                selected: {_analysisMode},
                onSelectionChanged: (selection) =>
                    setState(() => _analysisMode = selection.first),
              ),
              const SizedBox(height: 16),
              if (_analysisMode == _AnalysisMode.timing)
                _buildTimingControls()
              else
                _buildAttributeControls(),
              const SizedBox(height: 12),
              _buildTransportControls(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimingControls() {
    if (_currentEvent == null) return const SizedBox.shrink();
    final isFinished =
        _recordedSegments.any((s) => s.checkPoint == CheckPoint.finish);
    final nextCheckPointName = isFinished
        ? 'Finished'
        : 'Record ${_getDistanceForCheckpoint(_currentEvent!.checkPoints[_currentCheckPointIndex], _currentCheckPointIndex)}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCheckpointGuide(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_5),
                onPressed: _rewindAndUndo,
                iconSize: 40,
                tooltip: 'Rewind & Undo',
                color: Colors.white,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    onPressed: isFinished ? null : _recordCheckpoint,
                    backgroundColor: isFinished
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                    heroTag: 'timingFAB',
                    child: Icon(isFinished ? Icons.check : Icons.flag),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nextCheckPointName,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(_isSlowMotion
                    ? Icons.slow_motion_video_rounded
                    : Icons.slow_motion_video_outlined),
                onPressed: _toggleSlowMotion,
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

  String _getDistanceForCheckpoint(CheckPoint cp, int index) {
    if (_currentEvent == null) return cp.name;
    int turnCount = 0;
    for (int i = 0; i < index; i++) {
      if (_currentEvent!.checkPoints[i] == CheckPoint.turn) {
        turnCount++;
      }
    }
    final lapLength = _currentEvent!.poolLength.distance;

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
        return '${_currentEvent!.distance}m';
    }
  }

  void _seekToIntervalStart(int intervalIndex) {
    if (intervalIndex < _recordedSegments.length) {
      _controller
          ?.seekTo(_recordedSegments[intervalIndex].splitTimeOfTotalRace);
    }
  }

  void _changeAttributeInterval(int delta) {
    final newIndex = _attributeEditingIntervalIndex + delta;
    if (newIndex >= 0 && newIndex < _recordedSegments.length - 1) {
      setState(() {
        _attributeEditingIntervalIndex = newIndex;
      });
      _seekToIntervalStart(newIndex);
    }
  }

  Widget _buildAttributeControls() {
    if (_recordedSegments.length < 2 || _currentEvent == null) {
      return const Text('Record at least one interval to edit attributes.',
          style: TextStyle(color: Colors.white70));
    }

    final currentAttributes =
        _intervalAttributes[_attributeEditingIntervalIndex];
    final bool isBreaststroke = _currentEvent!.stroke == Stroke.breaststroke;

    final startCp = _currentEvent!.checkPoints[_attributeEditingIntervalIndex];
    final endCp =
        _currentEvent!.checkPoints[_attributeEditingIntervalIndex + 1];

    final startName =
        _getDistanceForCheckpoint(startCp, _attributeEditingIntervalIndex);
    final endName =
        _getDistanceForCheckpoint(endCp, _attributeEditingIntervalIndex + 1);

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
              color: Colors.white,
            ),
            Text(
              'EDITING: $startName -> $endName',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  _attributeEditingIntervalIndex < _recordedSegments.length - 2
                      ? () => _changeAttributeInterval(1)
                      : null,
              color: Colors.white,
            ),
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
                    setState(() => currentAttributes.dolphinKickCount--),
              ),
            if (isSwimming)
              _buildAttributeCounter(
                label: 'Strokes',
                count: currentAttributes.strokeCount,
                onIncrement: () =>
                    setState(() => currentAttributes.strokeCount++),
                onDecrement: () =>
                    setState(() => currentAttributes.strokeCount--),
              ),
            if (isSwimming && !isBreaststroke)
              _buildAttributeCounter(
                label: 'Breaths',
                count: currentAttributes.breathCount,
                onIncrement: () =>
                    setState(() => currentAttributes.breathCount++),
                onDecrement: () =>
                    setState(() => currentAttributes.breathCount--),
              ),
          ],
        )
      ],
    );
  }

  Widget _buildAttributeCounter({
    required String label,
    required int count,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: count > 0 ? onDecrement : null,
              iconSize: 30,
              color: count > 0 ? Colors.white : Colors.white30,
            ),
            Text(
              '$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onIncrement,
              iconSize: 30,
              color: Colors.white,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransportControls() {
    if (_controller == null) return const SizedBox.shrink();

    // PERFORMANCE OPTIMIZATION: Use the `child` parameter of the ValueListenableBuilder.
    // This pre-builds the static parts of the widget tree (the Row and its children),
    // preventing them from being rebuilt every time the video position changes.
    return ValueListenableBuilder(
      valueListenable: _controller!,
      builder: (context, VideoPlayerValue value, Widget? child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          // The pre-built child is used here.
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.fast_rewind),
            onPressed: () {
              final currentPosition = _controller!.value.position;
              final newPosition = currentPosition - const Duration(seconds: 2);
              _controller?.seekTo(
                  newPosition.isNegative ? Duration.zero : newPosition);
            },
            color: Colors.white,
            iconSize: 32,
          ),
          // The play/pause button is the only part that *truly* needs to rebuild
          // based on the `value`, but for simplicity and given its small cost,
          // rebuilding the whole row is acceptable. The main optimization is avoiding
          // rebuilding the widgets within the builder. A more granular approach
          // would be to have another builder just for the play/pause icon.
          // For now, this is a significant improvement.
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller!,
            builder: (context, value, child) {
              return IconButton(
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (value.isPlaying) {
                    userPressedPlay = false;
                    _controller!.pause();
                  } else {
                    userPressedPlay = true;
                    _controller!.play();
                  }
                  debugPrint('UserPressedPlay: ${userPressedPlay.toString()}');
                },
                color: Colors.white,
                iconSize: 48,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.fast_forward),
            onPressed: () {
              final currentPosition = _controller!.value.position;
              final newPosition = currentPosition + const Duration(seconds: 2);
              _controller?.seekTo(newPosition);
            },
            color: Colors.white,
            iconSize: 32,
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final Duration totalDuration;
  final double pixelsPerSecond;
  final String Function(Duration) formatDuration;

  _TimelinePainter({
    required this.totalDuration,
    required this.pixelsPerSecond,
    required this.formatDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // PERFORMANCE OPTIMIZATION: Calculate total ticks once.
    // Use `size.width` to avoid drawing ticks that are off-screen.
    final maxVisibleSeconds = size.width / pixelsPerSecond;
    final totalTicks = (maxVisibleSeconds * 10).ceil();

    for (int i = 0; i <= totalTicks; i++) {
      final xPos = (i / 10.0) * pixelsPerSecond;
      if (i % 10 == 0) {
        // Every full second
        canvas.drawLine(Offset(xPos, 10), Offset(xPos, size.height), tickPaint);
        textPainter.text = TextSpan(
          text: formatDuration(Duration(seconds: i ~/ 10)),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(xPos - (textPainter.width / 2), -5));
      } else {
        // Every 100 milliseconds
        canvas.drawLine(Offset(xPos, 25), Offset(xPos, size.height), tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.totalDuration != totalDuration ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}

/// --- Custom Painter for the Audio Waveform ---
class _WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double totalWidth;
  final Paint wavePaint;

  _WaveformPainter({
    required this.waveformData,
    required this.totalWidth,
  }) : wavePaint = Paint()
          ..color = Colors.lightBlueAccent.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty || totalWidth <= 0) return;

    final middleY = size.height / 2;
    final samplesPerPixel = waveformData.length / totalWidth;
    final int width = size.width.toInt();

    // PERFORMANCE OPTIMIZATION: Pre-calculate min/max values for each pixel column.
    // This avoids creating sublists and iterating multiple times over the same data.
    final List<double> minValues = List.filled(width, 1.0);
    final List<double> maxValues = List.filled(width, -1.0);

    for (int i = 0; i < waveformData.length; i++) {
      final pixelIndex = (i / samplesPerPixel).floor();
      if (pixelIndex >= width) break;

      final sample = waveformData[i];
      if (sample < minValues[pixelIndex]) {
        minValues[pixelIndex] = sample;
      }
      if (sample > maxValues[pixelIndex]) {
        maxValues[pixelIndex] = sample;
      }
    }

    // Now, draw the lines based on the pre-calculated min/max values.
    for (int i = 0; i < width; i++) {
      final maxVal = maxValues[i];
      final minVal = minValues[i];

      if (minVal <= maxVal) {
        // Ensure there's a valid range to draw.
        final yMax = middleY - (maxVal * middleY);
        final yMin = middleY - (minVal * middleY);
        canvas.drawLine(
            Offset(i.toDouble(), yMin), Offset(i.toDouble(), yMax), wavePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    // PERFORMANCE OPTIMIZATION: Only repaint if the waveform data or width changes.
    // Using identity check for waveformData is fast and effective if the list is replaced, not mutated.
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.totalWidth != totalWidth;
  }
}
