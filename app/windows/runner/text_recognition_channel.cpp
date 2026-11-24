#include "text_recognition_channel.h"

#include <flutter/standard_method_codec.h>

#include <functional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "text_recognizer.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;

// The strings in |value| when it is a list; others are skipped.
std::vector<std::string> Strings(const EncodableValue* value) {
  std::vector<std::string> strings;
  const auto* list = value ? std::get_if<EncodableList>(value) : nullptr;
  if (!list) return strings;
  for (const auto& item : *list) {
    if (const auto* text = std::get_if<std::string>(&item)) {
      strings.push_back(*text);
    }
  }
  return strings;
}

// Runs |work| on its own thread, in the multithreaded apartment the Windows
// Runtime's blocking calls need, and posts what it answers to |window|.
void RunInBackground(HWND window,
                     std::function<std::function<void()>()> work) {
  std::thread([window, work = std::move(work)]() {
    const HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    auto answer = new std::function<void()>(work());
    if (SUCCEEDED(apartment)) CoUninitialize();
    if (!PostMessage(window, TextRecognitionChannel::kAnswerMessage, 0,
                     reinterpret_cast<LPARAM>(answer))) {
      // The window is gone, and the engine with it: nobody is waiting.
      delete answer;
    }
  }).detach();
}

}  // namespace

TextRecognitionChannel::TextRecognitionChannel(
    flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "is.banner.callerscompendium/text_recognition",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [window](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<Result> result) {
        std::shared_ptr<Result> reply(std::move(result));
        const std::string& method = call.method_name();
        if (method == "availableLanguages") {
          auto asked = Strings(call.arguments());
          RunInBackground(window, [asked, reply]() -> std::function<void()> {
            const auto found = text_recognition::AvailableLanguages(
                asked, text_recognition::InstalledLanguageTags());
            EncodableList list;
            for (const auto& language : found) list.emplace_back(language);
            return [reply, list]() { reply->Success(EncodableValue(list)); };
          });
        } else if (method == "recognize") {
          const auto* args = call.arguments()
                                 ? std::get_if<EncodableMap>(call.arguments())
                                 : nullptr;
          const std::vector<uint8_t>* bytes = nullptr;
          const EncodableValue* languages = nullptr;
          if (args) {
            auto found = args->find(EncodableValue("bytes"));
            if (found != args->end()) {
              bytes = std::get_if<std::vector<uint8_t>>(&found->second);
            }
            auto asked = args->find(EncodableValue("languages"));
            if (asked != args->end()) languages = &asked->second;
          }
          if (!bytes) {
            reply->Error(text_recognition::ErrorCode(
                text_recognition::Error::kUnreadable));
            return;
          }
          RunInBackground(
              window, [data = *bytes, asked = Strings(languages),
                       reply]() -> std::function<void()> {
                const auto reading = text_recognition::Recognize(
                    data, asked, text_recognition::InstalledLanguageTags());
                if (reading.error) {
                  const std::string code =
                      text_recognition::ErrorCode(*reading.error);
                  return [reply, code]() { reply->Error(code); };
                }
                return [reply, text = reading.text]() {
                  reply->Success(EncodableValue(text));
                };
              });
        } else {
          reply->NotImplemented();
        }
      });
}

void TextRecognitionChannel::TakeAnswer(LPARAM lparam, bool run) {
  std::unique_ptr<std::function<void()>> answer(
      reinterpret_cast<std::function<void()>*>(lparam));
  if (run && answer && *answer) (*answer)();
}
