import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CustomDrawer extends StatelessWidget {
  final String currentRoute;

  const CustomDrawer({super.key, this.currentRoute = 'Home'});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Drawer(
        backgroundColor: AppTheme.background,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16.0, right: 16.0, left: 16.0, bottom: 24.0),
                child: IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildDrawerItem(context, icon: Icons.settings_rounded, title: 'الاعدادات', isSelected: true),
                    const SizedBox(height: 12),
                    _buildDrawerItem(context, icon: Icons.language_rounded, title: 'اللغة', isSelected: false),
                    const SizedBox(height: 12),
                    _buildDrawerItem(context, icon: Icons.help_outline_rounded, title: 'الدعم', isSelected: false),
                    const SizedBox(height: 12),
                    _buildDrawerItem(context, icon: Icons.description_outlined, title: 'سياسة الاستخدام', isSelected: false),
                    const SizedBox(height: 12),
                    _buildDrawerItem(context, icon: Icons.subscriptions_outlined, title: 'الاشتراكات', isSelected: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, {required IconData icon, required String title, required bool isSelected}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSelected ? AppTheme.primary : Colors.transparent,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 16,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () => Navigator.pop(context),
      ),
    );
  }
}
