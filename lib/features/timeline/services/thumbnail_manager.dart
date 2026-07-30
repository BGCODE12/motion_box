import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/libre_cuts_service.dart';

/// High-performance Video Thumbnail Generation & Caching System.
/// Synchronously returns cached thumbnail paths while asynchronously extracting
/// missing frames in the background via native LibreCutsEngine.
class ThumbnailManager extends ChangeNotifier {
  static final ThumbnailManager _instance = ThumbnailManager._internal();
  factory ThumbnailManager() => _instance;

  final LibreCutsService _service = LibreCutsService();

  /// In-memory cache mapping "videoPath#timeMs" -> image file path on disk.
  final Map<String, String> _cache = {};

  /// Set of pending extraction keys to prevent redundant duplicate calls.
  final Set<String> _pendingRequests = {};

  String? _tempDirPath;

  ThumbnailManager._internal() {
    _initTempDir();
  }

  Future<void> _initTempDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _tempDirPath = tempDir.path;
    } catch (e) {
      debugPrint('[ThumbnailManager] Error getting temp directory: $e');
    }
  }

  /// Synchronously fetches cached thumbnail file paths for a clip.
  /// Returns a list of paths (or null for tiles currently extracting).
  List<String?> getThumbnailsForClip({
    required String videoPath,
    required double trimStartMs,
    required double trimEndMs,
    required double clipWidthPx,
    double tileWidthPx = 45.0,
  }) {
    if (videoPath.isEmpty) {
      return [];
    }

    final count = (clipWidthPx / tileWidthPx).ceil().clamp(1, 30);
    final durationMs = (trimEndMs - trimStartMs).clamp(100.0, double.infinity);
    final stepIntervalMs = durationMs / count;

    final results = <String?>[];

    for (int i = 0; i < count; i++) {
      final targetTimeMs = (trimStartMs + (i * stepIntervalMs)).toInt();
      final key = '$videoPath#$targetTimeMs';

      if (_cache.containsKey(key)) {
        results.add(_cache[key]);
      } else {
        results.add(null);

        if (!_pendingRequests.contains(key) && _tempDirPath != null) {
          _pendingRequests.add(key);
          _extractThumbnailInBackground(key, videoPath, targetTimeMs);
        }
      }
    }

    return results;
  }

  Future<void> _extractThumbnailInBackground(
    String key,
    String videoPath,
    int timeMs,
  ) async {
    try {
      if (_tempDirPath == null) {
        final tempDir = await getTemporaryDirectory();
        _tempDirPath = tempDir.path;
      }

      final fileName = 'thumb_${key.hashCode}.jpg';
      final outputPath = '$_tempDirPath/$fileName';

      debugPrint('[ThumbnailManager] Queueing extraction: key=$key, timeMs=$timeMs');

      final resultPath = await _service.extractFrame(
        sourcePath: videoPath,
        timeMs: timeMs,
        outputPath: outputPath,
      );

      if (resultPath != null && File(resultPath).existsSync()) {
        debugPrint('[ThumbnailManager] Thumbnail extracted successfully: $resultPath');
        _cache[key] = resultPath;
        notifyListeners(); // Triggers UI update!
      } else {
        debugPrint('[ThumbnailManager] Extraction returned invalid path: $resultPath');
      }
    } catch (e, stack) {
      debugPrint('[ThumbnailManager] Error extracting thumbnail at ${timeMs}ms: $e\n$stack');
    } finally {
      _pendingRequests.remove(key);
    }
  }

  /// Clears in-memory thumbnail cache.
  void clearCache() {
    _cache.clear();
    _pendingRequests.clear();
    notifyListeners();
  }
}
