// ... imports remain the same

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:swim_analyzer/analysis/race/quick_analysis_ui.dart';
import 'package:swim_analyzer/analysis/race/race_analysis_modes.dart';
import 'package:swim_analyzer/analysis/race/results_page.dart';
import 'package:swim_apps_shared/swim_apps_shared.dart';
import 'package:video_player/video_player.dart';

import '../time_line_painter.dart';
import 'analysis_level.dart';
import 'analysis_ui_base.dart';
import 'full_analysis_ui.dart';

class RaceAnalysisView extends StatefulWidget {
  final AppUser appUser;
  const RaceAnalysisView({super.key, required this.appUser});

  @override
  State<RaceAnalysisView> createState() => _RaceAnalysisViewState();
}

class _RaceAnalysisViewState extends State<RaceAnalysisView> {
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();
  bool _isLoadingVideo = false;

  AnalysisType? analysisType;
  Event? _currentEvent;

  final GlobalKey<FullAnalysisUIState> _fullAnalysisKey = GlobalKey();
  final GlobalKey<QuickAnalysisUIState> _quickAnalysisKey = GlobalKey();

  // FIX: Add a callback method to be triggered by child widgets.
  void _onChildStateChanged() {
    setState(() {
      // This empty call is enough to trigger a rebuild of this widget,
      // which will re-evaluate _buildAppBarActions.
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final isPermissionGranted = await _requestPermissions();
    if (!isPermissionGranted || !mounted) return;

    setState(() => _isLoadingVideo = true);

    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    final selectedAnalysisType = await _selectAnalysisType();
    if (selectedAnalysisType == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    final selectedEvent = await _selectRace();
    if (selectedEvent == null || !mounted) {
      if (mounted) setState(() => _isLoadingVideo = false);
      return;
    }

    await _initializeVideoPlayer(file, selectedAnalysisType, selectedEvent);
  }

  Future<bool> _requestPermissions() async {
    final status = await (Platform.isIOS
        ? Permission.photos.request()
        : Permission.videos.request());
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permission is required to select a video.')),
      );
      return false;
    }
    return true;
  }

  Future<AnalysisType?> _selectAnalysisType() {
    return showDialog<AnalysisType>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Analysis Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Full Analysis'),
              subtitle:
                  const Text('Record detailed splits, strokes, breaths, etc.'),
              onTap: () => Navigator.of(context).pop(AnalysisType.full),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Quick Analysis'),
              subtitle: const Text('Record splits and strokes per lap.'),
              onTap: () => Navigator.of(context).pop(AnalysisType.quick),
            ),
          ],
        ),
      ),
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
                title: Text('25m Race'),
                onTap: () => Navigator.of(context).pop(TwentyFiveMeterRace),
              ),
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
        );
      },
    );

    if (selectedRaceType == null) return null;

    final selectedStroke = await showDialog<Stroke>(
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
                onTap: () => Navigator.of(context).pop(stroke),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selectedStroke == null) return null;
    if (selectedRaceType == TwentyFiveMeterRace) {
      return TwentyFiveMeterRace(stroke: selectedStroke);
    } else if (selectedRaceType == FiftyMeterRace) {
      return FiftyMeterRace(stroke: selectedStroke);
    } else if (selectedRaceType == HundredMetersRace) {
      return HundredMetersRace(stroke: selectedStroke);
    }
    return null;
  }

  Future<void> _initializeVideoPlayer(
      XFile file, AnalysisType type, Event event) async {
    _controller?.dispose();
    final newController = VideoPlayerController.file(File(file.path));

    try {
      await newController.initialize();
      if (!mounted) {
        newController.dispose();
        return;
      }
      setState(() {
        _controller = newController;
        analysisType = type;
        _currentEvent = event;
        _isLoadingVideo = false;
      });
    } catch (e) {
      print('Error initializing video: $e');
      if (mounted) setState(() => _isLoadingVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_buildAppBarTitle()),
        actions: _buildAppBarActions(),
      ),
      body: _buildBody(),
      floatingActionButton: _buildFab(),
    );
  }

  String _buildAppBarTitle() {
    if (analysisType == null) return 'Swim Analyzer';
    return analysisType == AnalysisType.full
        ? _currentEvent?.name ?? 'Full Analysis'
        : 'Quick Analysis';
  }

  List<Widget> _buildAppBarActions() {
    bool isFinished = false;
    VoidCallback? viewResults;

    if (mounted) {
      if (analysisType == AnalysisType.full &&
          _fullAnalysisKey.currentState != null) {
        isFinished = _fullAnalysisKey.currentState!.isAnalysisFinished();
        viewResults = _fullAnalysisKey.currentState!.viewResults;
      } else if (analysisType == AnalysisType.quick &&
          _quickAnalysisKey.currentState != null) {
        isFinished = _quickAnalysisKey.currentState!.isAnalysisFinished();
        viewResults = _quickAnalysisKey.currentState!.viewResults;
      }
    }

    if (isFinished) {
      return [
        IconButton(
          icon: const Icon(Icons.list_alt),
          onPressed: viewResults,
          tooltip: 'View Results',
        ),
      ];
    }
    return [];
  }

  Widget _buildBody() {
    if (_controller?.value.isInitialized ?? false) {
      switch (analysisType) {
        case AnalysisType.full:
          return FullAnalysisUI(
            key: _fullAnalysisKey,
            controller: _controller!,
            event: _currentEvent!,
            onStateChanged: _onChildStateChanged, // FIX: Pass the callback down
            appUser: widget.appUser,
          );
        case AnalysisType.quick:
          return QuickAnalysisUI(
            key: _quickAnalysisKey,
            controller: _controller!,
            event: _currentEvent!,
            onStateChanged: _onChildStateChanged, // FIX: Pass the callback down
            appUser: widget.appUser,
          );
        default:
          return _buildInitialPrompt();
      }
    }
    return _isLoadingVideo ? _buildLoadingIndicator() : _buildInitialPrompt();
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 50.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Preparing Video...', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined,
                size: 80, color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 16),
            const Text('Start Your Analysis',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
                'Tap the "Load Video" button below to select a race video from your device.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget? _buildFab() {
    if (_controller == null) {
      return FloatingActionButton.extended(
        onPressed: _isLoadingVideo ? null : _pickVideo,
        label: const Text('Load Video'),
        icon: const Icon(Icons.video_library),
      );
    }
    return null;
  }
}