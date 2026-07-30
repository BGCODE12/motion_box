import 'package:flutter_test/flutter_test.dart';
import 'package:motion_box/features/timeline/models/timeline_models.dart';

void main() {
  group('TimelineClip.effectiveDurationMs', () {
    test('calculates correct duration with normal speed (1.0x)', () {
      final clip = TimelineClip(
        id: '1',
        title: 'Clip 1',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 1000.0,
        trimEndMs: 4000.0,
        speed: 1.0,
      );

      // (4000 - 1000) / 1.0 = 3000
      expect(clip.effectiveDurationMs, 3000.0);
    });

    test('calculates correct duration with fast speed (2.0x)', () {
      final clip = TimelineClip(
        id: '2',
        title: 'Clip 2',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 1000.0,
        trimEndMs: 4000.0,
        speed: 2.0,
      );

      // (4000 - 1000) / 2.0 = 1500
      expect(clip.effectiveDurationMs, 1500.0);
    });

    test('calculates correct duration with slow speed (0.5x)', () {
      final clip = TimelineClip(
        id: '3',
        title: 'Clip 3',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 1000.0,
        trimEndMs: 4000.0,
        speed: 0.5,
      );

      // (4000 - 1000) / 0.5 = 6000
      expect(clip.effectiveDurationMs, 6000.0);
    });

    test('clamps duration to minimum 100.0ms when trim duration is very small', () {
      final clip = TimelineClip(
        id: '4',
        title: 'Clip 4',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 1000.0,
        trimEndMs: 1050.0, // 50ms diff
        speed: 1.0,
      );

      // (1050 - 1000) / 1.0 = 50ms -> clamped to 100ms
      expect(clip.effectiveDurationMs, 100.0);
    });

    test('clamps duration to minimum 100.0ms when fast speed makes duration too small', () {
      final clip = TimelineClip(
        id: '5',
        title: 'Clip 5',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 1000.0,
        trimEndMs: 1150.0, // 150ms diff
        speed: 2.0, // 150 / 2 = 75ms
      );

      // (1150 - 1000) / 2.0 = 75ms -> clamped to 100ms
      expect(clip.effectiveDurationMs, 100.0);
    });

    test('clamps duration to minimum 100.0ms when negative duration (trimEnd < trimStart)', () {
      final clip = TimelineClip(
        id: '6',
        title: 'Clip 6',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 2000.0,
        trimEndMs: 1000.0, // negative 1000
        speed: 1.0,
      );

      // (1000 - 2000) / 1.0 = -1000ms -> clamped to 100ms
      expect(clip.effectiveDurationMs, 100.0);
    });

    test('clamps duration to minimum 100.0ms when zero duration (trimEnd == trimStart)', () {
      final clip = TimelineClip(
        id: '7',
        title: 'Clip 7',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
        trimStartMs: 1000.0,
        trimEndMs: 1000.0, // 0 diff
        speed: 1.0,
      );

      // (1000 - 1000) / 1.0 = 0ms -> clamped to 100ms
      expect(clip.effectiveDurationMs, 100.0);
    });

    test('handles default trim values', () {
      final clip = TimelineClip(
        id: '8',
        title: 'Clip 8',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 5000.0,
      );

      // defaults: trimStart=0, trimEnd=mediaDuration (5000), speed=1.0
      // (5000 - 0) / 1.0 = 5000
      expect(clip.effectiveDurationMs, 5000.0);
    });
  });
}
