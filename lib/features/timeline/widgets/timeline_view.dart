import 'package:flutter/material.dart';
import '../controllers/timeline_controller.dart';
import '../models/timeline_models.dart';
import 'clip_widget.dart';
import 'timeline_ruler.dart';

/// CapCut-style Multi-Track Timeline View.
///
/// KEY DESIGN PRINCIPLE (prevents infinite seek loop):
/// - The timeline canvas scrolls in TWO different modes:
///   A) USER DRAG: User physically scrolls → updates playhead → throttled seekTo video
///   B) PLAYBACK SYNC: VideoPlayer updates playhead → programmatic jumpTo canvas
///
/// We use [_isProgrammaticScroll] to mark mode B so the ScrollController
/// listener NEVER interprets playback-driven scroll as user input.
class TimelineView extends StatefulWidget {
  final TimelineController controller;

  const TimelineView({
    super.key,
    required this.controller,
  });

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  late ScrollController _scrollController;

  /// True ONLY when the user is physically touching and scrolling.
  bool _isUserScrolling = false;

  /// True when WE are calling jumpTo() programmatically (playback or explicit seek).
  /// Guards _onScrollChanged from treating our own scroll as user input.
  bool _isProgrammaticScroll = false;

  double _baseScale = 0.05;

  static const Color colorCanvasBg = Color(0xFF161B24);
  static const Color colorBorder = Color(0xFF2A3646);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);
    widget.controller.currentPositionMs.addListener(_onPlayheadChanged);
  }

  /// Called on every scroll frame.
  /// CRITICAL: Only propagates to seekTo if it is a genuine USER scroll,
  /// not a programmatic scroll from playback sync.
  void _onScrollChanged() {
    if (_isProgrammaticScroll) {
      // This scroll was triggered by us (playback). IGNORE entirely.
      debugPrint('=> [TimelineView] _onScrollChanged SKIPPED (programmatic scroll)');
      return;
    }

    if (_isUserScrolling && _scrollController.hasClients && widget.controller.isUserDraggingTimeline) {
      final scrollPx = _scrollController.offset;
      final playheadMs = scrollPx / widget.controller.zoomScale;
      debugPrint('=> [TimelineView] USER DRAG: calling seekTo($playheadMs ms)');
      widget.controller.seekTo(playheadMs);
    }
  }

  /// Called when the VideoPlayer (or explicit seek) updates [currentPositionMs].
  /// Programmatically scrolls the canvas to follow the playhead.
  /// MUST NOT trigger seekTo back to video player.
  void _onPlayheadChanged() {
    if (_isUserScrolling) {
      // User is in control of scroll — don't fight them.
      return;
    }

    if (!_scrollController.hasClients) return;

    final targetScrollPx = widget.controller.currentPositionMs.value * widget.controller.zoomScale;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final clampedTarget = targetScrollPx.clamp(0.0, maxExtent);

    if ((_scrollController.offset - clampedTarget).abs() > 2.0) {
      debugPrint('=> [TimelineView] _onPlayheadChanged: programmatic jumpTo($clampedTarget px)');
      // Raise the programmatic flag BEFORE calling jumpTo so _onScrollChanged ignores it.
      _isProgrammaticScroll = true;
      _scrollController.jumpTo(clampedTarget);
      // Lower it after the frame is done — use addPostFrameCallback for safety.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isProgrammaticScroll = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    widget.controller.currentPositionMs.removeListener(_onPlayheadChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIX BUG #2: Use ListenableBuilder (not AnimatedBuilder on the full controller)
    // so this expensive rebuild only fires when zoom scale or track structure changes.
    // During playback, currentPositionMs fires 60×/sec — that ONLY drives the
    // scroll offset via _onPlayheadChanged() above, NOT a widget rebuild.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final zoomScale = widget.controller.zoomScale;
        final totalDurationMs = widget.controller.totalDurationMs;
        final timelineWidth = totalDurationMs * zoomScale;

        return LayoutBuilder(
          builder: (context, constraints) {
            final centerPadding = constraints.maxWidth / 2;
            final contentTotalWidth = timelineWidth + (centerPadding * 2);

            return Stack(
              children: [
                // Pinch-to-zoom & Scroll Gesture Container
                GestureDetector(
                  onScaleStart: (_) {
                    _baseScale = widget.controller.zoomScale;
                  },
                  onScaleUpdate: (details) {
                    if (details.scale != 1.0) {
                      widget.controller.setZoomScale(_baseScale * details.scale);
                    }
                  },
                  onScaleEnd: (_) {},
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification) {
                        if (_isProgrammaticScroll) return false;
                        _isUserScrolling = true;
                        widget.controller.setDragging(true);
                      } else if (notification is ScrollEndNotification) {
                        if (!_isUserScrolling) return false;
                        _isUserScrolling = false;
                        debugPrint('=> [TimelineView] ScrollEnd → setDragging(false)');
                        widget.controller.setDragging(false);
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Container(
                        width: contentTotalWidth,
                        color: colorCanvasBg,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Time Ruler Header
                            TimelineRuler(
                              totalDurationMs: totalDurationMs,
                              zoomScale: zoomScale,
                              width: contentTotalWidth,
                              paddingLeft: centerPadding,
                            ),
                            const Divider(height: 1, color: colorBorder),

                            // 2. Track Lanes — rebuilt only on structural changes, NOT on position ticks
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: widget.controller.tracks.map((track) {
                                    return _buildTrackLane(track, zoomScale, centerPadding);
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. Fixed White Playhead Line pinned at center — zero rebuild cost
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: centerPadding - 1,
                  child: IgnorePointer(
                    child: Container(
                      width: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTrackLane(TimelineTrack track, double zoomScale, double centerPadding) {
    // Main video track clips are non-draggable anchors.
    // Text, Audio, and Overlay clips are freely draggable.
    final bool trackIsDraggable = track.type != TrackType.video;

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: colorBorder, width: 0.8)),
      ),
      child: Stack(
        children: track.clips.map((clip) {
          final clipX = centerPadding + (clip.startMs * zoomScale);
          final isSelected = clip.id == widget.controller.selectedClipId;

          return Positioned(
            left: clipX,
            top: 2,
            child: ClipWidget(
              clip: clip,
              controller: widget.controller,
              isSelected: isSelected,
              isDraggable: trackIsDraggable,
            ),
          );
        }).toList(),
      ),
    );
  }
}

