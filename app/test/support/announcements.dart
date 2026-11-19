import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the screen-reader announcements sent while a test runs (the
/// `message` of each `SemanticsService.sendAnnouncement`), and stops recording
/// when the test ends.
List<String> recordAnnouncements() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final messages = <String>[];
  messenger.setMockMessageHandler(SystemChannels.accessibility.name, (
    ByteData? message,
  ) async {
    final decoded = SystemChannels.accessibility.codec.decodeMessage(message);
    if (decoded is Map && decoded['type'] == 'announce') {
      final data = decoded['data'];
      if (data is Map) messages.add('${data['message']}');
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      null,
    ),
  );
  return messages;
}
