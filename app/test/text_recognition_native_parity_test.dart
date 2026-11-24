import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Apple Vision recognizer (#2327) is one Swift file kept in both Xcode
/// projects; the two copies must not drift.
void main() {
  test('the iOS and macOS TextRecognizer.swift copies are identical', () {
    final ios = File('ios/Runner/TextRecognizer.swift');
    final macos = File('macos/Runner/TextRecognizer.swift');
    expect(ios.existsSync(), isTrue);
    expect(macos.readAsStringSync(), ios.readAsStringSync());
  });
}
