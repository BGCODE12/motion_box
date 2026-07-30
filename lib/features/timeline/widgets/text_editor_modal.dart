import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/timeline_controller.dart';
import '../models/timeline_models.dart';

/// Professional Text Editor Modal Bottom Sheet allowing real-time editing of
/// text string, text color palette, font family, and font size.
class TextEditorModal extends StatefulWidget {
  final TimelineController controller;
  final TimelineClip clip;

  const TextEditorModal({
    super.key,
    required this.controller,
    required this.clip,
  });

  static void show(BuildContext context, TimelineController controller, TimelineClip clip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TextEditorModal(controller: controller, clip: clip),
    );
  }

  @override
  State<TextEditorModal> createState() => _TextEditorModalState();
}

class _TextEditorModalState extends State<TextEditorModal> {
  late TextEditingController _textController;
  late String _selectedColorHex;
  late String _selectedFont;
  late double _fontSize;

  final List<Map<String, String>> _colorPalette = [
    {'name': 'White', 'hex': '#FFFFFF'},
    {'name': 'Yellow', 'hex': '#FFEB3B'},
    {'name': 'Red', 'hex': '#F44336'},
    {'name': 'Green', 'hex': '#4CAF50'},
    {'name': 'Cyan', 'hex': '#00BCD4'},
    {'name': 'Purple', 'hex': '#9C27B0'},
    {'name': 'Pink', 'hex': '#E91E63'},
    {'name': 'Orange', 'hex': '#FF9800'},
    {'name': 'Black', 'hex': '#000000'},
  ];

  final List<String> _fontFamilies = [
    'Roboto',
    'Montserrat',
    'Outfit',
    'Monospace',
    'Serif',
    'Sans-Serif',
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.clip.title);
    _selectedColorHex = widget.clip.textColorHex;
    _selectedFont = widget.clip.fontName;
    _fontSize = widget.clip.fontSize;
  }

  void _applyChanges() {
    widget.controller.updateTextClip(
      widget.clip.id,
      newText: _textController.text.trim(),
      newColorHex: _selectedColorHex,
      newFontName: _selectedFont,
      newFontSize: _fontSize,
    );
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.style_rounded, color: AppTheme.primary, size: 22),
                    SizedBox(width: 8),
                    Text('Edit Text Overlay', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 1. Live Text String Input
            TextField(
              controller: _textController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              onChanged: (_) => _applyChanges(),
              decoration: InputDecoration(
                hintText: 'Enter overlay text...',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Color Palette Selector
            const Text('Text Color', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _colorPalette.length,
                itemBuilder: (context, index) {
                  final colorItem = _colorPalette[index];
                  final hex = colorItem['hex']!;
                  final color = _parseHexColor(hex);
                  final isSelected = _selectedColorHex == hex;

                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedColorHex = hex);
                      _applyChanges();
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.amberAccent : Colors.white24,
                          width: isSelected ? 3.0 : 1.0,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check_rounded, size: 18, color: Colors.black) : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // 3. Font Family Selector
            const Text('Font Family', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _fontFamilies.map((font) {
                  final isSelected = _selectedFont == font;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(font, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textSecondary, fontSize: 12)),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      backgroundColor: AppTheme.surfaceVariant,
                      onSelected: (_) {
                        setState(() => _selectedFont = font);
                        _applyChanges();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Font Size Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Font Size', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${_fontSize.toInt()} px', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
            Slider(
              value: _fontSize,
              min: 16.0,
              max: 72.0,
              divisions: 28,
              activeColor: AppTheme.primary,
              inactiveColor: AppTheme.surfaceVariant,
              onChanged: (val) {
                setState(() => _fontSize = val);
                _applyChanges();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
