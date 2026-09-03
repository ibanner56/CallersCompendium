import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/sync/sync_id.dart'
    show generateSyncIdFromRandom;
import 'package:test/test.dart';

void main() {
  group('SyncId', () {
    test('normalizes trim, NFC, and case before validation', () {
      final id = SyncId.parse('  CAF\u0045\u0301-horse-battery-staple  ');

      expect(id.value, 'café-horse-battery-staple');
      expect(id.words, ['café', 'horse', 'battery', 'staple']);
    });

    test('enforces four words and 1-32 code points per word', () {
      for (final invalid in [
        '',
        'one-two-three',
        'one-two-three-four-five',
        'a--b-c',
        'one-two-three-${'a' * 33}',
        'one two-three-four-five',
        'one-\u0000-two-four',
      ]) {
        expect(
          () => SyncId.parse(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }

      expect(SyncId.parse('${'a' * 32}-b-c-d').value, '${'a' * 32}-b-c-d');
      expect(() => SyncId.parse('${'a' * 33}-b-c-d'), throwsFormatException);
      expect(
        () => SyncId.parse('${'a' * 33}-${'b' * 32}-${'c' * 32}-${'d' * 32}'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'sync ID must not exceed 131 Unicode code points',
          ),
        ),
      );
    });

    test('generated IDs use four EFF long-list words', () {
      final id = generateSyncId();
      expect(id.words, hasLength(syncIdWordCount));
      expect(id.isBelowStrengthWarning, isFalse);
    });

    test('rejection-samples hyphenated EFF words', () {
      final id = generateSyncIdFromRandom(_FixedRandom([2008, 0, 1, 2, 3]));

      expect(id.words, ['abacus', 'abdomen', 'abdominal', 'abide']);
    });

    test('strength scoring is normalized and advisory', () {
      expect(
        estimateSyncIdStrengthBits(' CAF\u0045\u0301-horse-battery-staple '),
        estimateSyncIdStrengthBits('café-horse-battery-staple'),
      );
      expect(
        estimateSyncIdStrengthBits('a-b-c-d'),
        lessThan(syncIdStrengthWarningBits),
      );
      expect(
        estimateSyncIdStrengthBits('aaa-aaa-aaa-aaa'),
        lessThan(syncIdStrengthWarningBits),
      );
      expect(
        estimateSyncIdStrengthBits('password-password-password-password'),
        lessThan(syncIdStrengthWarningBits),
      );
      expect(SyncId.parse('a-b-c-d').isBelowStrengthWarning, isTrue);
    });
  });

  group('sync credentials', () {
    test('encodes every ID as unpadded base64url UTF-8', () {
      const id = 'CAF\u0045\u0301-horse-battery-staple';

      expect(
        encodeSyncCredential(id),
        base64Url
            .encode(utf8.encode('café-horse-battery-staple'))
            .replaceAll('=', ''),
      );
      expect(
        decodeSyncCredential(encodeSyncCredential(id)),
        'café-horse-battery-staple',
      );
    });

    test('rejects malformed credentials and malformed UTF-8', () {
      for (final credential in [
        '',
        'not valid',
        'abcde',
        '////',
        base64Url.encode([0xc3, 0x28]).replaceAll('=', ''),
      ]) {
        expect(
          () => decodeSyncCredential(credential),
          throwsFormatException,
          reason: credential,
        );
      }
    });

    test('keeps decoded invalid IDs distinct from malformed credentials', () {
      final decoded = decodeSyncCredential(
        base64Url.encode(utf8.encode('one-two-three')).replaceAll('=', ''),
      );

      expect(decoded, 'one-two-three');
      expect(() => SyncId.parse(decoded), throwsFormatException);
    });

    test('derives the same key from equivalent normalized IDs', () {
      final pepper = List<int>.filled(32, 0x42);

      expect(
        deriveSyncIdKey(' CAF\u0045\u0301-horse-battery-staple ', pepper),
        deriveSyncIdKey('café-horse-battery-staple', pepper),
      );
      expect(
        deriveSyncIdKey('café-horse-battery-staple', pepper),
        'abfdc5f379f52af1fd6a6ed102bf72e8f2b3bebb133dc30f2f08f8da38161651',
      );
    });

    test(
      'client and server adapters agree across whitespace and Unicode form',
      () {
        final pepper = List<int>.filled(32, 0x42);
        const typed = ' CAF\u0045\u0301-horse-battery-staple ';
        const normalized = 'café-horse-battery-staple';

        expect(
          deriveSyncIdKey(typed, pepper),
          deriveIncomingSyncIdKey(typed, pepper),
        );
        expect(
          deriveIncomingSyncIdKey(typed, pepper),
          deriveSyncIdKey(normalized, pepper),
        );
      },
    );

    test('ASCII IDs and their encoded spellings remain distinct IDs', () {
      const asciiId = 'cafe-horse-battery-staple';
      final encoded = encodeSyncCredential(asciiId);

      expect(encoded, isNot(asciiId));
      expect(
        deriveSyncIdKey(asciiId, List<int>.filled(32, 0x42)),
        isNot(
          Hmac(
            sha256,
            List<int>.filled(32, 0x42),
          ).convert(utf8.encode(encoded)).toString(),
        ),
      );
    });
  });
}

class _FixedRandom implements Random {
  _FixedRandom(this._values);

  final List<int> _values;
  var _index = 0;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(100) / 100;

  @override
  int nextInt(int max) => _values[_index++] % max;
}
