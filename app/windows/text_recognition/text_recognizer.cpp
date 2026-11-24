#include "text_recognizer.h"

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <limits>
#include <utility>

namespace text_recognition {

namespace {

using winrt::Windows::Globalization::Language;
using winrt::Windows::Graphics::Imaging::BitmapAlphaMode;
using winrt::Windows::Graphics::Imaging::BitmapDecoder;
using winrt::Windows::Graphics::Imaging::BitmapInterpolationMode;
using winrt::Windows::Graphics::Imaging::BitmapPixelFormat;
using winrt::Windows::Graphics::Imaging::BitmapTransform;
using winrt::Windows::Graphics::Imaging::ColorManagementMode;
using winrt::Windows::Graphics::Imaging::ExifOrientationMode;
using winrt::Windows::Graphics::Imaging::SoftwareBitmap;
using winrt::Windows::Media::Ocr::OcrEngine;
using winrt::Windows::Media::Ocr::OcrLine;
using winrt::Windows::Storage::Streams::DataWriter;
using winrt::Windows::Storage::Streams::InMemoryRandomAccessStream;

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return text;
}

// |text| with where its line sits on the picture: its words' union.
Piece PieceOf(std::string text, const OcrLine& line) {
  Piece piece{std::move(text), std::numeric_limits<float>::max(),
              std::numeric_limits<float>::max(),
              std::numeric_limits<float>::lowest()};
  for (const auto& word : line.Words()) {
    const auto rect = word.BoundingRect();
    piece.left = std::min(piece.left, rect.X);
    piece.top = std::min(piece.top, rect.Y);
    piece.bottom = std::max(piece.bottom, rect.Y + rect.Height);
  }
  if (piece.bottom < piece.top) piece.left = piece.top = piece.bottom = 0;
  return piece;
}

Recognition Failure(Error error) { return Recognition{error, {}}; }

}  // namespace

const char* ErrorCode(Error error) {
  switch (error) {
    case Error::kUnreadable:
      return "unreadable";
    case Error::kTooManyPixels:
      return "tooManyPixels";
    case Error::kFailed:
      return "failed";
  }
  return "failed";
}

std::vector<std::string> InstalledLanguageTags() {
  std::vector<std::string> tags;
  try {
    for (const auto& language : OcrEngine::AvailableRecognizerLanguages()) {
      tags.push_back(winrt::to_string(language.LanguageTag()));
    }
  } catch (...) {
    // No OCR here (a Windows edition without it): no languages.
    tags.clear();
  }
  return tags;
}

std::vector<std::string> TagsFor(const std::string& language,
                                 const std::vector<std::string>& installed) {
  const std::string code = Lower(language);
  std::vector<std::string> found;
  if (code.empty()) return found;
  for (const auto& tag : installed) {
    const std::string lower = Lower(tag);
    if (lower == code || lower.rfind(code + "-", 0) == 0 ||
        lower.rfind(code + "_", 0) == 0) {
      found.push_back(tag);
    }
  }
  return found;
}

std::vector<std::string> AvailableLanguages(
    const std::vector<std::string>& languages,
    const std::vector<std::string>& installed) {
  std::vector<std::string> available;
  for (const auto& language : languages) {
    if (!TagsFor(language, installed).empty()) available.push_back(language);
  }
  return available;
}

std::string LinesOf(std::vector<Piece> pieces) {
  std::stable_sort(pieces.begin(), pieces.end(),
                   [](const Piece& a, const Piece& b) {
                     return a.MidY() < b.MidY();
                   });
  std::vector<std::vector<Piece>> rows;
  for (auto& piece : pieces) {
    if (!rows.empty()) {
      const Piece& first = rows.back().front();
      if (std::fabs(first.MidY() - piece.MidY()) <
          std::min(first.Height(), piece.Height()) / 2) {
        rows.back().push_back(std::move(piece));
        continue;
      }
    }
    rows.push_back({std::move(piece)});
  }
  std::string text;
  for (auto& row : rows) {
    std::stable_sort(row.begin(), row.end(),
                     [](const Piece& a, const Piece& b) {
                       return a.left < b.left;
                     });
    if (!text.empty()) text += '\n';
    for (size_t i = 0; i < row.size(); ++i) {
      if (i > 0) text += ' ';
      text += row[i].text;
    }
  }
  return text;
}

Recognition Recognize(const std::vector<uint8_t>& bytes,
                      const std::vector<std::string>& languages,
                      const std::vector<std::string>& installed) {
  try {
    if (bytes.empty()) return Failure(Error::kUnreadable);

    InMemoryRandomAccessStream stream;
    DataWriter writer(stream);
    writer.WriteBytes(winrt::array_view<const uint8_t>(
        bytes.data(), bytes.data() + bytes.size()));
    writer.StoreAsync().get();
    writer.DetachStream();
    stream.Seek(0);

    BitmapDecoder decoder{nullptr};
    try {
      decoder = BitmapDecoder::CreateAsync(stream).get();
    } catch (...) {
      return Failure(Error::kUnreadable);
    }
    const uint32_t width = decoder.PixelWidth();
    const uint32_t height = decoder.PixelHeight();
    if (width == 0 || height == 0) return Failure(Error::kUnreadable);
    if (width > kMaxSide || height > kMaxSide ||
        static_cast<uint64_t>(width) * height > kMaxPixels) {
      return Failure(Error::kTooManyPixels);
    }

    // Windows OCR reads one language at a time: the first one asked for
    // that is installed (the app's language, else English).
    OcrEngine engine{nullptr};
    for (const auto& language : languages) {
      for (const auto& tag : TagsFor(language, installed)) {
        engine = OcrEngine::TryCreateFromLanguage(
            Language(winrt::to_hstring(tag)));
        if (engine) break;
      }
      if (engine) break;
    }
    if (!engine) return Failure(Error::kFailed);

    // Decoded no larger than kDecodeSide (and the engine's own limit) on its
    // longer side, and turned upright by its EXIF orientation, so a picture
    // at the pixel cap does not take ~200 MB of memory. The scale is the
    // same on both sides, so it is given in the stored (unturned) frame.
    const uint32_t limit = std::min(kDecodeSide, OcrEngine::MaxImageDimension());
    const uint32_t longer = std::max(width, height);
    BitmapTransform transform;
    transform.InterpolationMode(BitmapInterpolationMode::Fant);
    if (longer > limit) {
      const double scale = static_cast<double>(limit) / longer;
      transform.ScaledWidth(std::max<uint32_t>(
          1, static_cast<uint32_t>(std::floor(width * scale))));
      transform.ScaledHeight(std::max<uint32_t>(
          1, static_cast<uint32_t>(std::floor(height * scale))));
    }
    SoftwareBitmap bitmap{nullptr};
    try {
      bitmap = decoder
                   .GetSoftwareBitmapAsync(
                       BitmapPixelFormat::Bgra8, BitmapAlphaMode::Premultiplied,
                       transform, ExifOrientationMode::RespectExifOrientation,
                       ColorManagementMode::DoNotColorManage)
                   .get();
    } catch (...) {
      return Failure(Error::kUnreadable);
    }

    const auto result = engine.RecognizeAsync(bitmap).get();
    std::vector<Piece> pieces;
    for (const auto& line : result.Lines()) {
      std::string piece = winrt::to_string(line.Text());
      if (!piece.empty()) pieces.push_back(PieceOf(std::move(piece), line));
    }
    const std::string text = LinesOf(std::move(pieces));
    return Recognition{std::nullopt, text};
  } catch (...) {
    return Failure(Error::kFailed);
  }
}

}  // namespace text_recognition
