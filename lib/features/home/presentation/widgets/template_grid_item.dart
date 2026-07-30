import 'package:flutter/material.dart';
import '../../data/template_model.dart';

class TemplateGridItem extends StatelessWidget {
  final DesignTemplate template;
  final int index;
  final VoidCallback? onTap;

  const TemplateGridItem({
    super.key,
    required this.template,
    this.index = 0,
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
                decoration: const BoxDecoration(color: Color(0xFFACADAF)),
                child: Center(
                  child: Icon(
                    Icons.movie_creation_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            template.title,
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
