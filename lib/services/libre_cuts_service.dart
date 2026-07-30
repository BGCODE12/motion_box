import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';


/// Status of the video export process.
enum RenderStatus { rendering, success, error, cancelled }

/// Progress update event emitted by [LibreCutsService.progressStream].
class RenderProgress {
  final RenderStatus status;
  final int progress; // 0 to 100
  final String? outputPath;
  final String? errorMessage;

  RenderProgress({
    required this.status,
    this.progress = 0,
    this.outputPath,
    this.errorMessage,
  });

  factory RenderProgress.fromMap(Map<dynamic, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'rendering';
    final progressVal = (map['progress'] as num?)?.toInt() ?? 0;
    final path = map['outputPath'] as String?;
    final err = map['message'] as String?;

    RenderStatus status;
    switch (statusStr) {
      case 'success':
        status = RenderStatus.success;
        break;
      case 'error':
        status = RenderStatus.error;
        break;
      case 'cancelled':
        status = RenderStatus.cancelled;
        break;
      case 'rendering':
      default:
        status = RenderStatus.rendering;
        break;
    }

    return RenderProgress(
      status: status,
      progress: progressVal.clamp(0, 100),
      outputPath: path,
      errorMessage: err,
    );
  }
}

/// Service interface to connect your custom Flutter UI to the native LibreCuts Engine.
class LibreCutsService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.yourcompany.librecuts/engine');

  static const EventChannel _eventChannel =
      EventChannel('com.yourcompany.librecuts/export_progress');

  Stream<RenderProgress>? _progressStream;

  /// Stream emitting real-time export progress updates (0% to 100%) and completion events.
  Stream<RenderProgress> get progressStream {
    _progressStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => RenderProgress.fromMap(event as Map<dynamic, dynamic>));
    return _progressStream!;
  }

  /// Triggers a video export on the native LibreCuts engine.
  ///
  /// [recipeMap] Timeline edit recipe as a Map — will be JSON-encoded before sending.
  /// [sourcePath] Absolute path to the primary source video file.
  /// [outputPath] Desired destination path for the exported video file.
  /// [resolution] Export vertical resolution in pixels (e.g. 1080, 720).
  /// [fps] Frames per second (e.g. 30, 60).
  Future<String?> renderExport({
    Map<String, dynamic>? recipeMap,
    String? recipeJson,
    String? sourcePath,
    required String outputPath,
    int resolution = 1080,
    int fps = 30,
    bool audioOnly = false,
    String fontAssetPath = 'fonts/Roboto-Regular.ttf',
  }) async {
    final String? finalRecipe =
        recipeJson ?? (recipeMap != null ? jsonEncode(recipeMap) : null);

    debugPrint('[LibreCutsService] ── renderExport called ──────────────────');
    debugPrint('[LibreCutsService]   channel  : $_methodChannel');
    debugPrint('[LibreCutsService]   method   : renderExport');
    debugPrint('[LibreCutsService]   sourcePath: ${sourcePath ?? "(null)"}');
    debugPrint('[LibreCutsService]   outputPath: $outputPath');
    debugPrint('[LibreCutsService]   resolution: $resolution  fps: $fps');
    debugPrint('[LibreCutsService]   recipe   : ${finalRecipe == null ? "(null)" : "${finalRecipe.length} chars"}');

    if (finalRecipe == null && (sourcePath == null || sourcePath.isEmpty)) {
      debugPrint('[LibreCutsService]   ERROR — both recipe and sourcePath are empty, aborting.');
      throw Exception('Cannot export: no recipe and no source video path provided.');
    }

    try {
      final String? resultPath = await _methodChannel.invokeMethod<String>(
        'renderExport',
        {
          'recipe': finalRecipe,
          'sourcePath': sourcePath,
          'outputPath': outputPath,
          'resolution': resolution,
          'fps': fps,
          'audioOnly': audioOnly,
          'fontAssetPath': fontAssetPath,
        },
      );
      debugPrint('[LibreCutsService]   MethodChannel result: $resultPath');
      return resultPath;
    } on PlatformException catch (e) {
      debugPrint('[LibreCutsService]   PlatformException: code=${e.code} msg=${e.message}');
      throw Exception('Video export failed [${e.code}]: ${e.message}');
    } catch (e) {
      debugPrint('[LibreCutsService]   Unexpected error: $e');
      rethrow;
    }
  }


  /// Cancels any currently running FFmpeg export session.
  Future<void> cancelExport() async {
    try {
      await _methodChannel.invokeMethod('cancelExport');
    } on PlatformException catch (e) {
      throw Exception('Failed to cancel export: ${e.message}');
    }
  }

  /// Fast audio stream extraction from a video.
  Future<String?> extractAudio({
    required String sourcePath,
    required String outputPath,
  }) async {
    try {
      return await _methodChannel.invokeMethod<String>('extractAudio', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
      });
    } on PlatformException catch (e) {
      throw Exception('Audio extraction failed: ${e.message}');
    }
  }

  /// Extracts a single frame thumbnail at [timeMs].
  Future<String?> extractFrame({
    required String sourcePath,
    required int timeMs,
    required String outputPath,
  }) async {
    try {
      debugPrint('[LibreCutsService] Invoking extractFrame: sourcePath=$sourcePath, timeMs=$timeMs, outputPath=$outputPath');
      final result = await _methodChannel.invokeMethod<String>('extractFrame', {
        'sourcePath': sourcePath,
        'timeMs': timeMs,
        'outputPath': outputPath,
      });
      debugPrint('[LibreCutsService] extractFrame result: $result');
      return result;
    } on PlatformException catch (e) {
      debugPrint('[LibreCutsService] PlatformException in extractFrame: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[LibreCutsService] Exception in extractFrame: $e');
      return null;
    }
  }
}

