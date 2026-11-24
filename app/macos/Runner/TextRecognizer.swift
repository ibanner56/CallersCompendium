// Reads the text of a chosen picture on the device with Apple Vision (#2327).
//
// Kept identical in app/ios/Runner and app/macos/Runner; Dart's
// `app/test/text_recognition_native_parity_test.dart` fails when the copies
// differ. The picture is decoded once, read, and released: nothing about it is
// stored.

import Foundation
import ImageIO
import Vision

/// Why a picture's text could not be read; the raw value is the platform-channel
/// error code `ChannelTextRecognitionService` maps.
enum TextRecognitionError: String, Error {
  case unreadable
  case tooManyPixels
  case failed
}

/// `internal` (not `private`) so the `RunnerTests` target can exercise it via
/// `@testable import`.
enum TextRecognizer {
  /// Largest picture read, in pixels on its longer side and in all; the Dart
  /// side refuses these first (`kMaxRecognitionImageSide`,
  /// `kMaxRecognitionImagePixels`), and this is the check for a format whose
  /// header Dart cannot read.
  static let maxSide = 10_000
  static let maxPixels = 50_000_000

  /// The recognition languages Vision offers here, as BCP 47 tags (`en-US`).
  static func supportedLanguageTags() -> [String] {
    if #available(iOS 15.0, macOS 12.0, *) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      return (try? request.supportedRecognitionLanguages()) ?? []
    }
    return (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
      for: .accurate, revision: VNRecognizeTextRequestRevision1)) ?? []
  }

  /// Which of `languages` (language codes such as `en` or `ja`, most wanted
  /// first) Vision can read here, in the order asked.
  static func availableLanguages(
    _ languages: [String], supported: [String] = supportedLanguageTags()
  ) -> [String] {
    languages.filter { !tags(for: $0, in: supported).isEmpty }
  }

  /// The supported tags for the language code `language`: `en` matches
  /// `en-US` and `en-GB`.
  static func tags(for language: String, in supported: [String]) -> [String] {
    let code = language.lowercased()
    return supported.filter {
      let tag = $0.lowercased()
      return tag == code || tag.hasPrefix(code + "-") || tag.hasPrefix(code + "_")
    }
  }

  /// The text of the encoded picture `data`, one line of text per line, top to
  /// bottom, read in `languages` (language codes).
  static func recognize(
    data: Data, languages: [String], supported: [String] = supportedLanguageTags()
  ) throws -> String {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0
    else { throw TextRecognitionError.unreadable }
    let properties =
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    if width > maxSide || height > maxSide || width * height > maxPixels {
      throw TextRecognitionError.tooManyPixels
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw TextRecognitionError.unreadable
    }
    let orientation =
      (properties[kCGImagePropertyOrientation] as? NSNumber).flatMap {
        CGImagePropertyOrientation(rawValue: $0.uint32Value)
      } ?? .up

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages.flatMap { tags(for: $0, in: supported) }
    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
    do {
      try handler.perform([request])
    } catch {
      throw TextRecognitionError.failed
    }
    let observations = request.results ?? []
    return lines(of: observations.compactMap { observation in
      observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
    })
  }

  /// Recognized strings in reading order: top to bottom, and left to right
  /// within a line (pieces whose middles are within half a piece's height of
  /// the line's first). Vision's bounding boxes are normalized with the origin
  /// at the bottom left.
  static func lines(of texts: [(String, CGRect)]) -> String {
    let topDown = texts.sorted { $0.1.midY > $1.1.midY }
    var rows: [[(String, CGRect)]] = []
    for text in topDown {
      if let first = rows.last?.first,
        abs(first.1.midY - text.1.midY) < min(first.1.height, text.1.height) / 2
      {
        rows[rows.count - 1].append(text)
      } else {
        rows.append([text])
      }
    }
    return rows
      .map { row in row.sorted { $0.1.minX < $1.1.minX }.map { $0.0 }.joined(separator: " ") }
      .joined(separator: "\n")
  }
}
