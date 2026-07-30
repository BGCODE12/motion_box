import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CategoryToggles extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;

  const CategoryToggles({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _buildToggle('Pranding'),
          const SizedBox(width: 12),
          _buildToggle('Basic'),
        ],
      ),
    );
  }

  Widget _buildToggle(String title) {
    final bool isSelected = selectedCategory == title;
    return Expanded(
      child: GestureDetector(
        onTap: () => onCategoryChanged(title),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 57,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(28.5),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
