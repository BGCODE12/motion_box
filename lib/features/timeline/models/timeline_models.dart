import 'package:flutter/material.dart';

/// Supported track types in the NLE timeline.
enum TrackType { video, audio, text, overlay }

/// Extension to get display attributes for each track type.
extension TrackTypeExtension on TrackType {
  String get title {
    switch (this) {
      case TrackType.video:
        return 'Main Video';
      case TrackType.audio:
        return 'Audio Track';
      case TrackType.text:
        return 'Text Overlay';
      case TrackType.overlay:
        return 'PIP / Overlay';
    }
  }

  IconData get icon {
    switch (this) {
      case TrackType.video:
        return Icons.movie_creation_rounded;
      case TrackType.audio:
        return Icons.audiotrack_rounded;
      case TrackType.text:
        return Icons.title_rounded;
      case TrackType.overlay:
        return Icons.layers_rounded;
    }
  }

  Color get defaultColor {
    switch (this) {
      case TrackType.video:
        return const Color(0xFF3B82F6); // Blue
      case TrackType.audio:
        return const Color(0xFF10B981); // Emerald Green
      case TrackType.text:
        return const Color(0xFFF59E0B); // Amber
      case TrackType.overlay:
        return const Color(0xFFEC4899); // Pink
    }
  }
}

/// Represents an individual media clip on a timeline track.
class TimelineClip {
  final String id;
  String title;
  final String? mediaPath;
  final TrackType type;

  /// Position of clip start on timeline in milliseconds.
  double startMs;

  /// Raw un-trimmed duration of media file in milliseconds.
  double mediaDurationMs;

  /// Trim start offset inside media file in milliseconds (In-point).
  double trimStartMs;

  /// Trim end position inside media file in milliseconds (Out-point).
  double trimEndMs;

  /// Playback speed multiplier (e.g. 0.5x, 1.0x, 2.0x).
  double speed;

  /// Audio volume (0.0 to 2.0).
  double volume;

  /// Visual accent color for timeline clip block.
  Color color;

  /// Text Overlay properties
  String textColorHex;
  String fontName;
  double fontSize;

  /// Canvas position as fractions of the video canvas size (0.0 to 1.0).
  /// (0.5, 0.5) = centered. (0.5, 0.85) = bottom center.
  double overlayX;
  double overlayY;

  TimelineClip({
    required this.id,
    required this.title,
    this.mediaPath,
    required this.type,
    required this.startMs,
    required this.mediaDurationMs,
    double? trimStartMs,
    double? trimEndMs,
    this.speed = 1.0,
    this.volume = 1.0,
    Color? color,
    this.textColorHex = '#FFFFFF',
    this.fontName = 'Roboto',
    this.fontSize = 36.0,
    this.overlayX = 0.5,
    this.overlayY = 0.85,
  })  : trimStartMs = trimStartMs ?? 0.0,
        trimEndMs = trimEndMs ?? mediaDurationMs,
        color = color ?? type.defaultColor;

  /// Effective duration on the timeline taking trim and speed into account.
  double get effectiveDurationMs => ((trimEndMs - trimStartMs) / speed).clamp(100.0, double.infinity);

  /// End position of this clip on the timeline in milliseconds.
  double get endMs => startMs + effectiveDurationMs;

  /// Creates a copy of this clip with optional parameter overrides.
  TimelineClip copyWith({
    String? id,
    String? title,
    String? mediaPath,
    TrackType? type,
    double? startMs,
    double? mediaDurationMs,
    double? trimStartMs,
    double? trimEndMs,
    double? speed,
    double? volume,
    Color? color,
    String? textColorHex,
    String? fontName,
    double? fontSize,
    double? overlayX,
    double? overlayY,
  }) {
    return TimelineClip(
      id: id ?? this.id,
      title: title ?? this.title,
      mediaPath: mediaPath ?? this.mediaPath,
      type: type ?? this.type,
      startMs: startMs ?? this.startMs,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      color: color ?? this.color,
      textColorHex: textColorHex ?? this.textColorHex,
      fontName: fontName ?? this.fontName,
      fontSize: fontSize ?? this.fontSize,
      overlayX: overlayX ?? this.overlayX,
      overlayY: overlayY ?? this.overlayY,
    );
  }
}

/// Represents a single track lane containing multiple sequential or layered clips.
class TimelineTrack {
  final String id;
  final String name;
  final TrackType type;
  final List<TimelineClip> clips;
  bool isMuted;
  bool isLocked;

  TimelineTrack({
    required this.id,
    required this.name,
    required this.type,
    List<TimelineClip>? clips,
    this.isMuted = false,
    this.isLocked = false,
  }) : clips = clips ?? [];
}
