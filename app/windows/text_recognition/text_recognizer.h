// Reads the text of a chosen picture on the device with Windows OCR
// (Windows.Media.Ocr), for **From an image…** (#2327). The Windows
// counterpart of app/ios/Runner/TextRecognizer.swift: the same caps, error
// codes and line order. The picture is decoded once, read, and released:
// nothing about it is stored.
//
// Built as its own library so the runner and the native tests in
// app/windows/text_recognition/tests share it, and so it can keep C++
// exceptions on for C++/WinRT. Nothing here throws to its callers.

#ifndef TEXT_RECOGNITION_TEXT_RECOGNIZER_H_
#define TEXT_RECOGNITION_TEXT_RECOGNIZER_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace text_recognition {

// Why a picture's text could not be read.
enum class Error { kUnreadable, kTooManyPixels, kFailed };

// The platform-channel error code Dart's ChannelTextRecognitionService maps.
const char* ErrorCode(Error error);

// Largest picture read, in pixels on its longer side and in all; Dart refuses
// these first, and this is the check for a format whose header Dart cannot
// read.
constexpr uint32_t kMaxSide = 10000;
constexpr uint64_t kMaxPixels = 50000000;

// Longest side a picture is decoded at for reading; larger ones are scaled
// down to it.
constexpr uint32_t kDecodeSide = 4096;

// The BCP 47 tags (en-US) of the OCR languages installed here. Windows reads
// only the languages whose language packs the user has installed; the app
// never installs one.
std::vector<std::string> InstalledLanguageTags();

// The installed tags for the language code |language|: en matches en-US and
// en-GB.
std::vector<std::string> TagsFor(const std::string& language,
                                 const std::vector<std::string>& installed);

// Which of |languages| (language codes such as en or ja, most wanted first)
// can be read here, in the order asked.
std::vector<std::string> AvailableLanguages(
    const std::vector<std::string>& languages,
    const std::vector<std::string>& installed);

// A piece of recognized text and where it sits on the picture, in pixels
// with the origin at the top left.
struct Piece {
  std::string text;
  float left;
  float top;
  float bottom;
  float MidY() const { return (top + bottom) / 2; }
  float Height() const { return bottom - top; }
};

// |pieces| in reading order, as TextRecognizer.lines(of:) in
// app/ios/Runner/TextRecognizer.swift orders them: top to bottom, one line of
// text per row, and left to right within a row joined by spaces (pieces whose
// middles are within half a piece's height of the row's first).
std::string LinesOf(std::vector<Piece> pieces);

// A reading: the text, or why there is none.
struct Recognition {
  std::optional<Error> error;
  // One line of text per line, top to bottom; empty when nothing was read.
  std::string text;
};

// The text of the encoded picture |bytes| (PNG, JPEG, BMP, TIFF, …), read in
// the first of |languages| (language codes) that is installed.
Recognition Recognize(const std::vector<uint8_t>& bytes,
                      const std::vector<std::string>& languages,
                      const std::vector<std::string>& installed);

}  // namespace text_recognition

#endif  // TEXT_RECOGNITION_TEXT_RECOGNIZER_H_
