import 'package:flutter/material.dart';
import '../../data/template_model.dart';

class LayoutTemplateGridItem extends StatelessWidget {
  final TemplateModel template;
  final VoidCallback? onTap;

  const LayoutTemplateGridItem({
    super.key,
    required this.template,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.0),
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFF2A2E39)),
                child: CustomPaint(
                  painter: _SlotPainter(slots: template.slots),
                  child: Center(
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            template.name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SlotPainter extends CustomPainter {
  final List<SlotModel> slots;

  _SlotPainter({required this.slots});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF346EE0).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final slot in slots) {
      final rect = Rect.fromLTWH(
        slot.left * size.width + 2,
        slot.top * size.height + 2,
        slot.width * size.width - 4,
        slot.height * size.height - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
