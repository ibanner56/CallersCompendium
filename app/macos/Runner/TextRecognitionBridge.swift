import FlutterMacOS
import Foundation

/// The platform channel behind **From an image…** on macOS (#2327): Dart's
/// `ChannelTextRecognitionService` asks which languages Vision reads and sends
/// a chosen picture's bytes to read. The work runs off the main thread; the
/// bytes are released when it finishes. Shared logic: `TextRecognizer.swift`.
final class TextRecognitionBridge {
  static let shared = TextRecognitionBridge()
  private init() {}

  private var channel: FlutterMethodChannel?

  /// Wires the channel to the engine messenger once the Flutter view controller
  /// exists.
  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/text_recognition",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "availableLanguages":
        let asked = call.arguments as? [String] ?? []
        DispatchQueue.global(qos: .userInitiated).async {
          let found = TextRecognizer.availableLanguages(asked)
          DispatchQueue.main.async { result(found) }
        }
      case "recognize":
        guard let args = call.arguments as? [String: Any],
          let bytes = args["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: TextRecognitionError.unreadable.rawValue, message: nil, details: nil))
          return
        }
        let languages = args["languages"] as? [String] ?? []
        DispatchQueue.global(qos: .userInitiated).async {
          let answer: Any
          do {
            answer = try TextRecognizer.recognize(data: bytes.data, languages: languages)
          } catch let error as TextRecognitionError {
            answer = FlutterError(code: error.rawValue, message: nil, details: nil)
          } catch {
            answer = FlutterError(
              code: TextRecognitionError.failed.rawValue, message: nil, details: nil)
          }
          DispatchQueue.main.async { result(answer) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }
}
