import 'package:flutter/material.dart';
import '../controllers/timeline_controller.dart';
import '../models/timeline_models.dart';
import 'text_editor_modal.dart';

/// A draggable, tappable text overlay rendered on top of the video canvas.
///
/// Position is stored as fractional coordinates [overlayX, overlayY] (0.0–1.0)
/// in [TimelineClip], allowing the canvas to be any size and positions to remain
/// correct across layouts.
///
/// FIX NOTES:
/// 1. Wrapped in GestureDetector with HitTestBehavior.opaque so touches are
///    consumed BEFORE falling through to the VideoPlayer underneath.
/// 2. Uses LayoutBuilder to convert pixel deltas into fractional deltas so
///    positions are resolution-independent.
/// 3. Double-tap opens [TextEditorModal] for inline editing.
/// A draggable, tappable text overlay rendered on top of the video canvas.
///
/// Position is stored as fractional coordinates [overlayX, overlayY] (0.0–1.0)
/// in [TimelineClip], allowing the canvas to be any size and positions to remain
/// correct across layouts.
///
/// PERFORMANCE & STATE FIX:
/// Converted to a StatefulWidget that maintains local [_overlayX] and [_overlayY]
/// state updated via local [setState] during [onPanUpdate]. This produces butter-smooth
/// 60fps dragging under the user's finger without requiring timeline scrubbing or
/// triggering full-tree controller rebuilds on every pixel delta.
/// On [onPanEnd], the position is committed to [TimelineController] for export and undo.
class DraggableTextOverlayWidget extends StatefulWidget {
  final TimelineClip clip;
  final TimelineController controller;
  final Size canvasSize;

  const DraggableTextOverlayWidget({
    super.key,
    required this.clip,
    required this.controller,
    required this.canvasSize,
  });

  @override
  State<DraggableTextOverlayWidget> createState() => _DraggableTextOverlayWidgetState();
}

class _DraggableTextOverlayWidgetState extends State<DraggableTextOverlayWidget> {
  late double _overlayX;
  late double _overlayY;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _overlayX = widget.clip.overlayX;
    _overlayY = widget.clip.overlayY;
  }

  @override
  void didUpdateWidget(covariant DraggableTextOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _overlayX = widget.clip.overlayX;
      _overlayY = widget.clip.overlayY;
    }
  }

  Color _parseHexColor(String hex) {
    try {
      final cleanHex = hex.replaceAll('#', '');
      if (cleanHex.length == 6) {
        return Color(int.parse('FF$cleanHex', radix: 16));
      }
    } catch (_) {}
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseHexColor(widget.clip.textColorHex);

    // Convert fractional position to pixel position
    // overlayX / overlayY are the fractional anchor of the text CENTER.
    final leftPx = (_overlayX * widget.canvasSize.width).clamp(0.0, widget.canvasSize.width);
    final topPx = (_overlayY * widget.canvasSize.height).clamp(0.0, widget.canvasSize.height);

    final isSelected = widget.controller.selectedClipId == widget.clip.id;

    return Positioned(
      left: leftPx - 100, // shift so the 200px-wide bubble is centered on the anchor
      top: topPx - 20,    // shift so text is centered vertically on the anchor
      child: GestureDetector(
        // CRITICAL FIX: opaque means this GestureDetector claims the touch
        // BEFORE it reaches the VideoPlayer below in the Stack.
        behavior: HitTestBehavior.opaque,

        onTap: () {
          debugPrint('=> [TextOverlay] onTap clip=${widget.clip.id.substring(0, 8)}');
          widget.controller.selectClip(widget.clip.id);
        },

        onDoubleTap: () {
          debugPrint('=> [TextOverlay] onDoubleTap → opening TextEditorModal');
          widget.controller.selectClip(widget.clip.id);
          TextEditorModal.show(context, widget.controller, widget.clip);
        },

        onPanStart: (details) {
          _isDragging = true;
          debugPrint(
            '=> [TextOverlay] onPanStart clip=${widget.clip.id.substring(0, 8)} '
            'overlayX=${_overlayX.toStringAsFixed(3)} '
            'overlayY=${_overlayY.toStringAsFixed(3)}',
          );
          widget.controller.selectClip(widget.clip.id);
        },

        onPanUpdate: (details) {
          if (widget.canvasSize.width <= 0 || widget.canvasSize.height <= 0) return;

          // Convert pixel delta to fractional delta
          final dx = details.delta.dx / widget.canvasSize.width;
          final dy = details.delta.dy / widget.canvasSize.height;

          // Butter-smooth 60fps local update under finger
          setState(() {
            _overlayX = (_overlayX + dx).clamp(0.05, 0.95);
            _overlayY = (_overlayY + dy).clamp(0.05, 0.95);
          });

          // Sync into clip model real-time
          widget.clip.overlayX = _overlayX;
          widget.clip.overlayY = _overlayY;
        },

        onPanEnd: (details) {
          _isDragging = false;
          debugPrint(
            '=> [TextOverlay] onPanEnd '
            'finalPos=(${_overlayX.toStringAsFixed(3)}, ${_overlayY.toStringAsFixed(3)})',
          );

          // Commit position to controller so notifyListeners() fires once
          // and updates Undo/Redo & Export systems.
          widget.controller.updateTextClipPosition(
            widget.clip.id,
            dx: 0.0,
            dy: 0.0,
          );
        },

        child: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Selection border indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.amberAccent, width: 1.5)
                      : Border.all(color: Colors.transparent, width: 1.5),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
                child: Text(
                  widget.clip.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: (widget.clip.fontSize * 0.6).clamp(12.0, 36.0),
                    fontWeight: FontWeight.bold,
                    fontFamily: widget.clip.fontName,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                ),
              ),

              // Drag handle indicator when selected
              if (isSelected) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.drag_indicator_rounded, size: 12, color: Colors.black),
                      SizedBox(width: 4),
                      Text('Drag to move', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

