import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OpenFilePlugin") {
      OpenFilePlugin.register(with: registrar)
    }
  }
}

/// Passes painting files opened from other apps ("Open in JingyaoPaint" from
/// Files, AirDrop or a chat app) to Flutter over the `jingyao/open_file`
/// channel, the same way MainActivity.kt does on Android. See
/// lib/share/incoming_files.dart.
///
/// iOS hands the file to the window scene: with the launch options when it
/// starts the app, and in `openURLContexts` while the app is running. Flutter
/// replays the launch options to plugins registered after the scene
/// connected, so registering with the implicit engine is early enough.
final class OpenFilePlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private static let channelName = "jingyao/open_file"

  /// Paintings are small JSON; refuse anything absurdly large.
  private static let maxFileBytes = 50 * 1024 * 1024

  private let channel: FlutterMethodChannel

  /// A file that launched the app, held until Flutter is ready to ask.
  private var pendingFile: Data?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = OpenFilePlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "takeInitialFile" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(pendingFile.map { FlutterStandardTypedData(bytes: $0) })
    pendingFile = nil
  }

  /// The app was started to open a file.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let url = connectionOptions?.urlContexts.first?.url,
      let data = Self.read(url)
    else { return false }
    pendingFile = data
    return true
  }

  /// A file was opened while the app was running.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    guard let url = URLContexts.first?.url, let data = Self.read(url) else { return false }
    channel.invokeMethod("openFile", arguments: FlutterStandardTypedData(bytes: data))
    return true
  }

  /// The bytes of the painting file at [url], or nil if it isn't one.
  private static func read(_ url: URL) -> Data? {
    guard url.isFileURL, url.pathExtension.lowercased() == "jypaint" else { return nil }
    // Files opened from another app's storage need this; copies in the
    // app's own Inbox don't, and the call is then a harmless no-op.
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
      // iOS copies opened files into Documents/Inbox. The painting is
      // imported into the app's own store, so the copy isn't needed.
      if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
    }
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileBytes {
      return nil
    }
    return try? Data(contentsOf: url)
  }
}
