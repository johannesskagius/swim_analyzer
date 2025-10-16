import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

Widget _buildPrecisionScrubber({required VideoPlayerController _controller}) {
  if (_controller == null || !_controller!.value.isInitialized) {
    return const SizedBox.shrink();
  }
  final totalDuration = _controller!.value.duration;
  final timelineWidth =
      (totalDuration.inMilliseconds / 1000.0) * _pixelsPerSecond;
  return Row(
    children: [
      IconButton(
        icon: const Icon(Icons.remove),
        onPressed: () => _seekFrames(-1),
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
            } else if (notification is ScrollEndNotification && _isScrubbing) {
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
        icon: const Icon(Icons.add),
        onPressed: () => _seekFrames(1),
      ),
    ],
  );
}