import 'dart:io';

import 'package:compendium_app/src/data/archive_intake_service.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native layers enforce the incoming-size limits while staging (so an
/// oversize payload is never fully copied or read), but they cannot import Dart
/// constants. These tests pin each native literal to its Dart source of truth so
/// the limits cannot drift apart silently.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// The integer literal assigned to [name] in [source], underscores removed.
  int literal(String source, String name) {
    final match = RegExp(
      '$name\\s*(?::\\s*\\w+)?\\s*=\\s*([0-9_]+)',
    ).firstMatch(source);
    expect(match, isNotNull, reason: '$name literal not found');
    return int.parse(match!.group(1)!.replaceAll('_', ''));
  }

  group('incoming archive byte cap', () {
    test('Android IncomingFileStager matches kMaxIncomingArchiveBytes', () {
      final source = read(
        'android/app/src/main/kotlin/org/callerscompendium/compendiumApp/'
        'IncomingFileStager.kt',
      );
      expect(literal(source, 'MAX_INCOMING_BYTES'), kMaxIncomingArchiveBytes);
    });

    test('iOS IncomingFileStager matches kMaxIncomingArchiveBytes', () {
      final source = read('ios/Runner/IncomingFilesPlugin.swift');
      expect(literal(source, 'static let maxBytes'), kMaxIncomingArchiveBytes);
    });

    test('macOS IncomingFileStager matches kMaxIncomingArchiveBytes', () {
      final source = read('macos/Runner/IncomingFilesBridge.swift');
      expect(literal(source, 'static let maxBytes'), kMaxIncomingArchiveBytes);
    });
  });

  group('shared text byte cap', () {
    // A character is at most 4 UTF-8 bytes, so this bound can never reject text
    // Dart's character check would accept.
    const expected = kMaxSharedImportTextLength * 4;

    test('iOS host queue matches 4 x kMaxSharedImportTextLength', () {
      final source = read('ios/Runner/IncomingFilesPlugin.swift');
      expect(literal(source, 'static let maxPayloadBytes'), expected);
    });

    test('iOS Share Extension matches the host queue', () {
      final source = read('ios/ShareExtension/ShareViewController.swift');
      expect(literal(source, 'static let maxPayloadBytes'), expected);
    });
  });

  test('every Share Extension locale defines the too-long strings', () {
    for (final locale in ['da', 'de', 'en', 'fr', 'ja', 'nl']) {
      final strings = read(
        'ios/ShareExtension/$locale.lproj/Localizable.strings',
      );
      expect(
        strings,
        contains('"share_extension.title.too_long"'),
        reason: locale,
      );
      expect(
        strings,
        contains('"share_extension.message.too_long"'),
        reason: locale,
      );
    }
  });
}
