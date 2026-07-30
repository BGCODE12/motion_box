import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../features/timeline/controllers/timeline_controller.dart';
import '../features/timeline/models/timeline_models.dart';

/// Helper service for serializing TimelineController state into LibreCuts JSON recipes.
class ExportService {
  /// Builds a complete map representation of the VideoProject ready for LibreCutsEngine.
  static Map<String, dynamic> buildExportRecipe({
    required TimelineController controller,
    required String sourcePath,
    String projectName = 'MotionBox Render',
  }) {
    final operations = <Map<String, dynamic>>[];

    // 1. Mute Main Audio Operation
    if (controller.isMainVideoMuted) {
      operations.add({
        'type': 'MuteAudio',
        'id': 'op_mute_${DateTime.now().millisecondsSinceEpoch}',
      });
    }

    // 2. Main Video Trims
    final videoTrack = controller.tracks.firstWhere(
      (t) => t.type == TrackType.video,
      orElse: () => controller.tracks.first,
    );

    for (final clip in videoTrack.clips) {
      if (clip.trimStartMs > 0 || clip.trimEndMs < clip.mediaDurationMs) {
        operations.add({
          'type': 'Trim',
          'startMs': clip.trimStartMs.toInt(),
          'endMs': clip.trimEndMs.toInt(),
          'id': clip.id,
        });
      }
    }

    // Default Aspect Ratio Crop
    operations.add({
      'type': 'Crop',
      'aspectRatio': '9:16',
    });

    // 3. Text Overlays
    for (final track in controller.tracks) {
      if (track.type == TrackType.text) {
        for (final clip in track.clips) {
          operations.add({
            'type': 'AddText',
            'id': clip.id,
            'text': clip.title,
            'fontSize': clip.fontSize.toInt(),
            'relativeX': clip.overlayX,
            'relativeY': clip.overlayY,
            'color': clip.textColorHex,
            'fontPath': clip.fontName,
            'startTimeMs': clip.startMs.toInt(),
            'endTimeMs': clip.endMs.toInt(),
            'position': 'BOTTOM_CENTER',
          });
        }
      }
    }

    // 4. Background Audio Tracks
    for (final track in controller.tracks) {
      if (track.type == TrackType.audio) {
        for (final clip in track.clips) {
          if (clip.mediaPath != null) {
            operations.add({
              'type': 'AddBackgroundAudio',
              'id': clip.id,
              'audioUri': clip.mediaPath,
              'volume': clip.volume,
              'internalStartMs': clip.trimStartMs.toInt(),
              'internalEndMs': clip.trimEndMs.toInt(),
              'startTimeMs': clip.startMs.toInt(),
              'endTimeMs': clip.endMs.toInt(),
              'removeOriginalAudio': false,
            });
          }
        }
      }
    }

    final recipeMap = {
      'projectName': projectName,
      'sourceUri': sourcePath,
      'sourceName': sourcePath.split(RegExp(r'[/\\]')).last,
      'operations': operations,
    };

    debugPrint('=> [ExportService] Generated recipe payload with ${operations.length} operations');
    return recipeMap;
  }

  static String buildExportRecipeJson({
    required TimelineController controller,
    required String sourcePath,
  }) {
    return jsonEncode(buildExportRecipe(controller: controller, sourcePath: sourcePath));
  }
}
