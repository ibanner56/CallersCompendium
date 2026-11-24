#ifndef RUNNER_TEXT_RECOGNITION_CHANNEL_H_
#define RUNNER_TEXT_RECOGNITION_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// The platform channel behind **From an image…** on Windows (#2327): Dart's
// ChannelTextRecognitionService asks which languages Windows OCR reads and
// sends a chosen picture's bytes to read. The same contract as
// app/ios/Runner/TextRecognitionPlugin.swift and
// app/macos/Runner/TextRecognitionBridge.swift; keep the three in step. The
// work runs on a background thread, and its answer is handed back on the
// window's thread, where Flutter requires it.
class TextRecognitionChannel {
 public:
  // The window message that carries an answer back to the window's thread.
  static constexpr UINT kAnswerMessage = WM_APP + 0x2327;

  TextRecognitionChannel(flutter::BinaryMessenger* messenger, HWND window);

  // Runs (|run|) or drops an answer posted with kAnswerMessage, and frees it.
  // The window's message handler calls this for that message, and drops the
  // answer once the Flutter engine is gone.
  static void TakeAnswer(LPARAM lparam, bool run);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
};

#endif  // RUNNER_TEXT_RECOGNITION_CHANNEL_H_
