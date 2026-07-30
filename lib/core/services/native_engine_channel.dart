import 'dart:io';
import 'package:flutter/services.dart';

class NativeEngineChannel {
  static const MethodChannel _channel = MethodChannel('com.motionbox.motion_box/librecuts_engine');

  /// Runs hardware-accelerated export on Android via MethodChannel if on Android platform.
  static Future<bool> executeHardwareExport(String command) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<Map>('executeHardwareExport', {
        'command': command,
      });
      return result?['status'] == 'success';
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Cancels active native FFmpeg sessions on Android.
  static Future<void> cancelNativeSessions() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelSessions');
    } on PlatformException catch (_) {}
  }
}
