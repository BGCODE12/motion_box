import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/libre_cuts_service.dart';
import '../controllers/timeline_controller.dart';
import '../models/timeline_models.dart';
import '../../../services/export_service.dart';
import '../widgets/timeline_view.dart';
import '../widgets/track_header_panel.dart';
import '../widgets/draggable_text_overlay_widget.dart';

import '../services/live_audio_sync_manager.dart';

/// CapCut-Grade NLE Timeline Editor Screen.
/// Combines live player preview, fixed playhead timeline canvas,
/// 15Hz throttled seek scrubbing, text overlays, and hardware-accelerated LibreCuts export.
class TimelineEditorScreen extends StatefulWidget {
  final String? initialVideoPath;

  const TimelineEditorScreen({
    super.key,
    this.initialVideoPath,
  });

  @override
  State<TimelineEditorScreen> createState() => _TimelineEditorScreenState();
}

class _TimelineEditorScreenState extends State<TimelineEditorScreen> {
  late TimelineController _controller;
  final LibreCutsService _libreCutsService = LibreCutsService();
  LiveAudioSyncManager? _audioSyncManager;

  VideoPlayerController? _videoPlayerController;
  bool _isRendering = false;
  int _renderProgress = 0;

  // BUG-05 FIX: Store subscription so we can cancel it in dispose().
  // Without this the callback holds a reference to the State object forever,
  // preventing GC and firing on a detached context after the screen is popped.
  StreamSubscription<RenderProgress>? _exportProgressSub;

  static const Color colorHeaderBg = Color(0xFF161B24);
  static const Color colorToolbarBg = Color(0xFF13171D);

  @override
  void initState() {
    super.initState();
    _controller = TimelineController();
    _audioSyncManager = LiveAudioSyncManager(_controller);


    if (widget.initialVideoPath != null && File(widget.initialVideoPath!).existsSync()) {
      _initVideoPlayer(widget.initialVideoPath!);
    }

    // BUG-05 FIX: Assign to field so it can be cancelled in dispose().
    _exportProgressSub = _libreCutsService.progressStream.listen((event) {
      if (mounted) {
        setState(() {
          if (event.status == RenderStatus.rendering) {
            _renderProgress = event.progress;
          } else if (event.status == RenderStatus.success) {
            _isRendering = false;
            _showSuccessDialog(event.outputPath ?? '');
          } else if (event.status == RenderStatus.error) {
            _isRendering = false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Export Error: ${event.errorMessage}'),
                backgroundColor: AppTheme.secondary,
              ),
            );
          }
        });
      }
    });
  }

  Future<void> _initVideoPlayer(String path) async {
    try {
      // BUG-06 FIX: Detach the old player from the controller BEFORE disposing it.
      // Without this, _onVideoPlayerTick listener fires into a disposed controller
      // on the next ExoPlayer callback — causing StateError: controller disposed.
      _controller.detachVideoPlayer(); // Detach to prevent StateError
      _videoPlayerController?.dispose();
      _videoPlayerController = VideoPlayerController.file(File(path));
      await _videoPlayerController!.initialize();
      _controller.attachVideoPlayer(_videoPlayerController!);
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing VideoPlayer: $e');
    }
  }

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      await _initVideoPlayer(path);

      // Add to video track
      final clip = TimelineClip(
        id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
        title: result.files.single.name,
        mediaPath: path,
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: _videoPlayerController?.value.duration.inMilliseconds.toDouble() ?? 10000.0,
      );

      _controller.addClipToTrack('track_video_main', clip);
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final fileName = result.files.single.name;

      // BUG-14 FIX: Read the actual audio file duration instead of hardcoding 15s.
      // A hardcoded 15000ms causes the FFmpeg recipe to request silence-padding
      // for any file shorter than 15s, producing an unexpected export result.
      double durationMs = 15000.0; // Safe fallback
      try {
        final probe = VideoPlayerController.file(File(path));
        await probe.initialize();
        durationMs = probe.value.duration.inMilliseconds.toDouble();
        await probe.dispose();
        debugPrint('=> [_pickAudioFile] Actual duration: ${durationMs.toStringAsFixed(0)} ms');
      } catch (e) {
        debugPrint('=> [_pickAudioFile] Could not probe duration, using fallback: $e');
      }

      _controller.addAudioClip(
        title: fileName,
        audioPath: path,
        durationMs: durationMs,
      );
    }
  }

  void _showAddTextDialog() {
    // BUG-10 FIX: Create the TextEditingController inside a StatefulBuilder so
    // it gets disposed when the dialog closes, preventing the TextInputConnection
    // memory leak that occurs when the controller is created in a plain builder.
    showDialog(
      context: context,
      builder: (ctx) {
        final textEditingController = TextEditingController(text: 'MotionBox Overlay');
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.title_rounded, color: AppTheme.primary, size: 24),
                  SizedBox(width: 8),
                  Text('Add Text Overlay', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: TextField(
                controller: textEditingController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter text...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    textEditingController.dispose();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final text = textEditingController.text.trim();
                    if (text.isNotEmpty) {
                      _controller.addTextClip(text: text);
                    }
                    textEditingController.dispose();
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: const Text('Add to Timeline', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportProject() async {
    debugPrint('=> [Export] Button pressed');

    // ── Guard: find valid source video path ─────────────────────────────────
    // Walk ALL video-track clips until we find one with a real mediaPath.
    String sourcePath = '';
    for (final track in _controller.tracks) {
      if (track.type == TrackType.video) {
        for (final clip in track.clips) {
          if (clip.mediaPath != null && clip.mediaPath!.isNotEmpty) {
            sourcePath = clip.mediaPath!;
            break;
          }
        }
      }
      if (sourcePath.isNotEmpty) break;
    }
    // Fall back to the widget's initial video path
    if (sourcePath.isEmpty) {
      sourcePath = widget.initialVideoPath ?? '';
    }

    if (sourcePath.isEmpty) {
      debugPrint('=> [Export] ABORTED — no source video loaded');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please load a source video before exporting.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    debugPrint('=> [Export] Source path resolved: $sourcePath');

    setState(() {
      _isRendering = true;
      _renderProgress = 0;
    });

    // ── Stuck-state safety timer (60 s) ─────────────────────────────────────
    // If neither a success nor error event arrives within 60 seconds, we reset
    // the UI so the Export button is never permanently locked.
    bool completedByStream = false;
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted && _isRendering && !completedByStream) {
        debugPrint('=> [Export] TIMEOUT — resetting _isRendering after 60s');
        setState(() => _isRendering = false);
      }
    });

    // ── Build output path ────────────────────────────────────────────────────
    final docsDir = await getApplicationDocumentsDirectory();
    final outputPath =
        '${docsDir.path}/motionbox_${DateTime.now().millisecondsSinceEpoch}.mp4';
    debugPrint('=> [Export] Output path: $outputPath');

    // ── Serialize the timeline recipe ────────────────────────────────────────
    final Map<String, dynamic> recipeMap;
    try {
      recipeMap = ExportService.buildExportRecipe(
        controller: _controller,
        sourcePath: sourcePath,
      );
    } catch (e) {
      debugPrint('=> [Export] ERROR building recipe: $e');
      setState(() => _isRendering = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export recipe error: $e'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    // Log a short preview of the generated JSON for quick MethodChannel debugging
    final previewJson = recipeMap.toString();
    debugPrint('=> [Export] JSON Payload generated (${previewJson.length} chars): '
        '${previewJson.substring(0, previewJson.length.clamp(0, 300))}...');

    // ── Invoke the native LibreCuts engine ───────────────────────────────────
    try {
      debugPrint('=> [Export] Invoking LibreCutsService.renderExport via MethodChannel...');
      final resultPath = await _libreCutsService.renderExport(
        recipeMap: recipeMap,
        sourcePath: sourcePath,
        outputPath: outputPath,
        resolution: 1080,
        fps: 30,
      );
      completedByStream = true;
      debugPrint('=> [Export] MethodChannel returned: $resultPath');
      // Success path is handled by progressStream.listen in initState().
      // The EventChannel "success" event fires before result.success() resolves,
      // so _isRendering and the dialog are already managed there.
    } catch (e) {
      completedByStream = true;
      debugPrint('=> [Export] Error: $e');
      if (mounted) {
        setState(() => _isRendering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export Failed: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }


  void _showSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
            SizedBox(width: 10),
            Text('Export Successful!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rendered with LibreCuts Hardware Engine:', style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(path, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // BUG-05 FIX: Cancel the export progress subscription FIRST.
    // This prevents the callback from firing on a detached context after dispose.
    _exportProgressSub?.cancel();
    _audioSyncManager?.dispose();
    // BUG-06 FIX: Detach the old player from the controller BEFORE disposing it.
    _controller.detachVideoPlayer();
    _videoPlayerController?.dispose();
    _controller.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter_rounded, color: AppTheme.primary, size: 20),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'MotionBox',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_rounded, color: Colors.white, size: 20),
            tooltip: 'Import Video',
            onPressed: _pickVideoFile,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0, top: 8.0, bottom: 8.0),
            child: ElevatedButton.icon(
              onPressed: _isRendering ? null : _exportProject,
              icon: const Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
              label: const Text('Export', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minimumSize: const Size(60, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],

      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. Live Video Preview Canvas
              Expanded(
                flex: 5,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                            ? Center(
                                child: AspectRatio(
                                  aspectRatio: _videoPlayerController!.value.aspectRatio,
                                  child: VideoPlayer(_videoPlayerController!),
                                ),
                              )
                            : _buildEmptyPreviewPlaceholder(),

                        // Live Draggable Text Overlay Layer (Synchronized with Playhead & Controller State)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                            return ListenableBuilder(
                              listenable: _controller,
                              builder: (context, _) {
                                return ValueListenableBuilder<double>(
                                  valueListenable: _controller.currentPositionMs,
                                  builder: (context, currentMs, _) {
                                    final activeTextClips = <TimelineClip>[];
                                    for (final track in _controller.tracks) {
                                      if (track.type == TrackType.text) {
                                        for (final clip in track.clips) {
                                          if (currentMs >= clip.startMs && currentMs <= clip.endMs) {
                                            activeTextClips.add(clip);
                                          }
                                        }
                                      }
                                    }

                                    if (activeTextClips.isEmpty) return const SizedBox.shrink();

                                    return Stack(
                                      children: activeTextClips.map((clip) {
                                        return DraggableTextOverlayWidget(
                                          key: ValueKey(clip.id),
                                          clip: clip,
                                          controller: _controller,
                                          canvasSize: canvasSize,
                                        );
                                      }).toList(),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),

                      ],
                    ),
                  ),
                ),
              ),

              // 2. TOP HEADER ROW (Matching dddd.PNG mockup)
              Container(
                color: colorHeaderBg,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Large White Play/Pause Button
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) {
                        return IconButton(
                          icon: Icon(
                            _controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _controller.togglePlayPause,
                        );
                      },
                    ),

                    // Center: Timecode Display (Current Time on top, Total Time below)
                    ValueListenableBuilder<double>(
                      valueListenable: _controller.currentPositionMs,
                      builder: (context, currentMs, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatMs(currentMs),
                              style: const TextStyle(
                                color: Color(0xFF8BA2B9),
                                fontSize: 13,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatMs(_controller.totalDurationMs),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // Right: Undo & Redo Action Buttons (wired to undo/redo stack)
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) {
                        return Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.undo_rounded,
                                color: _controller.canUndo ? Colors.white70 : Colors.white24,
                                size: 20,
                              ),
                              onPressed: _controller.canUndo ? _controller.undo : null,
                              tooltip: 'Undo',
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.redo_rounded,
                                color: _controller.canRedo ? Colors.white70 : Colors.white24,
                                size: 20,
                              ),
                              onPressed: _controller.canRedo ? _controller.redo : null,
                              tooltip: 'Redo',
                            ),
                          ],
                        );
                      },
                    ),

                  ],
                ),
              ),

              // 3. TIMELINE BODY (Row: Fixed Left Track Headers + Right Scrollable Canvas)
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    // Left Fixed Track Header Panel
                    TrackHeaderPanel(
                      controller: _controller,
                      onAddVideo: _pickVideoFile,
                      onAddText: _showAddTextDialog,
                      onAddAudio: _pickAudioFile,
                    ),

                    // Right Scrollable Timeline Canvas
                    Expanded(
                      child: TimelineView(controller: _controller),
                    ),
                  ],
                ),
              ),

              // 4. BOTTOM TOOLBAR (Matching dddd.PNG mockup)
              Container(
                color: colorToolbarBg,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.view_stream_rounded, color: Colors.white60, size: 22),
                      tooltip: 'Tracks',
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.crop_rounded, color: Colors.white60, size: 22),
                      tooltip: 'Crop / Transform',
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_cut_rounded, color: Colors.white60, size: 22),
                      tooltip: 'Split at Playhead',
                      onPressed: () => _controller.splitClipAtPlayhead(),
                    ),
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) {
                        return IconButton(
                          icon: Icon(
                            _controller.isMainVideoMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: _controller.isMainVideoMuted ? Colors.redAccent : Colors.white60,
                            size: 22,
                          ),
                          tooltip: 'Volume',
                          onPressed: _controller.toggleMainVideoMute,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white60, size: 22),
                      tooltip: 'Delete Clip',
                      onPressed: () {
                        if (_controller.selectedClipId != null) {
                          _controller.deleteClip(_controller.selectedClipId!);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Render Progress Modal Overlay
          if (_isRendering)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Center(
                child: Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTheme.primary),
                        const SizedBox(height: 20),
                        const Text('LibreCuts Engine Exporting...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        Text('$_renderProgress%', style: const TextStyle(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyPreviewPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_creation_outlined, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('No Video Loaded', style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _pickVideoFile,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Load Source Video'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  String _formatMs(double ms) {
    final duration = Duration(milliseconds: ms.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
