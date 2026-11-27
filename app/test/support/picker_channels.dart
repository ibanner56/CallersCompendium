import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the method channels of the two system pickers a picture can come
/// from, and records which one was opened: `image_picker`'s (the photo
/// picker) and `file_selector`'s (the open-file dialog). A host test
/// registers neither plugin's platform implementation, so these default
/// channels are what the real, uninjected picker calls reach.
///
/// Both channels hand back [path] (null: the picker was cancelled).
class PickerChannels {
  PickerChannels._();

  static const _photos = MethodChannel('plugins.flutter.io/image_picker');
  static const _files = MethodChannel('plugins.flutter.io/file_selector');

  /// The arguments of each `pickImage` call to the photo picker.
  final photoPicks = <Map<Object?, Object?>>[];

  /// The method of each call to the file selector.
  final fileCalls = <String>[];

  /// What either picker hands back.
  String? path;

  /// Installs the answers for the rest of the test.
  static PickerChannels install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final channels = PickerChannels._();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_photos, (call) async {
      if (call.method != 'pickImage') {
        fail('unexpected photo picker call ${call.method}');
      }
      channels.photoPicks.add(call.arguments as Map<Object?, Object?>);
      return channels.path;
    });
    messenger.setMockMethodCallHandler(_files, (call) async {
      channels.fileCalls.add(call.method);
      return channels.path == null ? null : [channels.path];
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_photos, null);
      messenger.setMockMethodCallHandler(_files, null);
    });
    return channels;
  }
}
