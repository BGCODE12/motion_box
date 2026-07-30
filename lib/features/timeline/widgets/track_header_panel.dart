import 'package:flutter/material.dart';
import '../controllers/timeline_controller.dart';

/// Fixed-width Left Panel containing Track Headers (Video, CC/Text, Audio)
/// matching the dddd.PNG design mockup.
class TrackHeaderPanel extends StatelessWidget {
  final TimelineController controller;
  final VoidCallback? onAddVideo;
  final VoidCallback? onAddText;
  final VoidCallback? onAddAudio;

  const TrackHeaderPanel({
    super.key,
    required this.controller,
    this.onAddVideo,
    this.onAddText,
    this.onAddAudio,
  });

  static const double panelWidth = 76.0;
  static const double headerHeight = 28.0;
  static const double rowHeight = 44.0;

  static const Color colorHeaderBg = Color(0xFF161B24);
  static const Color colorTrackRowBg = Color(0xFF202B38);
  static const Color colorBorder = Color(0xFF2A3646);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: panelWidth,
      child: Column(
        children: [
          // 1. Top Ruler Space — fixed height matching TimelineRuler
          Container(
            height: headerHeight,
            decoration: const BoxDecoration(
              color: colorHeaderBg,
              border: Border(bottom: BorderSide(color: colorBorder, width: 0.8)),
            ),
          ),

          // 2–4. Track rows fill remaining space equally
          Expanded(
            child: Column(
              children: [
                // Video Track Header
                Expanded(
                  child: _buildHeaderRow(
                    icon: Icons.play_circle_outline_rounded,
                    accentColor: const Color(0xFF3B82F6),
                    actionWidget: _buildActionButton(
                      child: const Icon(Icons.widgets_outlined,
                          size: 13, color: Colors.black87),
                      onTap: onAddVideo,
                    ),
                  ),
                ),

                // Text / CC Track Header
                Expanded(
                  child: _buildHeaderRow(
                    customLabel: 'CC',
                    accentColor: const Color(0xFFE55353),
                    actionWidget: _buildActionButton(
                      child: const Text(
                        'Fx',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      onTap: onAddText,
                    ),
                  ),
                ),

                // Audio Track Header
                Expanded(
                  child: _buildHeaderRow(
                    icon: Icons.music_note_rounded,
                    accentColor: const Color(0xFF80848E),
                    actionWidget: _buildActionButton(
                      child: const Icon(Icons.add_rounded,
                          size: 15, color: Colors.black87),
                      onTap: onAddAudio,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildHeaderRow({
    IconData? icon,
    String? customLabel,
    required Color accentColor,
    required Widget actionWidget,
  }) {
    return Container(
      // No fixed height — fills the Expanded parent.
      decoration: const BoxDecoration(
        color: colorTrackRowBg,
        border: Border(
          bottom: BorderSide(color: colorBorder, width: 0.8),
          right: BorderSide(color: colorBorder, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Accent Line + Track Icon/Label
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                if (icon != null)
                  Icon(icon, size: 15, color: Colors.white70)
                else if (customLabel != null)
                  Text(
                    customLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),

          // Right Action Button (Grid, Fx, +)
          actionWidget,
        ],
      ),
    );
  }

  Widget _buildActionButton({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

