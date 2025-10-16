import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../model/start_analyze.dart';

/// A page to display the results of a start analysis, including video playback and metrics.
class VideoAnalysisPage extends StatefulWidget {
  final StartAnalysis analysis;

  const VideoAnalysisPage({super.key, required this.analysis});

  @override
  State<VideoAnalysisPage> createState() => _VideoAnalysisPageState();
}

class _VideoAnalysisPageState extends State<VideoAnalysisPage> {
  late VideoPlayerController _controller;
  late Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();
    // Note: In a real app, you'd want to handle the case where the file path might not be valid.
    _controller = VideoPlayerController.file(File(widget.analysis.videoPath));
    _initializeVideoPlayerFuture = _controller.initialize().then((_) {
      _controller.setLooping(true);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Results'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder(
              future: _initializeVideoPlayerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && _controller.value.isInitialized) {
                  return Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_controller.value.isPlaying) {
                                  _controller.pause();
                                } else {
                                  _controller.play();
                                }
                              });
                            },
                            child: AnimatedOpacity(
                              opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                color: Colors.black26,
                                child: const Center(
                                  child: Icon(Icons.play_arrow, color: Colors.white, size: 100.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
            const SizedBox(height: 24),
            Text('Analysis ID: ${widget.analysis.id}', style: Theme.of(context).textTheme.bodySmall),
            Text('Analyzed on: ${widget.analysis.analysisDate.toLocal()}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            const Text('Performance Metrics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            _buildMetricRow('Reaction Time', widget.analysis.reactionTime),
            _buildMetricRow('Flight Time', widget.analysis.flightTime),
            _buildMetricRow('Entry Angle', widget.analysis.entryAngle, unit: '°'),
            _buildMetricRow('Back Leg Angle', widget.analysis.backLegAngle, unit: '°'),
            _buildMetricRow('Front Leg Angle', widget.analysis.frontLegAngle, unit: '°'),
            _buildMetricRow('Time to 15m', widget.analysis.timeTo15m),
            _buildMetricRow('Breakout Time', widget.analysis.breakoutTime),
            _buildMetricRow('Breakout Dolphin Kicks', widget.analysis.breakoutDolphinKicks),
            _buildMetricRow('Time to First Dolphin Kick', widget.analysis.timeToFirstDolphinKick),
            _buildMetricRow('Time to Pull-Out', widget.analysis.timeToPullOut),
            _buildMetricRow('Gliding Time Post Pull-Out', widget.analysis.timeGlidingPostPullOut),
            _buildMetricRow('Glide Face After Pull-Out', widget.analysis.glidFaceAfterPullOut),
            _buildMetricRow('Speed @ 5m', widget.analysis.speedToFiveMeters, unit: 'm/s'),
            _buildMetricRow('Speed @ 10m', widget.analysis.speedTo10Meters, unit: 'm/s'),
            _buildMetricRow('Speed @ 15m', widget.analysis.speedTo15Meters, unit: 'm/s'),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, dynamic value, {String? unit}) {
    String valueString = 'N/A';
    if (value != null) {
      if (value is Duration) {
        valueString = '${(value.inMilliseconds / 1000).toStringAsFixed(2)}s';
      } else if (value is double) {
        valueString = value.toStringAsFixed(2);
      } else {
        valueString = value.toString();
      }
      if (unit != null) {
        valueString += ' $unit';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:', style: const TextStyle(fontSize: 16)),
          Text(valueString, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}