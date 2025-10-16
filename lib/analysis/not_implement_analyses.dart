import 'package:flutter/material.dart';

class StrokeAnalysisPage extends StatelessWidget {
  const StrokeAnalysisPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Stroke Analysis")),
        body: const Center(child: Text("Stroke Analysis Page")),
      );
}

class TurnAnalysisPage extends StatelessWidget {
  const TurnAnalysisPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Turn Analysis")),
        body: const Center(child: Text("Turn Analysis Page")),
      );
}
