/// Reading a dance code (#2334) from a picture, for **Scan a dance code** in
/// Import (#2336). The picture comes from the shared camera service
/// (`photo_capture.dart`); this only finds the QR code in its pixels and
/// returns the text the code holds. That text is untrusted: the caller hands
/// it to the same link path a pasted or opened dance link takes
/// (`dance_link_intake.dart`), which caps and validates it.
///
/// Decoding is pure Dart (`zxing2`) on the device. No model is fetched, and
/// nothing about the picture is kept.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zxing2/qrcode.dart';

import 'photo_capture.dart';
import 'text_recognition.dart' show openRecognitionPicture;

/// Longest side, in pixels, a picture is decoded at before looking for a
/// code; larger ones are scaled down to it. A dance code filling a fifth of
/// a photo's width still has several pixels per module at this size.
const int kDanceCodeScanSide = 2048;

/// Largest picture looked at, in pixels on its longer side and in all; the
/// same caps as reading a picture's text.
const int kDanceCodeScanMaxSide = 10000;
const int kDanceCodeScanMaxPixels = 50 * 1000 * 1000;

/// Largest photo file searched for a code, in bytes; the same cap as a
/// picture whose text is read.
const int kDanceCodePhotoMaxBytes = 25 * 1024 * 1024;

/// Why no code text came out of a picture.
enum DanceCodeScanFailure {
  /// The bytes are not a picture this device can open, or it is too large.
  unreadablePicture,

  /// No QR code was found in the picture.
  noCode,

  /// A QR code was found but its contents could not be read: it is damaged,
  /// cut off or out of focus.
  damagedCode,
}

/// A picture that gave no code text, and why.
class DanceCodeScanException implements Exception {
  const DanceCodeScanException(this.failure);

  final DanceCodeScanFailure failure;

  @override
  String toString() => 'DanceCodeScanException($failure)';
}

/// Finds a QR code in an encoded picture and returns the text it holds.
abstract interface class DanceCodeDecoder {
  /// The text of the QR code in [encodedPicture] (PNG, JPEG, …). Throws
  /// [DanceCodeScanException] when there is none to return.
  Future<String> decode(Uint8List encodedPicture);
}

/// Pixels of a picture, one `0xAARRGGBB` value each, row by row.
@immutable
class ScanPixels {
  const ScanPixels(this.width, this.height, this.argb);

  final int width;
  final int height;
  final Int32List argb;
}

/// The `zxing2` QR reader, over pixels decoded by the engine's own image
/// codecs. The search runs off the UI thread.
class Zxing2DanceCodeDecoder implements DanceCodeDecoder {
  Zxing2DanceCodeDecoder({Future<String> Function(ScanPixels pixels)? search})
    : _search = search ?? _searchOffThread;

  final Future<String> Function(ScanPixels pixels) _search;

  static Future<String> _searchOffThread(ScanPixels pixels) =>
      compute(readQrCode, pixels);

  @override
  Future<String> decode(Uint8List encodedPicture) async {
    final pixels = await decodePixels(encodedPicture);
    return _search(pixels);
  }
}

/// Whether a [width] x [height] picture is over [kDanceCodeScanMaxSide] or
/// [kDanceCodeScanMaxPixels], and so is not looked at.
@visibleForTesting
bool overScanCaps(int width, int height) =>
    width > kDanceCodeScanMaxSide ||
    height > kDanceCodeScanMaxSide ||
    width * height > kDanceCodeScanMaxPixels;

/// Decodes [encodedPicture] to pixels no larger than [kDanceCodeScanSide] on
/// the longer side. Throws [DanceCodeScanException] with
/// [DanceCodeScanFailure.unreadablePicture] for bytes that are not a picture,
/// or a picture over the caps.
@visibleForTesting
Future<ScanPixels> decodePixels(Uint8List encodedPicture) async {
  if (encodedPicture.isEmpty) {
    throw const DanceCodeScanException(DanceCodeScanFailure.unreadablePicture);
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(encodedPicture);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0 || overScanCaps(width, height)) {
      throw const DanceCodeScanException(
        DanceCodeScanFailure.unreadablePicture,
      );
    }
    // Scaled down by a whole factor: a fractional one leaves the modules of a
    // sharp code unevenly wide, which the reader can misread.
    final longer = width > height ? width : height;
    final factor = (longer + kDanceCodeScanSide - 1) ~/ kDanceCodeScanSide;
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, width ~/ factor),
      targetHeight: math.max(1, height ~/ factor),
    );
    image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      throw const DanceCodeScanException(
        DanceCodeScanFailure.unreadablePicture,
      );
    }
    final bytes = rgba.buffer.asUint8List(
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    final argb = Int32List(image.width * image.height);
    for (var i = 0, j = 0; i < argb.length; i++, j += 4) {
      argb[i] =
          (bytes[j + 3] << 24) |
          (bytes[j] << 16) |
          (bytes[j + 1] << 8) |
          bytes[j + 2];
    }
    return ScanPixels(image.width, image.height, argb);
  } on DanceCodeScanException {
    // diagnostics: silent — re-thrown unchanged; the caller reports it
    rethrow;
  } on Exception {
    // diagnostics: silent — bytes the engine cannot decode; the user is told the picture can't be opened
    throw const DanceCodeScanException(DanceCodeScanFailure.unreadablePicture);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// The text of the QR code in [pixels]. Throws [DanceCodeScanException]:
/// [DanceCodeScanFailure.noCode] when none is found,
/// [DanceCodeScanFailure.damagedCode] when one is found but cannot be read.
/// A top-level function so it can run in another isolate.
@visibleForTesting
String readQrCode(ScanPixels pixels) {
  final source = RGBLuminanceSource(pixels.width, pixels.height, pixels.argb);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  var damaged = false;
  // A code printed light on dark reads only once the picture is inverted.
  for (final luminance in <LuminanceSource>[source, source.invert()]) {
    try {
      return QRCodeReader()
          .decode(BinaryBitmap(HybridBinarizer(luminance)), hints: hints)
          .text;
    } on NotFoundException {
      // diagnostics: silent — no code in this rendering; the next one is tried
    } on ChecksumException {
      // diagnostics: silent — a code too damaged to read; reported below
      damaged = true;
    } on FormatReaderException {
      // diagnostics: silent — a code too damaged to read; reported below
      damaged = true;
    } on ReaderException {
      // diagnostics: silent — any other reader refusal means no readable code here
    }
  }
  throw DanceCodeScanException(
    damaged ? DanceCodeScanFailure.damagedCode : DanceCodeScanFailure.noCode,
  );
}

/// Takes a photo with [camera] and returns the text of the QR code in it, or
/// null when the user cancels. The camera service deletes its photo file
/// before handing the bytes over, so no file outlives the photo whatever
/// [decoder] then finds. Throws what [camera] and [decoder] throw.
Future<String?> scanDanceCode({
  required PhotoCaptureService camera,
  required DanceCodeDecoder decoder,
}) async {
  final photo = await camera.takePhoto(maxBytes: kDanceCodePhotoMaxBytes);
  if (photo == null) return null;
  return decoder.decode(photo);
}

/// Thrown by [pickDanceCodePicture] for a chosen file over
/// [kDanceCodePhotoMaxBytes]; it is not searched. (On Android the file
/// selector, and on iOS the photo picker, has already copied it by then.)
class DanceCodePictureTooLarge implements Exception {
  const DanceCodePictureTooLarge();

  @override
  String toString() => 'DanceCodePictureTooLarge()';
}

/// Opens the system picker for one picture holding a dance code (a saved
/// photo, or a screenshot of someone's Show code screen) and reads it: on
/// iPhone and iPad the system photo picker, elsewhere the file picker
/// ([openRecognitionPicture]). Null when cancelled;
/// [DanceCodePictureTooLarge] for a file over [kDanceCodePhotoMaxBytes],
/// which is not searched.
///
/// Where the picker hands over a copy of the chosen picture, the copy is
/// deleted once read or refused: on iOS the photo picker's `image_picker_…`
/// copy ([deleteCapturedPhoto]), and on Android the file selector's copy in
/// the app's cache ([deleteAndroidPickerCopy]). Elsewhere the picker hands
/// back the user's own file, which is left alone. [temporaryDirectory] is
/// where those copies are looked for; by default the app's tmp folder on iOS
/// and its cache folder on Android.
Future<Uint8List?> pickDanceCodePicture({
  Future<XFile?> Function()? open,
  TargetPlatform? platform,
  Future<Directory> Function()? temporaryDirectory,
}) async {
  final on = platform ?? defaultTargetPlatform;
  final file = await (open ?? () => openRecognitionPicture(on))();
  if (file == null) return null;
  try {
    if (await file.length() > kDanceCodePhotoMaxBytes) {
      throw const DanceCodePictureTooLarge();
    }
    return await file.readAsBytes();
  } finally {
    switch (on) {
      case TargetPlatform.iOS:
        await deleteCapturedPhoto(
          file.path,
          // NSTemporaryDirectory: the photo picker's copies are in tmp, not
          // in the caches folder path_provider calls temporary on iOS.
          temporaryDirectory: temporaryDirectory == null
              ? Directory.systemTemp
              : await temporaryDirectory(),
        );
      case TargetPlatform.android:
        await deleteAndroidPickerCopy(
          file.path,
          cacheDirectory: await (temporaryDirectory ?? getTemporaryDirectory)(),
        );
      case TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.fuchsia:
        break;
    }
  }
}

/// The folder name the Android file selector copies a chosen file into: a
/// UUID made from the file's content URI.
final _androidCopyFolder = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Deletes [path] when it is the Android file selector's copy of a chosen
/// file: a file in a UUID-named folder directly in [cacheDirectory] (the
/// app's cache), links resolved on both sides. The folder goes too, once
/// empty. Any other path is left alone. Also used for the import pickers'
/// copies ([deletePickerCopy]).
Future<void> deleteAndroidPickerCopy(
  String path, {
  required Directory cacheDirectory,
}) async {
  if (path.isEmpty) return;
  final String cache;
  final String canonical;
  try {
    cache = await cacheDirectory.resolveSymbolicLinks();
    canonical = await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    // diagnostics: silent — the copy or the cache folder is gone, so there is nothing to delete
    return;
  }
  if (!p.isWithin(cache, canonical)) return;
  final parts = p.split(p.relative(canonical, from: cache));
  if (parts.length != 2 || !_androidCopyFolder.hasMatch(parts.first)) return;
  try {
    await File(canonical).delete();
    final folder = Directory(p.dirname(canonical));
    if (await folder.list().isEmpty) await folder.delete();
  } on FileSystemException {
    // diagnostics: silent — the copy or its folder is already gone
  }
}

/// Supplies the [DanceCodeDecoder] and the picture picker below it; tests
/// put fakes here.
class DanceCodeDecoderScope extends InheritedWidget {
  const DanceCodeDecoderScope({
    super.key,
    required this.decoder,
    this.pickPicture = pickDanceCodePicture,
    required super.child,
  });

  final DanceCodeDecoder decoder;

  /// Chooses a picture for **Dance code from a picture…**.
  final Future<Uint8List?> Function() pickPicture;

  static DanceCodeDecoderScope? _scope(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DanceCodeDecoderScope>();

  /// The decoder from the nearest scope, else the `zxing2` one.
  static DanceCodeDecoder of(BuildContext context) =>
      _scope(context)?.decoder ?? Zxing2DanceCodeDecoder();

  /// The picture picker from the nearest scope, else the system one.
  static Future<Uint8List?> Function() pickerOf(BuildContext context) =>
      _scope(context)?.pickPicture ?? pickDanceCodePicture;

  @override
  bool updateShouldNotify(DanceCodeDecoderScope oldWidget) =>
      decoder != oldWidget.decoder || pickPicture != oldWidget.pickPicture;
}
