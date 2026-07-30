import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../controllers/timeline_controller.dart';
import '../models/timeline_models.dart';

/// Live Audio Synchronization Manager — Performance-Optimized.
///
/// KEY FIXES applied here:
/// 1. NO longer listens to `currentPositionMs` (60fps ValueNotifier).
///    Instead, uses a low-frequency 8Hz Timer (every 125ms) for sync checks.
/// 2. `setVolume()` is only called once when volume CHANGES, not on every tick.
/// 3. `seekTo()` (drift correction) is BLOCKED while audio is already playing
///    normally — only fires on play START or after a user drag ends.
/// 4. `File.existsSync()` is cached so I/O never happens in the sync hot path.
class LiveAudioSyncManager {
  final TimelineController controller;
  final Map<String, VideoPlayerController> _audioPlayers = {};
  final Map<String, String> _loadedPaths = {};
  final Map<String, double> _lastKnownVolume = {};
  final Set<String> _existenceCache = {}; // Cached File.existsSync results
  final Set<String> _missingCache = {}; // Cached negative File.existsSync results
  Timer? _syncTimer;
  VoidCallback? _controllerListener;

  // Track the last playback state to detect transitions
  bool _wasPlaying = false;
  bool _wasDragging = false;

  // BUG-08 FIX: Guard flag to prevent re-entrant concurrent sync calls.
  // _syncAudioStreams is async (has awaits for player init/seek/play).
  // Without this, the 125ms timer can fire a second invocation before the
  // first completes, causing concurrent mutations of _audioPlayers map.
  bool _isSyncing = false;

  LiveAudioSyncManager(this.controller) {
    _init();
  }

  void _init() {
    // FIX #1: Listen to controller (ChangeNotifier) for state changes only.
    // We do NOT listen to currentPositionMs ValueNotifier (60fps).
    _controllerListener = _onControllerStateChanged;
    controller.addListener(_controllerListener!);

    // BUG-12 FIX: Register forceSync() so deleteClip() can trigger an
    // immediate audio player teardown without waiting for the 125ms timer.
    controller.clipDeletedCallback = forceSync;

    // FIX #2: Use 8Hz (125ms) timer for sync checks during playback.
    // BUG-08 FIX: Skip if previous sync is still in progress (_isSyncing guard).
    _syncTimer = Timer.periodic(const Duration(milliseconds: 125), (_) {
      if (!_isSyncing) {
        _syncAudioStreams(isForcedSync: false);
      }
    });
  }

  /// Called when isPlaying or isUserDraggingTimeline changes.
  /// This is the only place we do an IMMEDIATE, low-latency sync response.
  void _onControllerStateChanged() {
    final isPlaying = controller.isPlaying;
    final isDragging = controller.isUserDraggingTimeline;

    final playingChanged = isPlaying != _wasPlaying;
    final draggingChanged = isDragging != _wasDragging;

    _wasPlaying = isPlaying;
    _wasDragging = isDragging;

    // Only do an immediate sync on play/pause or drag-end transitions.
    // This is the event-driven fast path — not a polling path.
    if (playingChanged || draggingChanged) {
      debugPrint('=> [LiveAudioSync] State change: playing=$isPlaying dragging=$isDragging — triggering immediate sync');
      _syncAudioStreams(isForcedSync: true);
    }
  }

  /// Public entry point: force an immediate synchronization pass.
  /// Called by [TimelineController.deleteClip] via the [clipDeletedCallback]
  /// hook so orphaned audio players are torn down in the same event-loop turn.
  void forceSync() {
    debugPrint('=> [LiveAudioSyncManager] forceSync() called — immediate teardown pass');
    _syncAudioStreams(isForcedSync: true);
  }

  Future<void> _syncAudioStreams({required bool isForcedSync}) async {
    // BUG-08 FIX: Skip re-entrant calls. Forced syncs (play/pause/drag-end)
    // are allowed to interrupt a polling sync; they set _isSyncing themselves.
    if (_isSyncing && !isForcedSync) return;
    _isSyncing = true;
    try {
      await _doSync(isForcedSync: isForcedSync);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _doSync({required bool isForcedSync}) async {
    final currentMs = controller.currentPositionMs.value;
    final isPlaying = controller.isPlaying;
    final isDragging = controller.isUserDraggingTimeline;

    // Collect active audio clips (use cached file existence check)
    final activeAudioClips = <TimelineClip>[];
    for (final track in controller.tracks) {
      if (track.type == TrackType.audio) {
        for (final clip in track.clips) {
          if (clip.mediaPath == null) continue;

          if (_missingCache.contains(clip.mediaPath)) {
            continue;
          }

          // Cache file existence — avoid I/O on every sync tick
          if (!_existenceCache.contains(clip.mediaPath)) {
            if (File(clip.mediaPath!).existsSync()) {
              _existenceCache.add(clip.mediaPath!);
            } else {
              _missingCache.add(clip.mediaPath!);
              continue;
            }
          }
          activeAudioClips.add(clip);
        }
      }
    }

    final activeClipIds = activeAudioClips.map((c) => c.id).toSet();

    // Dispose players for removed clips
    final removedIds = _audioPlayers.keys.where((id) => !activeClipIds.contains(id)).toList();
    for (final id in removedIds) {
      debugPrint('=> [Live Audio Sync] Disposing AudioPlayer for deleted clip $id');
      await _audioPlayers[id]?.pause();
      await _audioPlayers[id]?.dispose();
      _audioPlayers.remove(id);
      _loadedPaths.remove(id);
      _lastKnownVolume.remove(id);
    }

    for (final clip in activeAudioClips) {
      VideoPlayerController? player = _audioPlayers[clip.id];

      // Initialize player only if file path changed or not yet created
      if (player == null || _loadedPaths[clip.id] != clip.mediaPath) {
        if (player != null) {
          await player.pause();
          await player.dispose();
        }
        try {
          debugPrint('=> [Live Audio Init] Initializing ExoPlayer for: ${clip.mediaPath}');
          player = VideoPlayerController.file(File(clip.mediaPath!));
          await player.initialize();
          _audioPlayers[clip.id] = player;
          _loadedPaths[clip.id] = clip.mediaPath!;
          _lastKnownVolume[clip.id] = -1; // Force volume set on first init
        } catch (e) {
          debugPrint('=> [Live Audio Init Error] Failed to initialize: $e');
          continue;
        }
      }

      if (!player.value.isInitialized) continue;

      // FIX #3: Only call setVolume() when volume actually changes — not on every tick
      final targetVolume = clip.volume.clamp(0.0, 2.0);
      if ((_lastKnownVolume[clip.id] ?? -1) != targetVolume) {
        await player.setVolume(targetVolume);
        _lastKnownVolume[clip.id] = targetVolume;
      }

      final isInBounds = currentMs >= clip.startMs && currentMs <= clip.endMs;
      final relativeAudioMs = (currentMs - clip.startMs + clip.trimStartMs)
          .clamp(clip.trimStartMs, clip.trimEndMs);

      if (isInBounds && isPlaying && !isDragging) {
        if (!player.value.isPlaying) {
          // Transitioning to PLAYING — seek to correct position then play
          debugPrint('=> [Live Audio Action] STARTING clip=${clip.title} at relative ${relativeAudioMs.toStringAsFixed(0)}ms');
          await player.seekTo(Duration(milliseconds: relativeAudioMs.toInt()));
          await player.play();
        } else if (isForcedSync) {
          // FIX #4: Drift correction ONLY runs during forced syncs (play start / drag end),
          // NOT on the 8Hz polling timer during normal uninterrupted playback.
          final playerPosMs = player.value.position.inMilliseconds.toDouble();
          final drift = (playerPosMs - relativeAudioMs).abs();
          if (drift > 200) {
            debugPrint('=> [Live Audio Drift Fix] Correcting ${drift.toStringAsFixed(0)}ms drift for clip ${clip.title}');
            await player.seekTo(Duration(milliseconds: relativeAudioMs.toInt()));
          }
        }
        // else: player is playing normally — DO NOTHING. Zero MethodChannel traffic.
      } else {
        if (player.value.isPlaying) {
          debugPrint('=> [Live Audio Action] PAUSING clip=${clip.title} (inBounds=$isInBounds playing=$isPlaying dragging=$isDragging)');
          await player.pause();
        }
      }
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (_controllerListener != null) {
      controller.removeListener(_controllerListener!);
    }
    // BUG-12 FIX: Clear the callback so the controller no longer holds
    // a reference to this (potentially already disposed) manager.
    controller.clipDeletedCallback = null;
    for (final player in _audioPlayers.values) {
      // BUG-07 FIX: pause() is intentionally fire-and-forget here.
      // VideoPlayerController.dispose() tears down the ExoPlayer instance and
      // all pending operations atomically — the pause command is not needed
      // for correctness, only to silence logcat warnings on some OEM ROMs.
      unawaited(player.pause());
      unawaited(player.dispose());
    }
    _audioPlayers.clear();
    _loadedPaths.clear();
    _lastKnownVolume.clear();
    _existenceCache.clear();
    _missingCache.clear();
    debugPrint('=> [LiveAudioSyncManager] Disposed all audio players.');
  }
}
