import 'dart:async';
import '../../services/libre_cuts_service.dart';


/// Result type for LibreCuts video engine operations.
abstract class RenderResult {
  const RenderResult();
}

class RenderSuccess extends RenderResult {
  final String outputPath;
  const RenderSuccess(this.outputPath);
}

class RenderFailure extends RenderResult {
  final String error;
  const RenderFailure(this.error);
}

class RenderCancelled extends RenderResult {
  const RenderCancelled();
}

/// Legacy wrapper redirecting calls to native [LibreCutsService].
class LibreCutsEngine {
  static final LibreCutsEngine _instance = LibreCutsEngine._internal();
  factory LibreCutsEngine() => _instance;
  LibreCutsEngine._internal();

  final LibreCutsService _service = LibreCutsService();

  Future<void> cancelAllSessions() async {
    await _service.cancelExport();
  }

  Future<RenderResult> cropVideo({
    required String sourcePath,
    required String aspectRatio,
    required String outputPath,
  }) async {
    try {
      final res = await _service.renderExport(
        sourcePath: sourcePath,
        outputPath: outputPath,
        resolution: 1080,
      );
      if (res != null) return RenderSuccess(res);
      return const RenderFailure('Export failed');
    } catch (e) {
      return RenderFailure(e.toString());
    }
  }

  Future<RenderResult> renderMultiSlotComposition({
    required List<SlotCompositionItem> items,
    required int targetWidth,
    required int targetHeight,
    required double durationSecs,
    required String outputPath,
    Function(int progress)? onProgress,
  }) async {
    try {
      final res = await _service.renderExport(
        sourcePath: items.firstOrNull?.mediaPath,
        outputPath: outputPath,
        resolution: targetHeight,
      );
      if (res != null) return RenderSuccess(res);
      return const RenderFailure('Multi-slot composition failed');
    } catch (e) {
      return RenderFailure(e.toString());
    }
  }
}

class SlotCompositionItem {
  final String slotId;
  final String mediaPath;
  final double left;
  final double top;
  final double width;
  final double height;
  final bool isVideo;

  const SlotCompositionItem({
    required this.slotId,
    required this.mediaPath,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.isVideo = true,
  });
}
