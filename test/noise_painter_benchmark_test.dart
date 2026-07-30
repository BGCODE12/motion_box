import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

void main() {
  testWidgets('Noise painter benchmark', (WidgetTester tester) async {
    final size = const Size(400, 80);
    final count = (size.width * size.height * 0.05).toInt();
    print('Number of points: $count');

    // Warmup
    for (int i = 0; i < 100; i++) {
      _paintUnoptimized(size, count);
      _paintOptimized(size, count);
    }

    final stopwatch = Stopwatch()..start();
    for (int i = 0; i < 1000; i++) {
      _paintUnoptimized(size, count);
    }
    stopwatch.stop();
    print('Unoptimized (real canvas): ${stopwatch.elapsedMilliseconds}ms');

    stopwatch.reset();
    stopwatch.start();
    for (int i = 0; i < 1000; i++) {
      _paintOptimized(size, count);
    }
    stopwatch.stop();
    print('Optimized (real canvas): ${stopwatch.elapsedMilliseconds}ms');
  });
}

void _paintUnoptimized(Size size, int count) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final random = math.Random(0);
  final paint = Paint()..color = Colors.white.withValues(alpha: 0.015)..strokeWidth = 1.0;
  for (int i = 0; i < count; i++) {
    canvas.drawPoints(ui.PointMode.points, [Offset(random.nextDouble() * size.width, random.nextDouble() * size.height)], paint);
  }
  recorder.endRecording();
}

void _paintOptimized(Size size, int count) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final random = math.Random(0);
  final paint = Paint()..color = Colors.white.withValues(alpha: 0.015)..strokeWidth = 1.0;
  final points = List<Offset>.generate(
    count,
    (_) => Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
    growable: false,
  );
  canvas.drawPoints(ui.PointMode.points, points, paint);
  recorder.endRecording();
}
