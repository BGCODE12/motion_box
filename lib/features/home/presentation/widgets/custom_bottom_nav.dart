import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C242F).withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(40.0),
                  border: Border.all(
                    color: const Color(0xFF687088).withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: CustomPaint(
                  painter: _NoisePainter(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: _buildNavItem(0, _buildAIIcon(currentIndex == 0))),
                      Expanded(child: _buildNavItem(1, _buildHomeIcon(currentIndex == 1))),
                      Expanded(child: _buildNavItem(2, _buildStudioIcon(currentIndex == 2))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, Widget child) {
    final bool isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          width: isSelected ? 76 : 50,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.0),
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF687088).withValues(alpha: 0.35),
                      const Color(0xFF1C242F).withValues(alpha: 0.85),
                    ],
                  )
                : null,
            border: Border.all(
              color: isSelected ? const Color(0xFF687088).withValues(alpha: 0.6) : Colors.transparent,
              width: 0.6,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: const Color(0xFF687088).withValues(alpha: 0.18), blurRadius: 16, spreadRadius: 2, offset: const Offset(0, 2))]
                : [],
          ),
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isSelected ? 1.0 : 0.5,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAIIcon(bool isSelected) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topRight,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.5), borderRadius: BorderRadius.circular(6)),
          child: const Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        const Positioned(top: -3, right: -5, child: Icon(Icons.auto_awesome, color: Colors.white, size: 9)),
      ],
    );
  }

  Widget _buildHomeIcon(bool isSelected) {
    return Icon(isSelected ? Icons.home_rounded : Icons.home_outlined, color: Colors.white, size: 24);
  }

  Widget _buildStudioIcon(bool isSelected) {
    return const Icon(Icons.layers_rounded, color: Colors.white, size: 24);
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // NOTE: Generating a list of points and making a single drawPoints call
    // avoids making thousands of JNI/engine calls per frame.
    final random = math.Random();
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.015)..strokeWidth = 1.0;
    final count = (size.width * size.height * 0.05).toInt();
    final points = List<Offset>.generate(
      count,
      (_) => Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
      growable: false,
    );
    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
