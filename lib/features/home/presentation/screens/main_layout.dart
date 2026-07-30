import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'home_screen.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/custom_drawer.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 1;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      backgroundColor: AppTheme.background,
      endDrawer: const CustomDrawer(currentRoute: 'Home'),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              const Center(child: Text('AI Magic Screen', style: TextStyle(color: Colors.white))),
              HomeScreen(scaffoldKey: _scaffoldKey),
              const Center(child: Text('Studio Screen', style: TextStyle(color: Colors.white))),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomBottomNav(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
            ),
          ),
        ],
      ),
    );
  }
}
