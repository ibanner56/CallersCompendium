import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Taking a photo with the system camera (#2328), shared by every feature
/// that reads one: **Take a photo** in the figure-text sheet, and the QR
/// scanner (#2336). The photo is read once and its file deleted at once, so
/// no photo outlives the call.

/// Longest side of a captured photo, in pixels. The system camera scales the
/// photo down to this before handing it over; the recognizer reads no more
/// than this anyway.
const double kCapturedPhotoMaxSide = 4096;

/// Why a captured photo could not be handed over.
enum PhotoCaptureFailure {
  /// The photo file is larger than the caller's byte cap.
  tooLarge,
}

/// A photo that was taken but could not be handed over, and why.
class PhotoCaptureException implements Exception {
  const PhotoCaptureException(this.reason);

  final PhotoCaptureFailure reason;

  @override
  String toString() => 'PhotoCaptureException($reason)';
}

/// Takes one photo and hands back its encoded bytes.
abstract interface class PhotoCaptureService {
  /// Opens the camera and returns the photo's encoded bytes (JPEG), or null
  /// when the user cancels. A photo over [maxBytes] throws
  /// [PhotoCaptureException]. The photo's file is deleted before this
  /// returns or throws.
  Future<Uint8List?> takePhoto({required int maxBytes});
}

/// The system camera through `image_picker`: no in-app preview, so no camera
/// code of our own and, on Android, no `CAMERA` permission.
class SystemCameraPhotoCapture implements PhotoCaptureService {
  SystemCameraPhotoCapture({
    Future<XFile?> Function()? capture,
    this.temporaryDirectory,
  }) : _capture = capture ?? _systemCamera;

  final Future<XFile?> Function() _capture;

  /// Where the camera plugin writes its photos; the system temporary folder
  /// when null.
  final Directory? temporaryDirectory;

  static Future<XFile?> _systemCamera() => ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: kCapturedPhotoMaxSide,
    maxHeight: kCapturedPhotoMaxSide,
    // Full metadata would ask for photo-library access on iOS; the photo is
    // read for its pixels only.
    requestFullMetadata: false,
  );

  @override
  Future<Uint8List?> takePhoto({required int maxBytes}) async {
    final file = await _capture();
    if (file == null) return null;
    try {
      if (await file.length() > maxBytes) {
        throw const PhotoCaptureException(PhotoCaptureFailure.tooLarge);
      }
      return await file.readAsBytes();
    } finally {
      await deleteCapturedPhoto(
        file.path,
        temporaryDirectory: temporaryDirectory ?? Directory.systemTemp,
      );
    }
  }
}

/// Deletes [path] when it is one of the camera plugin's own photo files: an
/// `image_picker_…` file directly in [temporaryDirectory] (on iOS, the
/// app's tmp folder), links resolved on both sides. Any other path is left
/// alone.
@visibleForTesting
Future<void> deleteCapturedPhoto(
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
    // diagnostics: silent — the photo or the temporary folder is gone, so there is nothing to delete
    return;
  }
  if (p.dirname(canonical) != temp) return;
  if (!p.basename(canonical).startsWith('image_picker_')) return;
  try {
    await File(canonical).delete();
  } on FileSystemException {
    // diagnostics: silent — the photo is already gone
  }
}

/// The camera for [platform], or null where the app takes no photos: only
/// iOS has one for now. Android has no text recognition to feed (#2327), and
/// desktop webcams are poor at reading cards.
PhotoCaptureService? photoCaptureServiceFor(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) {
  if (isWeb) return null;
  return switch (platform) {
    TargetPlatform.iOS => SystemCameraPhotoCapture(),
    TargetPlatform.android ||
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia => null,
  };
}

/// Supplies the [PhotoCaptureService] below it; tests put fakes here.
class PhotoCaptureScope extends InheritedWidget {
  const PhotoCaptureScope({
    super.key,
    required this.service,
    required super.child,
  });

  /// Null hides every **Take a photo**.
  final PhotoCaptureService? service;

  /// The service from the nearest scope, else the platform's own.
  static PhotoCaptureService? of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PhotoCaptureScope>();
    if (scope != null) return scope.service;
    return photoCaptureServiceFor(defaultTargetPlatform);
  }

  @override
  bool updateShouldNotify(PhotoCaptureScope oldWidget) =>
      service != oldWidget.service;
}
