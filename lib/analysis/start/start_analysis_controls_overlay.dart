import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ControlsOverlay extends StatelessWidget {
  const ControlsOverlay({required this.controller});

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