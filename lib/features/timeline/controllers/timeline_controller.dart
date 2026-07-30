import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/timeline_models.dart';
import '../models/undo_operation.dart';

/// High-performance TimelineController managing timeline state, tracks,
/// zoom scale, 15Hz throttled seek scrubbing, and non-blocking 60FPS video playback.
class TimelineController extends ChangeNotifier {
  /// Fast ValueNotifier for playhead position in milliseconds.
  /// Subscribed by playhead line & timestamp display via ValueListenableBuilder.
  final ValueNotifier<double> currentPositionMs = ValueNotifier<double>(0.0);

  /// Total duration of the timeline project in milliseconds.
  double _totalDurationMs = 15000.0; // Default 15 seconds
  double get totalDurationMs => _totalDurationMs;

  /// Zoom scale factor: Pixels per millisecond.
  /// 0.05 px/ms = 50 pixels per second. Range: 0.01 to 0.5 px/ms.
  double _zoomScale = 0.05;
  double get zoomScale => _zoomScale;

  /// Active track lanes.
  final List<TimelineTrack> _tracks = [];
  List<TimelineTrack> get tracks => List.unmodifiable(_tracks);

  /// Selected clip ID for highlighting and context operations.
  String? _selectedClipId;
  String? get selectedClipId => _selectedClipId;

  /// Playback state.
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// STRICT DRAGGING FLAG: True ONLY when user is actively dragging/touching the timeline.
  bool _isUserDraggingTimeline = false;
  bool get isUserDraggingTimeline => _isUserDraggingTimeline;

  DateTime? _lastSeekTime;
  Timer? _pendingSeekTimer;

  // BUG-09 FIX: Debounce timestamp for splitClipAtPlayhead.
  // Rapid taps mutate track.clips while a ListenableBuilder frame is still
  // iterating the list — a 300ms gate prevents same-frame double-splits.
  DateTime? _lastSplitTime;

  /// Associated Flutter VideoPlayerController for preview sync.
  VideoPlayerController? _videoPlayerController;
  VideoPlayerController? get videoPlayerController => _videoPlayerController;

  /// Main video track audio mute flag.
  bool _isMainVideoMuted = false;
  bool get isMainVideoMuted => _isMainVideoMuted;

  // ─── Undo / Redo Stack ────────────────────────────────────────────────────
  // Stores sealed UndoOperation subclasses covering every mutating operation.
  // The stacks hold the full before/after snapshot so undo/redo never
  // recomputes — it just restores the captured field values.
  final List<UndoOperation> _undoStack = [];
  final List<UndoOperation> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // ─── BUG-12 Fix: Immediate audio teardown on clip delete ─────────────────
  // LiveAudioSyncManager registers its forceSync() into this slot during init.
  // deleteClip() calls it immediately so orphaned audio players are disposed
  // in the same event-loop turn — not up to 125ms later on the next timer tick.
  VoidCallback? _onClipDeleted;

  /// Register a callback that is fired synchronously inside deleteClip().
  /// Used by LiveAudioSyncManager to force an immediate audio player teardown.
  set clipDeletedCallback(VoidCallback? callback) => _onClipDeleted = callback;

  Timer? _playbackTicker;

  TimelineController() {
    _initializeDefaultTracks();
  }

  // ─── Undo / Redo helpers ──────────────────────────────────────────────────

  /// Push [op] onto the undo stack and clear the redo stack.
  /// Every mutating method calls this AFTER applying its change.
  void _pushUndo(UndoOperation op) {
    _undoStack.add(op);
    _redoStack.clear();
    debugPrint('=> [Undo] pushed ${op.runtimeType} | stack depth: ${_undoStack.length}');
  }

  /// Apply the INVERSE of [op] (used by undo()).
  void _applyUndo(UndoOperation op) {
    switch (op) {
      case MoveOp():
        final clip = findClipById(op.clipId);
        if (clip != null) clip.startMs = op.oldStartMs;

      case TrimOp():
        final clip = findClipById(op.clipId);
        if (clip != null) {
          clip.trimStartMs    = op.oldTrimStartMs;
          clip.trimEndMs      = op.oldTrimEndMs;
          clip.startMs        = op.oldStartMs;
          clip.mediaDurationMs = op.oldMediaDurationMs;
        }

      case DeleteOp():
        // Re-insert the deleted clip at its original track position.
        final track = _tracks.firstWhere(
          (t) => t.id == op.trackId,
          orElse: () => _tracks.first,
        );
        final idx = op.clipIndex.clamp(0, track.clips.length);
        track.clips.insert(idx, op.clip);

      case AddOp():
        // Remove the added clip by ID.
        for (final track in _tracks) {
          track.clips.removeWhere((c) => c.id == op.clip.id);
        }

      case SplitOp():
        // Remove both halves and restore the original clip.
        final track = _tracks.firstWhere(
          (t) => t.id == op.trackId,
          orElse: () => _tracks.first,
        );
        track.clips.removeWhere(
          (c) => c.id == op.firstHalf.id || c.id == op.secondHalf.id,
        );
        final idx = op.originalIndex.clamp(0, track.clips.length);
        track.clips.insert(idx, op.originalClip);
        _selectedClipId = op.originalClip.id;
    }
    _recalculateTotalDuration();
    notifyListeners();
  }

  /// Re-apply the FORWARD state of [op] (used by redo()).
  void _applyRedo(UndoOperation op) {
    switch (op) {
      case MoveOp():
        final clip = findClipById(op.clipId);
        if (clip != null) clip.startMs = op.newStartMs;

      case TrimOp():
        final clip = findClipById(op.clipId);
        if (clip != null) {
          clip.trimStartMs    = op.newTrimStartMs;
          clip.trimEndMs      = op.newTrimEndMs;
          clip.startMs        = op.newStartMs;
          clip.mediaDurationMs = op.newMediaDurationMs;
        }

      case DeleteOp():
        // Re-delete the clip.
        for (final track in _tracks) {
          track.clips.removeWhere((c) => c.id == op.clip.id);
        }
        if (_selectedClipId == op.clip.id) _selectedClipId = null;
        // Notify audio manager immediately (BUG-12 guard).
        _onClipDeleted?.call();

      case AddOp():
        // Re-add the clip to its original track.
        final track = _tracks.firstWhere(
          (t) => t.id == op.trackId,
          orElse: () => _tracks.first,
        );
        track.clips.add(op.clip);
        _selectedClipId = op.clip.id;

      case SplitOp():
        // Re-perform the split: remove original, insert both halves.
        final track = _tracks.firstWhere(
          (t) => t.id == op.trackId,
          orElse: () => _tracks.first,
        );
        final idx = track.clips.indexWhere((c) => c.id == op.originalClip.id);
        if (idx != -1) {
          track.clips[idx] = op.firstHalf;
          track.clips.insert(idx + 1, op.secondHalf);
          _selectedClipId = op.secondHalf.id;
        }
    }
    _recalculateTotalDuration();
    notifyListeners();
  }


  void _initializeDefaultTracks() {
    _tracks.clear();

    // Track 1: Main Video Track
    final videoTrack = TimelineTrack(
      id: 'track_video_main',
      name: 'Main Video',
      type: TrackType.video,
      clips: [
        TimelineClip(
          id: 'clip_video_1',
          title: 'Sample Video 01',
          type: TrackType.video,
          startMs: 0.0,
          mediaDurationMs: 8000.0,
        ),
        TimelineClip(
          id: 'clip_video_2',
          title: 'Sample Video 02',
          type: TrackType.video,
          startMs: 8000.0,
          mediaDurationMs: 7000.0,
        ),
      ],
    );

    // Track 2: Text / Overlay Track
    final textTrack = TimelineTrack(
      id: 'track_text',
      name: 'Text Overlay',
      type: TrackType.text,
      clips: [
        TimelineClip(
          id: 'clip_text_1',
          title: 'Title Overlay',
          type: TrackType.text,
          startMs: 2000.0,
          mediaDurationMs: 5000.0,
        ),
      ],
    );

    // Track 3: Audio Track
    final audioTrack = TimelineTrack(
      id: 'track_audio',
      name: 'Audio Track',
      type: TrackType.audio,
      clips: [
        TimelineClip(
          id: 'clip_audio_1',
          title: 'Background Beat.mp3',
          type: TrackType.audio,
          startMs: 0.0,
          mediaDurationMs: 15000.0,
        ),
      ],
    );

    _tracks.addAll([videoTrack, textTrack, audioTrack]);
    _recalculateTotalDuration();
  }

  /// Attach a VideoPlayerController for 1:1 preview scrubbing and playback sync.
  void attachVideoPlayer(VideoPlayerController player) {
    _videoPlayerController = player;
    _videoPlayerController!.addListener(_onVideoPlayerTick);
    notifyListeners();
  }

  void detachVideoPlayer() {
    _videoPlayerController?.removeListener(_onVideoPlayerTick);
    _videoPlayerController = null;
  }

  void _onVideoPlayerTick() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      final vpPlaying = _videoPlayerController!.value.isPlaying;
      if (_isPlaying) {
        final position = _videoPlayerController!.value.position.inMilliseconds.toDouble();
        if ((position - currentPositionMs.value).abs() > 15) {
          // SAFE: only updates the ValueNotifier — does NOT call seekTo() or notifyListeners()
          currentPositionMs.value = position.clamp(0.0, _totalDurationMs);
        }
      }
      // Only propagate isPlaying change when VIDEO STOPS (e.g. reaches end).
      // play() already calls notifyListeners() when starting, so we skip that direction.
      if (_isPlaying && !vpPlaying) {
        debugPrint('=> [VideoPlayer Listener] video stopped externally — syncing isPlaying → false');
        _isPlaying = false;
        _playbackTicker?.cancel();
        _playbackTicker = null;
        notifyListeners();
      }
    }
  }


  /// Sets dragging state. Pauses playback when user touches/drags timeline.
  void setDragging(bool dragging) {
    if (_isUserDraggingTimeline == dragging) return;
    debugPrint('=> [TimelineController] setDragging($dragging) — was $_isUserDraggingTimeline');
    _isUserDraggingTimeline = dragging;

    if (dragging) {
      if (_isPlaying) {
        pause();
      }
    } else {
      _pendingSeekTimer?.cancel();
      _pendingSeekTimer = null;
      // Final alignment seek after drag ends (video is paused at this point)
      if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized && !_isPlaying) {
        debugPrint('=> [TimelineController] setDragging(false): final alignmentseekTo(${currentPositionMs.value.toInt()} ms)');
        _videoPlayerController!.seekTo(Duration(milliseconds: currentPositionMs.value.toInt()));
      }
    }
  }

  /// Seek playhead to a specific position in milliseconds.
  ///
  /// GOLDEN RULE: seekTo() ONLY calls videoPlayerController.seekTo() if:
  ///   1. [_isUserDraggingTimeline] is true (user gesture), AND
  ///   2. [_isPlaying] is false (video is paused)
  ///
  /// This is the single gate that prevents the infinite seek loop.
  void seekTo(double positionMs) {
    final clamped = positionMs.clamp(0.0, _totalDurationMs);
    currentPositionMs.value = clamped;

    if (!_isUserDraggingTimeline) {
      debugPrint('=> [TimelineController] seekTo(${clamped.toInt()}) BLOCKED — not user dragging');
      return;
    }
    if (_isPlaying) {
      debugPrint('=> [TimelineController] seekTo(${clamped.toInt()}) BLOCKED — video is playing');
      return;
    }
    if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) {
      return;
    }

    // 15Hz Throttled seek during active user drag
    final now = DateTime.now();
    if (_lastSeekTime == null || now.difference(_lastSeekTime!) >= const Duration(milliseconds: 66)) {
      _lastSeekTime = now;
      debugPrint('=> [TimelineController] seekTo ALLOWED — calling videoPlayer.seekTo(${clamped.toInt()} ms)');
      _videoPlayerController!.seekTo(Duration(milliseconds: clamped.toInt()));
    } else {
      _pendingSeekTimer?.cancel();
      _pendingSeekTimer = Timer(const Duration(milliseconds: 66), () {
        if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized && !_isPlaying && _isUserDraggingTimeline) {
          debugPrint('=> [TimelineController] throttled seekTo ALLOWED — calling videoPlayer.seekTo(${currentPositionMs.value.toInt()} ms)');
          _videoPlayerController!.seekTo(Duration(milliseconds: currentPositionMs.value.toInt()));
        }
      });
    }
  }

  /// Explicit seek triggered by user tapping timeline ruler or playhead jump.
  void seekToExplicit(double positionMs) {
    final clamped = positionMs.clamp(0.0, _totalDurationMs);
    currentPositionMs.value = clamped;

    if (_isPlaying) {
      pause();
    }
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      _videoPlayerController!.seekTo(Duration(milliseconds: clamped.toInt()));
    }
  }

  /// Toggle play / pause playback.
  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    _isUserDraggingTimeline = false; // Force drag flag false on play
    notifyListeners();

    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      _videoPlayerController!.play();
    } else {
      _playbackTicker?.cancel();
      _playbackTicker = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!_isPlaying) {
          timer.cancel();
          return;
        }
        final nextPos = currentPositionMs.value + 16.0;
        if (nextPos >= _totalDurationMs) {
          pause();
          seekToExplicit(0.0);
        } else {
          currentPositionMs.value = nextPos;
        }
      });
    }
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _playbackTicker?.cancel();
    _playbackTicker = null;
    notifyListeners();

    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      _videoPlayerController!.pause();
    }
  }

  /// Update zoom scale (pixels per millisecond).
  /// Min: 0.02 px/ms (20px/sec) — below this clips become sub-pixel wide
  /// and trim-handle drag delta amplification exceeds 50ms/px (unusable).
  void setZoomScale(double newScale) {
    final clampedScale = newScale.clamp(0.02, 0.3);
    if ((_zoomScale - clampedScale).abs() > 0.0001) {
      _zoomScale = clampedScale;
      notifyListeners();
    }
  }

  /// Select a timeline clip by ID.
  void selectClip(String? clipId) {
    if (_selectedClipId != clipId) {
      _selectedClipId = clipId;
      notifyListeners();
    }
  }

  /// Find clip by ID across all tracks.
  TimelineClip? findClipById(String clipId) {
    for (final track in _tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  /// Add a Text Overlay clip to the text track at current playhead position.
  void addTextClip({
    required String text,
    double durationMs = 4000.0,
    String textColorHex = '#FFFFFF',
    String fontName = 'Roboto',
    double fontSize = 36.0,
  }) {
    final textTrack = _tracks.firstWhere(
      (t) => t.type == TrackType.text,
      orElse: () {
        final newTrack = TimelineTrack(
          id: 'track_text_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Text Overlay',
          type: TrackType.text,
        );
        _tracks.add(newTrack);
        return newTrack;
      },
    );

    final startMs = currentPositionMs.value;
    final clip = TimelineClip(
      id: 'clip_text_${DateTime.now().millisecondsSinceEpoch}',
      title: text,
      type: TrackType.text,
      startMs: startMs,
      mediaDurationMs: durationMs,
      textColorHex: textColorHex,
      fontName: fontName,
      fontSize: fontSize,
    );

    textTrack.clips.add(clip);
    _selectedClipId = clip.id;
    _recalculateTotalDuration();
    // AddOp: undo removes the clip; redo re-adds it.
    _pushUndo(AddOp(trackId: textTrack.id, clip: clip.copyWith()));
    notifyListeners();
  }

  /// Toggle mute state for the main video track.
  void toggleMainVideoMute() {
    _isMainVideoMuted = !_isMainVideoMuted;
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      _videoPlayerController!.setVolume(_isMainVideoMuted ? 0.0 : 1.0);
    }
    debugPrint('=> [TimelineController] toggleMainVideoMute: isMainVideoMuted=$_isMainVideoMuted');
    notifyListeners();
  }

  /// Add an Audio clip to the audio track.
  void addAudioClip({
    required String title,
    required String audioPath,
    required double durationMs,
    double volume = 1.0,
  }) {
    final audioTrack = _tracks.firstWhere(
      (t) => t.type == TrackType.audio,
      orElse: () {
        final newTrack = TimelineTrack(
          id: 'track_audio_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Audio Track',
          type: TrackType.audio,
        );
        _tracks.add(newTrack);
        return newTrack;
      },
    );

    final startMs = currentPositionMs.value;
    final clip = TimelineClip(
      id: 'clip_audio_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      mediaPath: audioPath,
      type: TrackType.audio,
      startMs: startMs,
      mediaDurationMs: durationMs,
      volume: volume,
    );

    audioTrack.clips.add(clip);
    _selectedClipId = clip.id;
    _recalculateTotalDuration();
    debugPrint('=> [TimelineController] addAudioClip: $title (startMs=$startMs, durationMs=$durationMs)');
    // AddOp: undo removes the clip; redo re-adds it.
    _pushUndo(AddOp(trackId: audioTrack.id, clip: clip.copyWith()));
    notifyListeners();
  }

  /// Update clip volume (0.0 to 2.0).
  void updateClipVolume(String clipId, double newVolume) {
    final clip = findClipById(clipId);
    if (clip == null) return;
    clip.volume = newVolume.clamp(0.0, 2.0);
    debugPrint('=> [TimelineController] updateClipVolume: clipId=${clip.id} newVolume=${clip.volume}');
    notifyListeners();
  }


  /// Update text overlay properties of a clip.
  void updateTextClip(
    String clipId, {
    String? newText,
    String? newColorHex,
    String? newFontName,
    double? newFontSize,
  }) {
    final clip = findClipById(clipId);
    if (clip == null) return;

    if (newText != null && newText.isNotEmpty) {
      clip.title = newText;
    }
    if (newColorHex != null) {
      clip.textColorHex = newColorHex;
    }
    if (newFontName != null) {
      clip.fontName = newFontName;
    }
    if (newFontSize != null) {
      clip.fontSize = newFontSize;
    }

    notifyListeners();
  }

  /// Update the canvas position of a text/overlay clip.
  /// [dx] and [dy] are fractional deltas (fraction of canvas width/height).
  /// The position is clamped so the clip's anchor stays within the canvas bounds.
  void updateTextClipPosition(String clipId, {required double dx, required double dy}) {
    final clip = findClipById(clipId);
    if (clip == null) return;

    clip.overlayX = (clip.overlayX + dx).clamp(0.05, 0.95);
    clip.overlayY = (clip.overlayY + dy).clamp(0.05, 0.95);

    debugPrint(
      '=> [updateTextClipPosition] id=${clipId.substring(0, 8)} '
      'overlayX=${clip.overlayX.toStringAsFixed(3)} '
      'overlayY=${clip.overlayY.toStringAsFixed(3)}',
    );

    notifyListeners();
  }


  /// Adjust clip start trim handle (In-point).
  /// Moving LEFT (negative dx → negative deltaMs) trims from the start, shrinking the clip from the left.
  /// Moving RIGHT (positive dx → positive deltaMs) extends back in, growing the clip from the left.
  void trimClipStart(String clipId, double deltaMs) {
    final clip = findClipById(clipId);
    if (clip == null) return;

    // Snapshot BEFORE state for TrimOp
    final oldTrimStartMs    = clip.trimStartMs;
    final oldTrimEndMs      = clip.trimEndMs;
    final oldStartMs        = clip.startMs;
    final oldMediaDuration  = clip.mediaDurationMs;

    // Lower bound: 0 (can't trim before media start)
    // Upper bound: trimEndMs - 200 (must leave at least 200ms of clip)
    final newTrimStart = (clip.trimStartMs + deltaMs).clamp(0.0, clip.trimEndMs - 200.0);
    final actualDelta = newTrimStart - clip.trimStartMs;

    clip.trimStartMs = newTrimStart;
    // BUG-01 FIX: Clamp to >= 0 so the clip can never be pushed before the origin.
    clip.startMs = (clip.startMs + actualDelta / clip.speed).clamp(0.0, double.infinity);

    debugPrint(
      '=> [trimClipStart] id=${clipId.substring(0, 8)} '
      'delta=${deltaMs.toStringAsFixed(1)}ms '
      'trimStart: ${oldTrimStartMs.toStringAsFixed(0)} → ${clip.trimStartMs.toStringAsFixed(0)}ms '
      'startMs=${clip.startMs.toStringAsFixed(0)}ms '
      'effectiveDuration=${clip.effectiveDurationMs.toStringAsFixed(0)}ms',
    );

    _pushUndo(TrimOp(
      clipId: clipId,
      oldTrimStartMs:    oldTrimStartMs,
      oldTrimEndMs:      oldTrimEndMs,
      oldStartMs:        oldStartMs,
      oldMediaDurationMs: oldMediaDuration,
      newTrimStartMs:    clip.trimStartMs,
      newTrimEndMs:      clip.trimEndMs,
      newStartMs:        clip.startMs,
      newMediaDurationMs: clip.mediaDurationMs,
    ));
    _recalculateTotalDuration();
    notifyListeners();
  }

  /// Adjust clip end trim handle (Out-point).
  /// Moving RIGHT (positive dx → positive deltaMs) expands the clip's duration.
  /// Moving LEFT  (negative dx → negative deltaMs) shrinks the clip's duration.
  ///
  /// FIX: For Text/Overlay clips (no fixed media file), we grow [mediaDurationMs] along
  /// with [trimEndMs] so the upper-bound clamp never blocks expansion.
  /// For Video/Audio clips, [mediaDurationMs] is the hard ceiling (can't show
  /// frames that don't exist in the file).
  void trimClipEnd(String clipId, double deltaMs) {
    final clip = findClipById(clipId);
    if (clip == null) return;

    // Snapshot BEFORE state for TrimOp
    final oldTrimStartMs   = clip.trimStartMs;
    final oldTrimEndMs     = clip.trimEndMs;
    final oldStartMs       = clip.startMs;
    final oldMediaDuration = clip.mediaDurationMs;

    // For clips without real media (Text, Overlay), grow mediaDurationMs freely.
    // For Video/Audio, respect the hard file duration ceiling.
    final bool hasFixedMedia = clip.type == TrackType.video || clip.type == TrackType.audio;

    if (hasFixedMedia) {
      // Hard ceiling: cannot exceed actual file duration
      clip.trimEndMs = (clip.trimEndMs + deltaMs).clamp(
        clip.trimStartMs + 200.0,
        clip.mediaDurationMs,
      );
    } else {
      // Soft ceiling: text/overlay clips can grow indefinitely.
      // Grow mediaDurationMs in lockstep so the clamp never blocks expansion.
      final wantedTrimEnd = clip.trimEndMs + deltaMs;
      final minAllowed = clip.trimStartMs + 200.0;
      if (wantedTrimEnd > clip.mediaDurationMs) {
        clip.mediaDurationMs = wantedTrimEnd.clamp(minAllowed, double.infinity);
      }
      clip.trimEndMs = wantedTrimEnd.clamp(minAllowed, clip.mediaDurationMs);
    }

    debugPrint(
      '=> [trimClipEnd] id=${clipId.substring(0, 8)} '
      'delta=${deltaMs.toStringAsFixed(1)}ms '
      'hasFixedMedia=$hasFixedMedia '
      'mediaDuration: ${oldMediaDuration.toStringAsFixed(0)} → ${clip.mediaDurationMs.toStringAsFixed(0)}ms '
      'trimEnd: ${oldTrimEndMs.toStringAsFixed(0)} → ${clip.trimEndMs.toStringAsFixed(0)}ms '
      'effectiveDuration=${clip.effectiveDurationMs.toStringAsFixed(0)}ms',
    );

    _pushUndo(TrimOp(
      clipId: clipId,
      oldTrimStartMs:    oldTrimStartMs,
      oldTrimEndMs:      oldTrimEndMs,
      oldStartMs:        oldStartMs,
      oldMediaDurationMs: oldMediaDuration,
      newTrimStartMs:    clip.trimStartMs,
      newTrimEndMs:      clip.trimEndMs,
      newStartMs:        clip.startMs,
      newMediaDurationMs: clip.mediaDurationMs,
    ));
    _recalculateTotalDuration();
    notifyListeners();
  }

  /// Split selected clip at current playhead position.
  /// BUG-09 FIX: Debounced to 300ms to prevent rapid-tap list corruption.
  void splitClipAtPlayhead() {
    // ── Debounce gate ─────────────────────────────────────────────────────
    final now = DateTime.now();
    if (_lastSplitTime != null &&
        now.difference(_lastSplitTime!) < const Duration(milliseconds: 300)) {
      debugPrint('=> [splitClipAtPlayhead] DEBOUNCED — ignoring tap '
          '(${now.difference(_lastSplitTime!).inMilliseconds}ms since last split)');
      return;
    }
    // ── Normal split logic ─────────────────────────────────────────────────
    if (_selectedClipId == null) return;
    final playhead = currentPositionMs.value;

    for (final track in _tracks) {
      final index = track.clips.indexWhere((c) => c.id == _selectedClipId);
      if (index != -1) {
        final clip = track.clips[index];
        if (playhead > clip.startMs + 100 && playhead < clip.endMs - 100) {
          final splitOffsetMediaMs = (playhead - clip.startMs) * clip.speed + clip.trimStartMs;

          // Snapshot original clip for SplitOp BEFORE mutating the list.
          final originalSnapshot = clip.copyWith();

          final firstHalf = clip.copyWith(
            id: '${clip.id}_part1',
            trimEndMs: splitOffsetMediaMs,
          );

          final secondHalf = clip.copyWith(
            id: '${clip.id}_part2',
            startMs: playhead,
            trimStartMs: splitOffsetMediaMs,
          );

          track.clips[index] = firstHalf;
          track.clips.insert(index + 1, secondHalf);
          _selectedClipId = secondHalf.id;

          _pushUndo(SplitOp(
            trackId: track.id,
            originalIndex: index,
            originalClip: originalSnapshot,
            firstHalf: firstHalf.copyWith(),
            secondHalf: secondHalf.copyWith(),
          ));
          _recalculateTotalDuration();
          notifyListeners();
          _lastSplitTime = now;
          debugPrint('=> [splitClipAtPlayhead] Split "${clip.title}" at ${playhead.toStringAsFixed(0)}ms');
          return;
        }
      }
    }
  }

  /// Delete clip by ID.
  /// BUG-12 FIX: After removing the clip from state, immediately fires
  /// _onClipDeleted so LiveAudioSyncManager tears down the orphaned audio
  /// player in the same event-loop turn (not 125ms later).
  void deleteClip(String clipId) {
    // Find clip + track BEFORE removing — needed for DeleteOp snapshot.
    String? foundTrackId;
    int foundIndex = -1;
    TimelineClip? foundClip;

    for (final track in _tracks) {
      final idx = track.clips.indexWhere((c) => c.id == clipId);
      if (idx != -1) {
        foundTrackId = track.id;
        foundIndex   = idx;
        foundClip    = track.clips[idx].copyWith(); // deep snapshot
        break;
      }
    }

    for (final track in _tracks) {
      track.clips.removeWhere((c) => c.id == clipId);
    }
    if (_selectedClipId == clipId) _selectedClipId = null;

    if (foundClip != null) {
      _pushUndo(DeleteOp(
        trackId:   foundTrackId!,
        clipIndex: foundIndex,
        clip:      foundClip,
      ));
    }

    _recalculateTotalDuration();
    notifyListeners();

    // Immediately notify audio manager — avoids the 125ms timer lag.
    _onClipDeleted?.call();
    debugPrint('=> [TimelineController] deleteClip: $clipId — audio teardown triggered immediately');
  }

  /// Add a clip to a specific track.
  void addClipToTrack(String trackId, TimelineClip clip) {
    final track = _tracks.firstWhere((t) => t.id == trackId, orElse: () => _tracks.first);
    track.clips.add(clip);
    _recalculateTotalDuration();
    notifyListeners();
  }


  /// Commit a clip-move drag to the project state and push to the undo stack.
  /// Called ONCE per drag gesture (onHorizontalDragEnd), NOT on every pixel delta.
  ///
  /// [clipId]      — the clip being moved.
  /// [finalStartMs]— the new timeline start position in milliseconds.
  void updateClipStartTime(String clipId, double finalStartMs) {
    final clip = findClipById(clipId);
    if (clip == null) return;

    final oldStartMs = clip.startMs;
    final clamped = finalStartMs.clamp(0.0, double.infinity);

    if ((oldStartMs - clamped).abs() < 1.0) return; // No meaningful change

    clip.startMs = clamped;
    _pushUndo(MoveOp(clipId: clipId, oldStartMs: oldStartMs, newStartMs: clamped));
    _recalculateTotalDuration();
    debugPrint('=> [TimelineController] updateClipStartTime: $clipId  ${oldStartMs.toStringAsFixed(0)} → ${clamped.toStringAsFixed(0)} ms  (undo depth: ${_undoStack.length})');
    notifyListeners();
  }

  /// Undo the last timeline operation.
  /// Pattern-matches on [UndoOperation] subclasses via [_applyUndo].
  void undo() {
    if (_undoStack.isEmpty) return;
    final op = _undoStack.removeLast();
    debugPrint('=> [TimelineController] undo: $op  (redo depth: ${_redoStack.length + 1})');
    _applyUndo(op);
    _redoStack.add(op);
  }

  /// Redo the last undone timeline operation.
  /// Pattern-matches on [UndoOperation] subclasses via [_applyRedo].
  void redo() {
    if (_redoStack.isEmpty) return;
    final op = _redoStack.removeLast();
    debugPrint('=> [TimelineController] redo: $op  (undo depth: ${_undoStack.length + 1})');
    _applyRedo(op);
    _undoStack.add(op);
  }

  void _recalculateTotalDuration() {

    double maxEndMs = 10000.0;
    for (final track in _tracks) {
      for (final clip in track.clips) {
        if (clip.endMs > maxEndMs) {
          maxEndMs = clip.endMs;
        }
      }
    }
    _totalDurationMs = maxEndMs + 2000.0;
  }

  @override
  void dispose() {
    detachVideoPlayer();
    _playbackTicker?.cancel();
    _pendingSeekTimer?.cancel();
    currentPositionMs.dispose();
    super.dispose();
  }
}
