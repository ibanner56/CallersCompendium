import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/error_log.dart';

/// Reading the text of a chosen picture on the device (#2327): Apple Vision
/// on iOS and macOS, nothing elsewhere yet. The picture
/// is read once and released; only the text leaves this file.

/// Largest picture file read, in bytes.
const int kMaxRecognitionImageBytes = 25 * 1024 * 1024;

/// Largest picture read, in pixels on its longer side.
const int kMaxRecognitionImageSide = 10000;

/// Largest picture read, in pixels in all.
const int kMaxRecognitionImagePixels = 50 * 1000 * 1000;

/// Whether, and in which languages, this device can read a picture's text.
@immutable
class TextRecognitionAvailability {
  const TextRecognitionAvailability({required this.languages});

  /// None: the platform has no text recognition, or none of the languages
  /// asked for.
  static const TextRecognitionAvailability none = TextRecognitionAvailability(
    languages: [],
  );

  /// The language codes (`en`, `ja`, …) of those asked for that the device
  /// can read, in the order asked.
  final List<String> languages;

  bool get isAvailable => languages.isNotEmpty;
}

/// Why a picture's text could not be read.
enum TextRecognitionFailure {
  /// The file is larger than [kMaxRecognitionImageBytes].
  tooLarge,

  /// The picture is larger than [kMaxRecognitionImageSide] or
  /// [kMaxRecognitionImagePixels].
  tooManyPixels,

  /// The file is not a picture the device can open.
  unreadable,

  /// The picture holds no text the device could read.
  noText,

  /// The device's text recognition failed.
  failed,
}

/// A picture whose text could not be read, and why.
class TextRecognitionException implements Exception {
  const TextRecognitionException(this.reason);

  final TextRecognitionFailure reason;

  @override
  String toString() => 'TextRecognitionException($reason)';
}

/// Reads the text of a picture on the device.
abstract interface class TextRecognitionService {
  /// Which of [languages] (language codes, most wanted first) the device can
  /// read.
  Future<TextRecognitionAvailability> availability(List<String> languages);

  /// The text of the encoded picture [bytes] (JPEG, PNG, HEIC, …), one line
  /// of text per line, read in [languages]. Throws
  /// [TextRecognitionException].
  Future<String> recognize(Uint8List bytes, {required List<String> languages});
}

/// The platform channel to the native recognizer: app/ios/Runner/
/// TextRecognitionPlugin.swift on iOS and app/macos/Runner/
/// TextRecognitionBridge.swift on macOS.
class ChannelTextRecognitionService implements TextRecognitionService {
  ChannelTextRecognitionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Platform-channel name shared with the native handlers.
  static const String channelName =
      'is.banner.callerscompendium/text_recognition';

  final MethodChannel _channel;

  @override
  Future<TextRecognitionAvailability> availability(
    List<String> languages,
  ) async {
    try {
      final found = await _channel.invokeListMethod<String>(
        'availableLanguages',
        languages,
      );
      return TextRecognitionAvailability(
        languages: [
          for (final language in languages)
            if (found?.contains(language) ?? false) language,
        ],
      );
    } on MissingPluginException {
      // diagnostics: silent — no native recognizer here; the image path is hidden
      return TextRecognitionAvailability.none;
    } on PlatformException {
      // diagnostics: silent — the native query failed; the image path is hidden
      return TextRecognitionAvailability.none;
    }
  }

  @override
  Future<String> recognize(
    Uint8List bytes, {
    required List<String> languages,
  }) async {
    final String? text;
    try {
      text = await _channel.invokeMethod<String>('recognize', {
        'bytes': bytes,
        'languages': languages,
      });
    } on PlatformException catch (e, stack) {
      final reason = switch (e.code) {
        'unreadable' => TextRecognitionFailure.unreadable,
        'tooManyPixels' => TextRecognitionFailure.tooManyPixels,
        _ => TextRecognitionFailure.failed,
      };
      // A refused picture is expected and shown; only a failed engine is
      // worth the diagnostic log.
      if (reason == TextRecognitionFailure.failed) {
        logCaughtErrorTypeOnly(e, stack, source: 'text_recognition.recognize');
      }
      throw TextRecognitionException(reason);
    } on MissingPluginException catch (e, stack) {
      logCaughtErrorTypeOnly(e, stack, source: 'text_recognition.recognize');
      throw const TextRecognitionException(TextRecognitionFailure.failed);
    }
    if (text == null || text.trim().isEmpty) {
      throw const TextRecognitionException(TextRecognitionFailure.noText);
    }
    return text;
  }
}

/// The recognizer for [platform], or null where none is offered: Android
/// (no OS text recognition the app may use), Linux (none ships with it), and
/// for now Windows, whose Windows OCR recognizer is still to come.
TextRecognitionService? textRecognitionServiceFor(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) {
  if (isWeb) return null;
  return switch (platform) {
    TargetPlatform.iOS ||
    TargetPlatform.macOS => ChannelTextRecognitionService(),
    TargetPlatform.windows ||
    TargetPlatform.android ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => null,
  };
}

/// Supplies the [TextRecognitionService] and the picture picker below it;
/// tests put fakes here.
class TextRecognitionScope extends InheritedWidget {
  const TextRecognitionScope({
    super.key,
    required this.service,
    this.pickImage = pickRecognitionImage,
    required super.child,
  });

  /// Null hides **From an image…**.
  final TextRecognitionService? service;

  /// Opens the picker and reads the chosen picture.
  final Future<PickedRecognitionImage?> Function() pickImage;

  static TextRecognitionScope? _scope(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TextRecognitionScope>();

  /// The service from the nearest scope, else the platform's own.
  static TextRecognitionService? of(BuildContext context) {
    final scope = _scope(context);
    if (scope != null) return scope.service;
    return textRecognitionServiceFor(defaultTargetPlatform);
  }

  /// The picker from the nearest scope, else the system picker.
  static Future<PickedRecognitionImage?> Function() pickerOf(
    BuildContext context,
  ) => _scope(context)?.pickImage ?? pickRecognitionImage;

  @override
  bool updateShouldNotify(TextRecognitionScope oldWidget) =>
      service != oldWidget.service || pickImage != oldWidget.pickImage;
}

/// The languages to read a picture in: the UI language, then English.
List<String> recognitionLanguagesFor(Locale locale) => [
  locale.languageCode,
  if (locale.languageCode != 'en') 'en',
];

/// The size of the encoded picture [bytes], read from its header without
/// decoding it; null when it is not a picture this engine can open.
Future<ui.Size?> encodedImageSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  } on Exception {
    // diagnostics: silent — not a picture the engine opens; native decoding still decides (HEIC)
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Refuses [bytes] over the byte cap, and a picture whose header gives a size
/// over the pixel caps, before any recognition runs.
Future<void> checkRecognitionImage(
  Uint8List bytes, {
  Future<ui.Size?> Function(Uint8List bytes) sizeOf = encodedImageSize,
}) async {
  if (bytes.length > kMaxRecognitionImageBytes) {
    throw const TextRecognitionException(TextRecognitionFailure.tooLarge);
  }
  final size = await sizeOf(bytes);
  if (size == null) return;
  if (size.width > kMaxRecognitionImageSide ||
      size.height > kMaxRecognitionImageSide ||
      size.width * size.height > kMaxRecognitionImagePixels) {
    throw const TextRecognitionException(TextRecognitionFailure.tooManyPixels);
  }
}

/// The file types **From an image…** offers.
XTypeGroup recognitionImageTypeGroup() => const XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'tif', 'tiff', 'bmp'],
  uniformTypeIdentifiers: ['public.image'],
  mimeTypes: ['image/*'],
);

/// A picture the caller chose: its bytes, read once.
typedef PickedRecognitionImage = ({String name, Uint8List bytes});

/// Opens the system picker for one picture and reads it, refusing one over
/// [kMaxRecognitionImageBytes] before reading it. Null when cancelled.
///
/// On iOS the document picker copies the chosen file into a
/// `<bundle id>-Inbox` folder in this app's temporary folder; that copy is
/// deleted once read. Elsewhere the picker hands back the caller's own file,
/// which is left alone.
Future<PickedRecognitionImage?> pickRecognitionImage({
  Future<XFile?> Function()? open,
  TargetPlatform? platform,
  Directory? temporaryDirectory,
}) async {
  final file =
      await (open ??
          () => openFile(acceptedTypeGroups: [recognitionImageTypeGroup()]))();
  if (file == null) return null;
  try {
    if (await file.length() > kMaxRecognitionImageBytes) {
      throw const TextRecognitionException(TextRecognitionFailure.tooLarge);
    }
    return (name: file.name, bytes: await file.readAsBytes());
  } finally {
    if ((platform ?? defaultTargetPlatform) == TargetPlatform.iOS) {
      await deletePickerCopy(
        file.path,
        temporaryDirectory: temporaryDirectory ?? Directory.systemTemp,
      );
    }
  }
}

/// Deletes [path] when it lies in an `…-Inbox` folder directly inside
/// [temporaryDirectory] (on iOS, the app's tmp folder, where the
/// document picker's import mode puts its copies).
@visibleForTesting
Future<void> deletePickerCopy(
  String path, {
  required Directory temporaryDirectory,
}) async {
  if (path.isEmpty) return;
  final String temp;
  final String canonical;
  try {
    temp = await temporaryDirectory.resolveSymbolicLinks();
    canonical = await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    // diagnostics: silent — the file or the temporary folder is gone, so there is no copy to delete
    return;
  }
  if (!p.isWithin(temp, canonical)) return;
  final parts = p.split(p.relative(canonical, from: temp));
  if (parts.length < 2 || !parts.first.endsWith('-Inbox')) return;
  try {
    await File(canonical).delete();
  } on FileSystemException {
    // diagnostics: silent — the copy is already gone
  }
}
