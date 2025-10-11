import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:swim_analyzer/video_analysis_page.dart';
import 'package:video_player/video_player.dart';

import 'model/start_analysis.dart';

class OffTheBlockAnalysisPage extends StatefulWidget {
  const OffTheBlockAnalysisPage({super.key});

  @override
  State<OffTheBlockAnalysisPage> createState() => _OffTheBlockAnalysisPageState();
}

class _OffTheBlockAnalysisPageState extends State<OffTheBlockAnalysisPage> {
  bool _isLoading = false;
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();

  final Set<String> _selectedAttributes = {};

  List<String> analyzableOffTheBlockAttributes = [
    'startPositionBackLegAngle',
    'startPositionFrontLegAngle',
    'reactionTime',
    'flightTime',
    'entryStartAngle',
    'entryHipAngle',
    'entryFinishAngle',
  ];

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isLoading = true;
      _selectedAttributes.clear();
    });

    try {
      final XFile? pickedFile =
      await _picker.pickVideo(source: ImageSource.gallery);

      if (pickedFile == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await _controller?.dispose();
      final newController = VideoPlayerController.file(File(pickedFile.path));
      await newController.initialize();

      if (!mounted) {
        await newController.dispose();
        return;
      }

      setState(() {
        _controller = newController;
        _controller!.setLooping(true);
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

  void _analyzeVideo() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final analysis = StartAnalysis(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      videoPath: _controller!.dataSource.replaceFirst('file://', ''),
      analysisDate: DateTime.now(),
      enabledAttributes: _selectedAttributes,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoAnalysisPage(
          analysis: analysis,
        ),
      ),
    );
  }

  String _formatAttributeName(String attribute) {
    final spaced = attribute.replaceAllMapped(
        RegExp(r'(?<=[a-z])[A-Z]'), (match) => ' ${match.group(0)}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // RENAMED: Title updated in the AppBar
        title: const Text("Off the Block Analysis"),
      ),
      body: Column(
        children: <Widget>[
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
          if (_controller != null && !_isLoading) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Select Attributes to Analyze',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              flex: 3,
              child: Scrollbar(
                // RENAMED: Using the updated list variable
                child: ListView(
                  children: analyzableOffTheBlockAttributes.map((attribute) {
                    return CheckboxListTile(
                      title: Text(_formatAttributeName(attribute)),
                      value: _selectedAttributes.contains(attribute),
                      onChanged: (bool? isSelected) {
                        setState(() {
                          if (isSelected == true) {
                            _selectedAttributes.add(attribute);
                          } else {
                            _selectedAttributes.remove(attribute);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildVideoSelectionPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Please select a video to begin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            VideoPlayer(_controller!),
            _ControlsOverlay(controller: _controller!),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _pickVideo,
            icon: const Icon(Icons.video_library),
            label: Text(_controller == null
                ? 'Select Video from Gallery'
                : 'Select Different Video'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _controller?.value.isInitialized == true &&
                !_isLoading &&
                _selectedAttributes.isNotEmpty
                ? _analyzeVideo
                : null,
            icon: const Icon(Icons.analytics),
            // RENAMED: Button text updated
            label: const Text('Analyze Off the Block'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size(double.infinity, 50),
              textStyle: const TextStyle(fontSize: 16),
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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Stack(
          children: <Widget>[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 50),
              reverseDuration: const Duration(milliseconds: 200),
              child: controller.value.isPlaying
                  ? const SizedBox.shrink()
                  : Container(
                color: Colors.black26,
                child: const Center(
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 100.0,
                    semanticLabel: 'Play',
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
            ),
          ],
        );
      },
    );
  }
}
