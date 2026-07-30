import 'timeline_models.dart';

/// Sealed base class for all reversible timeline operations.
///
/// Every mutating method in [TimelineController] constructs the appropriate
/// subclass BEFORE applying its change, snapshots the before-state into it,
/// then pushes it onto `_undoStack`.
///
/// [undo] pattern-matches on this type and applies the exact inverse.
/// [redo] re-applies the forward state from the same snapshot.
sealed class UndoOperation {
  const UndoOperation();
}

// -----------------------------------------------------------------------------
// MoveOp — clip dragged to a new timeline position
// -----------------------------------------------------------------------------
final class MoveOp extends UndoOperation {
  final String clipId;
  final double oldStartMs;
  final double newStartMs;

  const MoveOp({
    required this.clipId,
    required this.oldStartMs,
    required this.newStartMs,
  });

  @override
  String toString() =>
      'MoveOp($clipId: ${oldStartMs.toStringAsFixed(0)} ? ${newStartMs.toStringAsFixed(0)} ms)';
}

// -----------------------------------------------------------------------------
// TrimOp — trim handles adjusted (in-point or out-point)
//
// Snapshots ALL four fields that trimClipStart/trimClipEnd can mutate so that
// undo/redo is a single atomic restore with no recomputation.
// -----------------------------------------------------------------------------
final class TrimOp extends UndoOperation {
  final String clipId;

  // State BEFORE the trim gesture
  final double oldTrimStartMs;
  final double oldTrimEndMs;
  final double oldStartMs;          // timeline position also shifts on trimStart
  final double oldMediaDurationMs;  // text clips grow mediaDurationMs on expand

  // State AFTER the trim gesture
  final double newTrimStartMs;
  final double newTrimEndMs;
  final double newStartMs;
  final double newMediaDurationMs;

  const TrimOp({
    required this.clipId,
    required this.oldTrimStartMs,
    required this.oldTrimEndMs,
    required this.oldStartMs,
    required this.oldMediaDurationMs,
    required this.newTrimStartMs,
    required this.newTrimEndMs,
    required this.newStartMs,
    required this.newMediaDurationMs,
  });

  @override
  String toString() =>
      'TrimOp($clipId: trim[${oldTrimStartMs.toStringAsFixed(0)},${oldTrimEndMs.toStringAsFixed(0)}]'
      ' ? [${newTrimStartMs.toStringAsFixed(0)},${newTrimEndMs.toStringAsFixed(0)}])';
}

// -----------------------------------------------------------------------------
// DeleteOp — clip removed from a track
//
// Stores the full clip snapshot + insertion metadata so undo can re-insert it
// at exactly the same position in the same track.
// -----------------------------------------------------------------------------
final class DeleteOp extends UndoOperation {
  final String trackId;
  final int clipIndex;     // original position in track.clips list
  final TimelineClip clip; // deep snapshot via copyWith()

  const DeleteOp({
    required this.trackId,
    required this.clipIndex,
    required this.clip,
  });

  @override
  String toString() =>
      'DeleteOp(track=$trackId idx=$clipIndex clip=${clip.id})';
}

// -----------------------------------------------------------------------------
// AddOp — clip added to a track (text overlay or audio clip)
//
// Stores the full clip so redo can re-insert it at the same position.
// -----------------------------------------------------------------------------
final class AddOp extends UndoOperation {
  final String trackId;
  final TimelineClip clip; // full snapshot for redo re-insertion

  const AddOp({
    required this.trackId,
    required this.clip,
  });

  @override
  String toString() =>
      'AddOp(track=$trackId clip=${clip.id} "${clip.title}")';
}

// -----------------------------------------------------------------------------
// SplitOp — clip split into two halves at playhead position
//
// Stores the original clip + both resulting halves so:
//   undo ? remove both halves, re-insert originalClip at originalIndex
//   redo ? remove originalClip, re-insert firstHalf + secondHalf
// -----------------------------------------------------------------------------
final class SplitOp extends UndoOperation {
  final String trackId;
  final int originalIndex;       // position of the clip before split
  final TimelineClip originalClip;
  final TimelineClip firstHalf;
  final TimelineClip secondHalf;

  const SplitOp({
    required this.trackId,
    required this.originalIndex,
    required this.originalClip,
    required this.firstHalf,
    required this.secondHalf,
  });

  @override
  String toString() =>
      'SplitOp(track=$trackId idx=$originalIndex '
      '"${originalClip.title}" ? [${firstHalf.id}, ${secondHalf.id}])';
}
