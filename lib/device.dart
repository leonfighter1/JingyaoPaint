import 'package:flutter/foundation.dart';

import 'device_browser.dart';

/// What the app runs on, so texts can say what's true there: "photo album"
/// or "Photos", Back button or Cancel, saved on the device or in the browser.
enum DeviceKind {
  android,

  /// iPhone or iPad app.
  apple,

  /// Any browser, on any system (see [Device.browser]).
  web,

  /// Windows, macOS or Linux desktop app.
  desktop,
}

class Device {
  const Device(this.kind, {this.browser, this.desktopOs = false});

  final DeviceKind kind;

  /// The browser's name (Safari, Chrome, Edge, Firefox…) on the web.
  final String? browser;

  /// Whether the system underneath is a desktop one (a mouse, likely), also
  /// for a browser on Windows or a Mac.
  final bool desktopOs;

  bool get isWeb => kind == DeviceKind.web;

  /// Set in tests to act as another device.
  @visibleForTesting
  static Device? debugOverride;

  static Device get current {
    if (debugOverride case final d?) return d;
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    if (kIsWeb) {
      return Device(DeviceKind.web, browser: browserName(), desktopOs: desktop);
    }
    return Device(
      switch (defaultTargetPlatform) {
        TargetPlatform.android => DeviceKind.android,
        TargetPlatform.iOS => DeviceKind.apple,
        _ => DeviceKind.desktop,
      },
      desktopOs: desktop,
    );
  }
}
