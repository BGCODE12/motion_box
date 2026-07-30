import 'dart:io';
import 'package:flutter/material.dart';

import '../models/timeline_models.dart';
import '../controllers/timeline_controller.dart';
import '../services/thumbnail_manager.dart';
import 'text_editor_modal.dart';

/// Individual clip block widget on a timeline track lane.
///
/// DRAG-AND-DROP ARCHITECTURE:
/// ─────────────────────────────────────────────────────────────────────────
/// We use a LOCAL `ValueNotifier<double> _dragOffsetPx` to translate the clip
/// visually at 60fps WITHOUT calling `notifyListeners()` on the controller.
///
/// The controller is ONLY called ONCE — on `onHorizontalDragEnd` — via
/// `controller.updateClipStartTime(finalMs)`. This single commit records the
/// action to the undo/redo stack and triggers one layout rebuild.
///
/// Drag Guards:
/// - Main video track clips (TrackType.video with index 0) are NOT draggable
///   (they are anchor clips). Text and Audio clips are freely draggable.
/// - `newStartMs` is clamped to ≥ 0 (can't drag before timeline start).
/// - During drag we call `controller.setDragging(true)` to pause playback
///   and suppress the timeline scroll listener — same flag used by seek scrub.
///
/// Visual Feedback:
/// - Opacity drops to 0.7 during drag.
/// - A white 1.5px border highlights the clip body.
/// - The clip translates smoothly with a `Transform.translate`.
class ClipWidget extends StatefulWidget {
  final TimelineClip clip;
  final TimelineController controller;
  final bool isSelected;

  /// Whether this clip is draggable (non-anchor clips only).
  final bool isDraggable;

  const ClipWidget({
    super.key,
    required this.clip,
    required this.controller,
    this.isSelected = false,
    this.isDraggable = true,
  });

  @override
  State<ClipWidget> createState() => _ClipWidgetState();
}

class _ClipWidgetState extends State<ClipWidget> {
  TimelineClip get clip => widget.clip;
  TimelineController get controller => widget.controller;
  bool get isSelected => widget.isSelected;

  // ─── Drag State ─────────────────────────────────────────────────────────
  /// Live pixel offset accumulated during a drag gesture.
  /// Drives Transform.translate — does NOT call notifyListeners().
  final ValueNotifier<double> _dragOffsetPx = ValueNotifier(0.0);

  /// Whether we are currently in an active drag.
  bool _isDragging = false;

  /// The clip's startMs captured at the moment the drag begins.
  double _dragStartMs = 0.0;

  // ─── Colors ─────────────────────────────────────────────────────────────
  static const Color colorVideoBody = Color(0xFF4A607A);
  static const Color colorVideoBodySelected = Color(0xFF3B5067);
  static const Color colorRedAccent = Color(0xFFE55353);
  static const Color colorTextClip = Color(0xFFE55353);
  static const Color colorAudioClip = Color(0xFF7F848E);

  Color get _clipBackgroundColor {
    switch (clip.type) {
      case TrackType.video:
        return isSelected ? colorVideoBodySelected : colorVideoBody;
      case TrackType.text:
        return colorTextClip;
      case TrackType.audio:
        return colorAudioClip;
      case TrackType.overlay:
        return clip.color;
    }
  }

  @override
  void dispose() {
    _dragOffsetPx.dispose();
    super.dispose();
  }

  // ─── Drag Handlers ───────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragStartMs = clip.startMs;
    _dragOffsetPx.value = 0.0;
    // Pause playback & suppress timeline scroll listener during clip drag
    controller.setDragging(true);
    debugPrint('=> [ClipDrag] START clip=${clip.id.substring(0, 8)} startMs=${_dragStartMs.toStringAsFixed(0)}');
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    // Accumulate pixel delta into the local notifier — ZERO controller calls.
    _dragOffsetPx.value += details.delta.dx;

    // Compute the provisional new startMs so we can enforce the left boundary.
    final deltaMs = _dragOffsetPx.value / controller.zoomScale;
    final provisionalMs = (_dragStartMs + deltaMs).clamp(0.0, double.infinity);

    // If clamped against left wall, also clamp the visual offset so the clip
    // doesn't slide off the start of the timeline.
    final clampedOffsetPx = (provisionalMs - _dragStartMs) * controller.zoomScale;
    if (_dragOffsetPx.value != clampedOffsetPx) {
      _dragOffsetPx.value = clampedOffsetPx;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;

    final deltaMs = _dragOffsetPx.value / controller.zoomScale;
    final finalStartMs = (_dragStartMs + deltaMs).clamp(0.0, double.infinity);

    debugPrint(
      '=> [ClipDrag] END clip=${clip.id.substring(0, 8)} '
      'delta=${_dragOffsetPx.value.toStringAsFixed(1)}px  '
      'finalStart=${finalStartMs.toStringAsFixed(0)}ms',
    );

    // Reset visual offset BEFORE the controller call so the clip snaps cleanly.
    _dragOffsetPx.value = 0.0;

    // Single commit: updates state + pushes to undo stack + notifyListeners().
    controller.updateClipStartTime(clip.id, finalStartMs);
    controller.setDragging(false);
  }

  void _onDragCancel() {
    if (!_isDragging) return;
    _isDragging = false;
    // Snap back to original position — no controller call needed.
    _dragOffsetPx.value = 0.0;
    controller.setDragging(false);
    debugPrint('=> [ClipDrag] CANCELLED clip=${clip.id.substring(0, 8)}');
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final clipWidth =
        (clip.effectiveDurationMs * controller.zoomScale).clamp(24.0, double.infinity);

    // ValueListenableBuilder wraps only the translating shell — the expensive
    // clip internals (filmstrip, handles) are in the child and don't rebuild
    // on every drag pixel.
    return ValueListenableBuilder<double>(
      valueListenable: _dragOffsetPx,
      builder: (context, offsetPx, child) {
        final isDraggingNow = offsetPx != 0.0 || _isDragging;

        return Transform.translate(
          offset: Offset(offsetPx, 0),
          child: Opacity(
            opacity: isDraggingNow ? 0.72 : 1.0,
            child: child,
          ),
        );
      },
      // child is built once and reused — not rebuilt on every drag frame.
      child: _buildClipBody(clipWidth),
    );
  }

  Widget _buildClipBody(double clipWidth) {
    return GestureDetector(
      // ── Clip selection / text editor tap ──────────────────────────────
      onTap: () {
        controller.selectClip(clip.id);
        if (clip.type == TrackType.text) {
          TextEditorModal.show(context, controller, clip);
        }
      },
      onDoubleTap: () {
        if (clip.type == TrackType.text) {
          TextEditorModal.show(context, controller, clip);
        }
      },

      // ── Clip-move horizontal drag (Text, Audio, non-anchor Video) ─────
      onHorizontalDragStart: widget.isDraggable ? _onDragStart : null,
      onHorizontalDragUpdate: widget.isDraggable ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.isDraggable ? _onDragEnd : null,
      onHorizontalDragCancel: widget.isDraggable ? _onDragCancel : null,

      child: ValueListenableBuilder<double>(
        valueListenable: _dragOffsetPx,
        builder: (context, offsetPx, child) {
          final isDraggingNow = offsetPx != 0.0 || _isDragging;
          return Container(
            width: clipWidth,
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: clip.type == TrackType.video && isSelected
                  ? colorRedAccent
                  : _clipBackgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: isDraggingNow
                  // White highlight border during active drag
                  ? Border.all(color: Colors.white, width: 1.5)
                  : clip.type == TrackType.video && isSelected
                      ? Border.all(color: colorRedAccent, width: 2)
                      : null,
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              // 1. Video Body Container inside Red Frame (selected Video Clips)
              if (clip.type == TrackType.video)
                Positioned.fill(
                  left: isSelected ? 10 : 0,
                  right: isSelected ? 10 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _clipBackgroundColor,
                      borderRadius: BorderRadius.circular(isSelected ? 3 : 4),
                    ),
                    child: Stack(
                      children: [
                        if (clip.mediaPath != null)
                          Positioned.fill(
                            child: _buildFilmstripThumbnails(
                                clipWidth - (isSelected ? 20 : 0)),
                          ),
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 2. Clip title label
              Positioned.fill(
                left: clip.type == TrackType.video && isSelected ? 12 : 6,
                right: clip.type == TrackType.video && isSelected
                    ? 12
                    : (clip.type == TrackType.video ? 24 : 6),
                child: Row(
                  children: [
                    if (clip.type != TrackType.video)
                      Icon(clip.type.icon, size: 12, color: Colors.white70),
                    if (clip.type != TrackType.video) const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        clip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Unselected Video delete 'X' button
              if (clip.type == TrackType.video && !isSelected)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => controller.deleteClip(clip.id),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 11, color: Colors.black87),
                      ),
                    ),
                  ),
                ),

              // 4. Left Trim Handle (In-point) — only when selected
              if (isSelected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: GestureDetector(
                    // Trim handles use their own drag and MUST NOT trigger
                    // the clip-move drag above. They call setDragging separately.
                    onHorizontalDragStart: (_) => controller.setDragging(true),
                    onHorizontalDragUpdate: (details) {
                      final deltaMs = details.delta.dx / controller.zoomScale;
                      controller.trimClipStart(clip.id, deltaMs);
                    },
                    onHorizontalDragEnd: (_) => controller.setDragging(false),
                    child: _buildHandle(isLeft: true),
                  ),
                ),

              // 5. Right Trim Handle (Out-point) — only when selected
              if (isSelected)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) => controller.setDragging(true),
                    onHorizontalDragUpdate: (details) {
                      final deltaMs = details.delta.dx / controller.zoomScale;
                      controller.trimClipEnd(clip.id, deltaMs);
                    },
                    onHorizontalDragEnd: (_) => controller.setDragging(false),
                    child: _buildHandle(isLeft: false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle({required bool isLeft}) {
    final isVideo = clip.type == TrackType.video;
    return Container(
      decoration: BoxDecoration(
        color: isVideo ? colorRedAccent : Colors.white70,
        borderRadius: isLeft
            ? const BorderRadius.horizontal(left: Radius.circular(4))
            : const BorderRadius.horizontal(right: Radius.circular(4)),
      ),
      child: Center(
        child: Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildFilmstripThumbnails(double clipWidthPx) {
    final thumbManager = ThumbnailManager();

    return ListenableBuilder(
      listenable: thumbManager,
      builder: (context, _) {
        final tiles = thumbManager.getThumbnailsForClip(
          videoPath: clip.mediaPath!,
          trimStartMs: clip.trimStartMs,
          trimEndMs: clip.trimEndMs,
          clipWidthPx: clipWidthPx,
          tileWidthPx: 40.0,
        );

        if (tiles.isEmpty) {
          return Container(color: colorVideoBody);
        }

        return Row(
          children: tiles.map((path) {
            return Container(
              width: 40.0,
              height: 40,
              decoration: const BoxDecoration(
                border: Border(
                    right: BorderSide(color: Colors.black12, width: 0.5)),
              ),
              child: path != null && File(path).existsSync()
                  ? Image.file(File(path),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      cacheHeight: 120) // ⚡ Bolt: limits memory footprint
                  : Container(color: colorVideoBody.withValues(alpha: 0.5)),
            );
          }).toList(),
        );
      },
    );
  }
}
