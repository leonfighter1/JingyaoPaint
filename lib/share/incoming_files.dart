import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Painting files opened from other apps ("open with JingyaoPaint").
///
/// On Android `MainActivity.kt`, and on iOS `OpenFilePlugin` in
/// `AppDelegate.swift`, read the file the user opened and pass its bytes over
/// this channel. Other platforms have no handler, which is fine; they import
/// through the in-app file picker instead.
abstract final class IncomingFiles {
  static const _channel = MethodChannel('jingyao/open_file');

  /// Calls [onFile] with the file that launched the app (if any) and with
  /// every file opened later while the app is running.
  static Future<void> listen(Future<void> Function(Uint8List bytes) onFile) async {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile' && call.arguments is Uint8List) {
        await onFile(call.arguments as Uint8List);
      }
    });
    try {
      final initial = await _channel.invokeMethod<Uint8List>('takeInitialFile');
      if (initial != null) await onFile(initial);
    } on MissingPluginException {
      // Not Android or iOS: nothing is ever opened from outside.
    }
  }
}
