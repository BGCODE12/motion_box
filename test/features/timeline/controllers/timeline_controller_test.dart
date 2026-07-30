import 'package:flutter_test/flutter_test.dart';
import 'package:motion_box/features/timeline/controllers/timeline_controller.dart';
import 'package:motion_box/features/timeline/models/timeline_models.dart';

void main() {
  group('TimelineController', () {
    late TimelineController controller;

    setUp(() {
      controller = TimelineController();
    });

    test('addTextClip uses existing default text track if available', () {
      final initialTextTracks = controller.tracks.where((t) => t.type == TrackType.text).toList();
      expect(initialTextTracks.length, 1);

      controller.addTextClip(text: 'Hello World');

      final textTracks = controller.tracks.where((t) => t.type == TrackType.text);
      expect(textTracks.length, 1);
      final track = textTracks.first;
      // Default initialized text track might already have a clip, or just check the last one added
      expect(track.clips.last.title, 'Hello World');
      expect(controller.selectedClipId, track.clips.last.id);
    });

    test('addTextClip adds multiple text clips correctly', () {
      controller.addTextClip(text: 'First Text');

      final textTracks = controller.tracks.where((t) => t.type == TrackType.text);
      expect(textTracks.length, 1);
      final trackId = textTracks.first.id;
      final initialClipCount = textTracks.first.clips.length;

      controller.addTextClip(text: 'Second Text');

      final updatedTextTracks = controller.tracks.where((t) => t.type == TrackType.text);
      expect(updatedTextTracks.length, 1);
      expect(updatedTextTracks.first.id, trackId);
      expect(updatedTextTracks.first.clips.length, initialClipCount + 1);
      expect(updatedTextTracks.first.clips.last.title, 'Second Text');
    });

    test('addTextClip respects custom properties', () {
      controller.addTextClip(
        text: 'Custom Text',
        durationMs: 5000.0,
        textColorHex: '#FF0000',
        fontName: 'Arial',
        fontSize: 42.0,
      );

      final track = controller.tracks.firstWhere((t) => t.type == TrackType.text);
      final clip = track.clips.last;

      expect(clip.title, 'Custom Text');
      expect(clip.mediaDurationMs, 5000.0);
      expect(clip.textColorHex, '#FF0000');
      expect(clip.fontName, 'Arial');
      expect(clip.fontSize, 42.0);
    });

    test('addTextClip places clip at current playhead position', () {
      controller.currentPositionMs.value = 2500.0;

      controller.addTextClip(text: 'Positioned Text');

      final track = controller.tracks.firstWhere((t) => t.type == TrackType.text);
      final clip = track.clips.last;

      expect(clip.startMs, 2500.0);
    });

    test('addTextClip registers undo operation', () {
      controller.addTextClip(text: 'Undoable Text');

      final track = controller.tracks.firstWhere((t) => t.type == TrackType.text);
      final clip = track.clips.last;
      final clipId = clip.id;

      expect(controller.findClipById(clipId), isNotNull);

      controller.undo();

      expect(controller.findClipById(clipId), isNull);
    });
  });
}
