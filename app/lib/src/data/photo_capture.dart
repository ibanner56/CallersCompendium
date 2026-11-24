import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Taking a photo with the system camera (#2328), shared by every feature
/// that reads one: **Take a photo** in the figure-text sheet, and the QR
/// scanner (#2336). The photo is read once and its file deleted at once, so
/// no photo outlives the call.

/// Longest side of a captured photo, in pixels. The camera plugin redraws
/// and re-encodes the photo (JPEG) to at most this before handing it over;
/// the recognizer reads no more than this anyway.
const double kCapturedPhotoMaxSide = 4096;

/// Why a captured photo could not be handed over.
enum PhotoCaptureFailure {
  /// The photo file is larger than the caller's byte cap.
  tooLarge,

  /// The user turned camera access off for the app (or a device policy
  /// does): the camera never opened.
  accessDenied,

  /// The device has no camera app to take the photo (an Android tablet
  /// without one, say): the camera never opened.
  noCamera,
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
/// code of our own. Its photo files are found and deleted as the iOS and
/// Android plugins name and place them (see [deleteCapturedPhoto]); another
/// platform needs its own matcher before it is offered.
class SystemCameraPhotoCapture implements PhotoCaptureService {
  SystemCameraPhotoCapture({
    Future<XFile?> Function()? capture,
    this.temporaryDirectory,
    TargetPlatform? platform,
  }) : _capture = capture ?? _systemCamera,
       platform = platform ?? defaultTargetPlatform;

  final Future<XFile?> Function() _capture;

  /// Where the camera plugin writes its photos. When null: the system
  /// temporary folder on iOS, the app's cache folder on Android.
  final Directory? temporaryDirectory;

  /// Whose plugin's photo files [deleteCapturedPhoto] looks for.
  final TargetPlatform platform;

  static Future<XFile?> _systemCamera() => ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: kCapturedPhotoMaxSide,
    maxHeight: kCapturedPhotoMaxSide,
    // Full metadata means a photo-library lookup the photo is not in; it is
    // read for its pixels only.
    requestFullMetadata: false,
  );

  /// The plugins' error codes for camera access that is off.
  static const _accessDeniedCodes = {
    'camera_access_denied',
    'camera_access_restricted',
  };

  @override
  Future<Uint8List?> takePhoto({required int maxBytes}) async {
    final started = DateTime.now();
    try {
      return await _take(maxBytes);
    } finally {
      // The Android plugin makes its photo file before the camera opens and
      // leaves it on a cancel, and a photo from a capture Android cut short
      // may still be there: delete any of its files older than this capture.
      // Only one capture runs at a time, so none of them is in use.
      if (platform == TargetPlatform.android) {
        try {
          await _sweepAndroidPhotos(
            temporaryDirectory ?? await _pluginFolder(platform),
            writtenBefore: started,
          );
        } on Exception {
          // diagnostics: silent — no cache folder to sweep; the next capture or start tries again
        }
      }
    }
  }

  Future<Uint8List?> _take(int maxBytes) async {
    final XFile? file;
    try {
      file = await _capture();
    } on PlatformException catch (e) {
      if (e.code == 'no_available_camera') {
        // diagnostics: silent — the device has no camera app; shown inline
        throw const PhotoCaptureException(PhotoCaptureFailure.noCamera);
      }
      if (!_accessDeniedCodes.contains(e.code)) rethrow;
      // diagnostics: silent — the user's own choice, shown inline with how to undo it
      throw const PhotoCaptureException(PhotoCaptureFailure.accessDenied);
    }
    if (file == null) return null;
    try {
      if (await file.length() > maxBytes) {
        throw const PhotoCaptureException(PhotoCaptureFailure.tooLarge);
      }
      return await file.readAsBytes();
    } finally {
      await deleteCapturedPhoto(
        file.path,
        temporaryDirectory: temporaryDirectory ?? await _pluginFolder(platform),
        platform: platform,
      );
    }
  }
}

/// The folder the camera plugin writes its photos to on [platform]: the
/// app's tmp folder on iOS, its cache folder on Android.
Future<Directory> _pluginFolder(TargetPlatform platform) async =>
    platform == TargetPlatform.android
    ? await getTemporaryDirectory()
    : Directory.systemTemp;

/// The Android plugin's photo names: a random UUID with digits after it
/// (from Java's createTempFile), and `scaled_` before it once resized.
final _androidPhotoName = RegExp(
  r'^(scaled_)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
  r'[0-9]*\.jpg$',
);

/// Whether [name] is one of [platform]'s camera plugin's photo files.
bool _isPluginPhotoName(String name, TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? _androidPhotoName.hasMatch(name)
    : name.startsWith('image_picker_');

/// Deletes [path] when it is one of the camera plugin's own photo files,
/// directly in [temporaryDirectory] (the folder the plugin writes to), links
/// resolved on both sides. On iOS that is an `image_picker_…` file in the
/// app's tmp folder; on Android ([platform]) a `<uuid><digits>.jpg` or
/// `scaled_…` file in its cache folder. Any other path is left alone.
@visibleForTesting
Future<void> deleteCapturedPhoto(
  String path, {
  required Directory temporaryDirectory,
  TargetPlatform platform = TargetPlatform.iOS,
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
  if (!_isPluginPhotoName(p.basename(canonical), platform)) return;
  try {
    await File(canonical).delete();
  } on FileSystemException {
    // diagnostics: silent — the photo is already gone
  }
}

/// Deletes the Android camera plugin's photo files directly in [cache] that
/// were last written before [writtenBefore]. Anything that fails is left for
/// the next sweep.
Future<void> _sweepAndroidPhotos(
  Directory cache, {
  required DateTime writtenBefore,
}) async {
  try {
    await for (final entry in cache.list(followLinks: false)) {
      if (entry is File &&
          _isPluginPhotoName(p.basename(entry.path), TargetPlatform.android) &&
          (await entry.lastModified()).isBefore(writtenBefore)) {
        await deleteCapturedPhoto(
          entry.path,
          temporaryDirectory: cache,
          platform: TargetPlatform.android,
        );
      }
    }
  } on FileSystemException {
    // diagnostics: silent — the cache folder could not be listed; the next sweep tries again
  }
}

/// Deletes photos the Android camera plugin left behind: one Android took
/// while it closed the app to free memory (handed back by
/// `retrieveLostData`, and never read), and any other photo file of the
/// plugin's in the cache folder, as a photo is deleted the moment it is
/// read. Run once at start on Android. A file written after the sweep began
/// is left alone, so a photo being taken right then is not deleted before it
/// is read; it, and anything that fails, is left for the next capture's
/// sweep or the next start.
Future<void> deleteLeftoverCapturedPhotos({
  Future<LostDataResponse> Function()? retrieveLostData,
  Future<Directory> Function()? cacheDirectory,
}) async {
  final started = DateTime.now();
  try {
    // Claims the lost photo, so the plugin does not hand it back again.
    await (retrieveLostData ?? ImagePicker().retrieveLostData)();
  } on Exception {
    // diagnostics: silent — no lost photo to claim; the sweep below still runs
  }
  final Directory cache;
  try {
    cache = await (cacheDirectory ?? getTemporaryDirectory)();
  } on Exception {
    // diagnostics: silent — no cache folder, so no photo in it
    return;
  }
  await _sweepAndroidPhotos(cache, writtenBefore: started);
}

/// The camera for [platform], or null where the app takes no photos: iOS and
/// Android. On Android only **Scan a dance code** (#2336) uses it, as there is
/// no text recognition to feed (#2327); desktop webcams are poor at reading
/// cards and codes.
PhotoCaptureService? photoCaptureServiceFor(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) {
  if (isWeb) return null;
  return switch (platform) {
    TargetPlatform.iOS ||
    TargetPlatform.android => SystemCameraPhotoCapture(platform: platform),
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
