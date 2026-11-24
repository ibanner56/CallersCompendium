import Flutter
import Foundation

/// The platform channel behind **From an image…** on iOS (#2327): Dart's
/// `ChannelTextRecognitionService` asks which languages Vision reads and sends
/// a chosen picture's bytes to read. The work runs off the main thread; the
/// bytes are released when it finishes. Shared logic: `TextRecognizer.swift`.
public class TextRecognitionPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "is.banner.callerscompendium/text_recognition",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TextRecognitionPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    TextRecognitionCall.handle(call.method, call.arguments, result: result)
  }
}

/// The channel's two methods, for the iOS plugin and the macOS bridge alike.
enum TextRecognitionCall {
  static func handle(_ method: String, _ arguments: Any?, result: @escaping FlutterResult) {
    switch method {
    case "availableLanguages":
      let asked = arguments as? [String] ?? []
      DispatchQueue.global(qos: .userInitiated).async {
        let found = TextRecognizer.availableLanguages(asked)
        DispatchQueue.main.async { result(found) }
      }
    case "recognize":
      guard let args = arguments as? [String: Any],
        let bytes = args["bytes"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: TextRecognitionError.unreadable.rawValue, message: nil, details: nil))
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
          answer = FlutterError(code: TextRecognitionError.failed.rawValue, message: nil, details: nil)
        }
        DispatchQueue.main.async { result(answer) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
