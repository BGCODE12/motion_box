import 'package:flutter_test/flutter_test.dart';
import 'package:motion_box/features/timeline/controllers/timeline_controller.dart';
import 'package:motion_box/features/timeline/models/timeline_models.dart';
import 'package:motion_box/services/export_service.dart';

void main() {
  group('ExportService', () {
    late TimelineController controller;

    setUp(() {
      controller = TimelineController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('buildExportRecipe generates basic structure and default Crop operation', () {
      final recipe = ExportService.buildExportRecipe(
        controller: controller,
        sourcePath: '/path/to/source.mp4',
      );

      expect(recipe['projectName'], 'MotionBox Render');
      expect(recipe['sourceUri'], '/path/to/source.mp4');
      expect(recipe['sourceName'], 'source.mp4');

      final operations = recipe['operations'] as List<Map<String, dynamic>>;
      expect(operations, isNotEmpty);

      // Verify Crop operation is present
      final cropOp = operations.firstWhere(
        (op) => op['type'] == 'Crop',
        orElse: () => {},
      );
      expect(cropOp, isNotEmpty, reason: 'Default Crop operation should be present');
      expect(cropOp['aspectRatio'], '9:16');
    });

    test('buildExportRecipe includes MuteAudio operation when main video is muted', () {
      controller.toggleMainVideoMute();
      expect(controller.isMainVideoMuted, isTrue);

      final recipe = ExportService.buildExportRecipe(
        controller: controller,
        sourcePath: '/path/to/source.mp4',
      );

      final operations = recipe['operations'] as List<Map<String, dynamic>>;

      final muteOp = operations.firstWhere(
        (op) => op['type'] == 'MuteAudio',
        orElse: () => {},
      );
      expect(muteOp, isNotEmpty, reason: 'MuteAudio operation should be present');
      expect(muteOp['id'], startsWith('op_mute_'));
    });

    test('buildExportRecipe includes Trim operation for trimmed video clips', () {
      // Clear existing clips and add a trimmed one
      controller.tracks.first.clips.clear();

      final clip = TimelineClip(
        id: 'v1',
        title: 'Video',
        type: TrackType.video,
        startMs: 0.0,
        mediaDurationMs: 1000.0,
        trimStartMs: 100.0,
      );

      controller.addClipToTrack(controller.tracks.first.id, clip);

      final recipe = ExportService.buildExportRecipe(
        controller: controller,
        sourcePath: '/path/to/source.mp4',
      );

      final operations = recipe['operations'] as List<Map<String, dynamic>>;

      final trimOp = operations.firstWhere(
        (op) => op['type'] == 'Trim',
        orElse: () => {},
      );
      expect(trimOp, isNotEmpty, reason: 'Trim operation should be present');
      expect(trimOp['id'], 'v1');
      expect(trimOp['startMs'], 100);
      expect(trimOp['endMs'], 1000); // defaults to mediaDurationMs
    });

    test('buildExportRecipe includes AddText operation for text clips', () {
      controller.tracks.firstWhere((t) => t.type == TrackType.text).clips.clear();
      controller.addTextClip(text: "Hello");

      final recipe = ExportService.buildExportRecipe(
        controller: controller,
        sourcePath: '/path/to/source.mp4',
      );

      final operations = recipe['operations'] as List<Map<String, dynamic>>;

      final textOp = operations.firstWhere(
        (op) => op['type'] == 'AddText',
        orElse: () => {},
      );
      expect(textOp, isNotEmpty, reason: 'AddText operation should be present');
      expect(textOp['text'], 'Hello');
      expect(textOp['position'], 'BOTTOM_CENTER');
      expect(textOp['color'], isNotNull);
      expect(textOp['fontSize'], isNotNull);
    });

    test('buildExportRecipe includes AddBackgroundAudio operation for audio clips', () {
      controller.addAudioClip(title: "BGM", audioPath: "audio.mp3", durationMs: 1000.0);

      final recipe = ExportService.buildExportRecipe(
        controller: controller,
        sourcePath: '/path/to/source.mp4',
      );

      final operations = recipe['operations'] as List<Map<String, dynamic>>;

      final audioOp = operations.firstWhere(
        (op) => op['type'] == 'AddBackgroundAudio',
        orElse: () => {},
      );
      expect(audioOp, isNotEmpty, reason: 'AddBackgroundAudio operation should be present');
      expect(audioOp['audioUri'], 'audio.mp3');
      expect(audioOp['volume'], 1.0);
    });
  });
}
