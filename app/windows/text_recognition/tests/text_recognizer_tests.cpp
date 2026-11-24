// Native tests for the Windows OCR recognizer (#2327), the counterpart of the
// TextRecognizerTests in app/ios/RunnerTests and app/macos/RunnerTests. CI's
// Windows build leg builds and runs them (.github/workflows/ci.yml). Each
// picture is drawn here with GDI+, so no image file is checked in.
//
// Exits 0 when every check passes, 1 otherwise; each failure is printed.

#include <windows.h>

#include <algorithm>
// GDI+'s headers use min and max, which NOMINMAX takes away.
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>
#include <objidl.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>

#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "text_recognizer.h"

namespace {

int failures = 0;

void Check(bool condition, const char* what, const std::string& detail = "") {
  if (condition) return;
  ++failures;
  std::printf("FAIL: %s%s%s\n", what, detail.empty() ? "" : "\n  got: ",
              detail.c_str());
}

bool Contains(const std::string& text, const char* piece) {
  return text.find(piece) != std::string::npos;
}

std::vector<std::string> Lines(const std::string& text) {
  std::vector<std::string> lines;
  size_t start = 0;
  while (start <= text.size()) {
    const size_t end = text.find('\n', start);
    lines.push_back(text.substr(start, end == std::string::npos
                                           ? std::string::npos
                                           : end - start));
    if (end == std::string::npos) break;
    start = end + 1;
  }
  return lines;
}

CLSID EncoderFor(const wchar_t* mime) {
  UINT count = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&count, &size);
  std::vector<uint8_t> buffer(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(count, size, codecs);
  for (UINT i = 0; i < count; ++i) {
    if (std::wstring(codecs[i].MimeType) == mime) return codecs[i].Clsid;
  }
  return CLSID{};
}

// |bitmap| encoded as |mime| (image/png, image/jpeg).
std::vector<uint8_t> Encode(Gdiplus::Bitmap& bitmap, const wchar_t* mime) {
  IStream* stream = nullptr;
  std::vector<uint8_t> bytes;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return bytes;
  const CLSID encoder = EncoderFor(mime);
  if (bitmap.Save(stream, &encoder, nullptr) == Gdiplus::Ok) {
    STATSTG stat{};
    stream->Stat(&stat, STATFLAG_NONAME);
    bytes.resize(static_cast<size_t>(stat.cbSize.QuadPart));
    LARGE_INTEGER start{};
    stream->Seek(start, STREAM_SEEK_SET, nullptr);
    ULONG read = 0;
    stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read);
    bytes.resize(read);
  }
  stream->Release();
  return bytes;
}

// A white card with |lines| typed on it in black, one under another.
std::unique_ptr<Gdiplus::Bitmap> Card(const std::vector<std::wstring>& lines) {
  const int height = 120 + 90 * static_cast<int>(lines.size());
  auto bitmap =
      std::make_unique<Gdiplus::Bitmap>(1600, height, PixelFormat24bppRGB);
  Gdiplus::Graphics graphics(bitmap.get());
  graphics.Clear(Gdiplus::Color(255, 255, 255, 255));
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
  Gdiplus::FontFamily family(L"Arial");
  Gdiplus::Font font(&family, 48, Gdiplus::FontStyleRegular,
                     Gdiplus::UnitPixel);
  Gdiplus::SolidBrush ink(Gdiplus::Color(255, 0, 0, 0));
  for (size_t i = 0; i < lines.size(); ++i) {
    graphics.DrawString(
        lines[i].c_str(), -1, &font,
        Gdiplus::PointF(40.0f, 60.0f + 90.0f * static_cast<float>(i)), &ink);
  }
  return bitmap;
}

const std::vector<std::string> kInstalled = {"en-US"};

void TestInstalledLanguagesIncludeEnglish() {
  const auto installed = text_recognition::InstalledLanguageTags();
  Check(!text_recognition::TagsFor("en", installed).empty(),
        "Windows OCR offers English on this machine (the CI image's own "
        "language); the recognition tests below need it");
}

void TestLanguageCodesMatchInstalledTags() {
  using text_recognition::AvailableLanguages;
  using text_recognition::TagsFor;
  Check(TagsFor("en", {"en-US", "en-GB", "de-DE"}).size() == 2,
        "en matches en-US and en-GB");
  Check(TagsFor("EN", {"en-us"}).size() == 1, "matching ignores case");
  Check(TagsFor("e", {"en-US"}).empty(), "e does not match en-US");
  Check(TagsFor("", {"en-US"}).empty(), "an empty code matches nothing");
  Check(AvailableLanguages({"ja", "en"}, {"en-US"}) ==
            std::vector<std::string>{"en"},
        "only installed languages are available, in the order asked");
  Check(AvailableLanguages({"de", "en"}, {}).empty(),
        "with no OCR language installed, nothing is available");
}

void TestATypedCardReadsAsItsLinesInOrder() {
  auto card = Card({L"A1 (8) Neighbor balance and swing",
                    L"A2 (8) Long lines forward and back"});
  const auto reading = text_recognition::Recognize(
      Encode(*card, L"image/png"), {"en"},
      text_recognition::InstalledLanguageTags());
  Check(!reading.error, "a typed card is read");
  const auto lines = Lines(reading.text);
  Check(lines.size() == 2, "a typed card reads as two lines", reading.text);
  if (lines.size() == 2) {
    Check(Contains(lines[0], "Neighbor balance"), "line 1 first",
          reading.text);
    Check(Contains(lines[1], "Long lines"), "line 2 second", reading.text);
  }
}

void TestAPictureStoredSidewaysIsReadUpright() {
  // Orientation 6: the stored pixels must turn 90° clockwise to display, so
  // the upright card is stored turned 90° counter-clockwise (270° clockwise).
  auto card = Card({L"A1 (8) Neighbor balance and swing",
                    L"A2 (8) Long lines"});
  card->RotateFlip(Gdiplus::Rotate270FlipNone);
  USHORT orientation = 6;
  Gdiplus::PropertyItem item{};
  item.id = PropertyTagOrientation;
  item.length = sizeof(orientation);
  item.type = PropertyTagTypeShort;
  item.value = &orientation;
  card->SetPropertyItem(&item);
  const auto bytes = Encode(*card, L"image/jpeg");

  // Positive control: the file really is stored sideways with orientation 6,
  // so an upright reading below proves the orientation was applied.
  using winrt::Windows::Graphics::Imaging::BitmapDecoder;
  winrt::Windows::Storage::Streams::InMemoryRandomAccessStream stream;
  winrt::Windows::Storage::Streams::DataWriter writer(stream);
  writer.WriteBytes(winrt::array_view<const uint8_t>(
      bytes.data(), bytes.data() + bytes.size()));
  writer.StoreAsync().get();
  writer.DetachStream();
  stream.Seek(0);
  const auto decoder = BitmapDecoder::CreateAsync(stream).get();
  Check(decoder.PixelWidth() < decoder.PixelHeight() &&
            decoder.OrientedPixelWidth() > decoder.OrientedPixelHeight(),
        "the fixture is stored tall and displays wide (orientation 6)");

  const auto reading = text_recognition::Recognize(
      bytes, {"en"}, text_recognition::InstalledLanguageTags());
  Check(!reading.error, "a sideways photo is read");
  const auto lines = Lines(reading.text);
  Check(lines.size() == 2, "a sideways photo reads as two lines",
        reading.text);
  if (lines.size() == 2) {
    Check(Contains(lines[0], "Neighbor balance"), "upright line 1 first",
          reading.text);
    Check(Contains(lines[1], "Long lines"), "upright line 2 second",
          reading.text);
  }
}

void TestAPictureOverThePixelCapIsRefusedBeforeReading() {
  Gdiplus::Bitmap wide(static_cast<INT>(text_recognition::kMaxSide + 1), 1,
                       PixelFormat24bppRGB);
  const auto reading = text_recognition::Recognize(
      Encode(wide, L"image/png"), {"en"}, kInstalled);
  Check(reading.error == text_recognition::Error::kTooManyPixels,
        "a picture wider than the cap is refused as too many pixels");
}

void TestBytesThatAreNotAPictureAreUnreadable() {
  const std::string text = "not a picture";
  const auto reading = text_recognition::Recognize(
      std::vector<uint8_t>(text.begin(), text.end()), {"en"},
      text_recognition::InstalledLanguageTags());
  Check(reading.error == text_recognition::Error::kUnreadable,
        "bytes that are not a picture are unreadable");
  Check(text_recognition::Recognize({}, {"en"}, kInstalled).error ==
            text_recognition::Error::kUnreadable,
        "no bytes are unreadable");
}

void TestNoInstalledLanguageFailsWithoutReading() {
  auto card = Card({L"A1 (8) Neighbor balance and swing"});
  const auto reading =
      text_recognition::Recognize(Encode(*card, L"image/png"), {"en"}, {});
  Check(reading.error == text_recognition::Error::kFailed,
        "with no installed OCR language, reading fails");
}

void TestErrorCodesMatchTheChannel() {
  using text_recognition::Error;
  using text_recognition::ErrorCode;
  Check(std::string(ErrorCode(Error::kUnreadable)) == "unreadable",
        "unreadable code");
  Check(std::string(ErrorCode(Error::kTooManyPixels)) == "tooManyPixels",
        "tooManyPixels code");
  Check(std::string(ErrorCode(Error::kFailed)) == "failed", "failed code");
}

}  // namespace

int main() {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token = 0;
  Gdiplus::GdiplusStartup(&token, &input, nullptr);

  TestInstalledLanguagesIncludeEnglish();
  TestLanguageCodesMatchInstalledTags();
  TestATypedCardReadsAsItsLinesInOrder();
  TestAPictureStoredSidewaysIsReadUpright();
  TestAPictureOverThePixelCapIsRefusedBeforeReading();
  TestBytesThatAreNotAPictureAreUnreadable();
  TestNoInstalledLanguageFailsWithoutReading();
  TestErrorCodesMatchTheChannel();

  Gdiplus::GdiplusShutdown(token);
  std::printf("Windows text recognition tests: %d failure(s)\n", failures);
  return failures == 0 ? 0 : 1;
}
