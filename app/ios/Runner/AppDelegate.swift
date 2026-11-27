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
    // Receive-side share import (issue #298): forwards OS "open with" / AirDrop
    // files to Dart. Registered after the generated plugins so it shares the
    // implicit engine's messenger and scene life-cycle stream.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingFilesPlugin") {
      IncomingFilesPlugin.register(with: registrar)
    }
    // From an image… (#2327): reads a chosen picture's text with Apple Vision.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TextRecognitionPlugin") {
      TextRecognitionPlugin.register(with: registrar)
    }
    // The device-backup marker (sync-spec §3.3).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NoBackupMarkerPlugin") {
      NoBackupMarkerPlugin.register(with: registrar)
    }
  }
}

/// Answers the `is.banner.callerscompendium/no_backup` channel for Dart's
/// `restored_copy_check.dart`, which recognises a library restored from an
/// iCloud or computer backup, or carried to a new iPhone (sync-spec §3.3).
/// Android's twin is `MainActivity.kt`.
class NoBackupMarkerPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/no_backup",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NoBackupMarkerPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "markerExists":
        result(NoBackupMarker.exists(in: try NoBackupMarker.applicationSupport()))
      case "writeMarker":
        try NoBackupMarker.write(in: try NoBackupMarker.applicationSupport())
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
    }
  }
}

/// The device-backup marker itself. The plugin keeps it in Application
/// Support, which the system never clears on its own (unlike Caches and tmp),
/// with `isExcludedFromBackup` set so a backup does not carry it. Takes its
/// directory as a parameter so RunnerTests can use a throwaway one.
enum NoBackupMarker {
  static let fileName = "device_backup_marker"

  static func applicationSupport() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
  }

  static func exists(in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
  }

  /// Creates the marker if it is missing, and sets its backup exclusion every
  /// time, so a marker whose exclusion did not stick is excluded before Dart
  /// records it as written.
  static func write(in directory: URL) throws {
    var url = directory.appendingPathComponent(fileName)
    if !FileManager.default.fileExists(atPath: url.path) {
      try Data([1]).write(to: url, options: .atomic)
    }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
}
