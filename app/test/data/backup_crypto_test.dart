import 'dart:convert';
import 'dart:math';

import 'package:compendium_app/src/data/backup_crypto.dart';
import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cheap KDF cost so the round-trip/tamper tests stay fast; the *default*
/// production params are asserted separately below.
const _fastMemKiB = 256;
const _fastIters = 1;
const _fastParallel = 1;

Future<String> _encryptFast(
  String json,
  String passphrase, {
  int kdfId = kKdfArgon2id,
  int cipherId = kCipherXChaCha20Poly1305,
  Random? random,
}) => encryptBackup(
  json,
  passphrase,
  kdfId: kdfId,
  cipherId: cipherId,
  argon2MemoryKiB: _fastMemKiB,
  argon2Iterations: _fastIters,
  argon2Parallelism: _fastParallel,
  pbkdf2Iterations: 1000,
  random: random,
);

/// A representative plaintext backup carrying identifiable PII (a choreographer
/// name + email) so the leakage assertion has something to look for.
String _sampleBackupJson() {
  final doc = BackupDocument(
    createdAt: DateTime.utc(2026, 7, 15),
    core: CompendiumArchive(
      exportedAt: DateTime.utc(2026, 7, 15),
      choreographers: [
        Choreographer(id: 'c1', name: 'Cary Ravitz', email: 'cary@example.com'),
      ],
    ),
    settings: const {'sampleSetting': 'value'},
  );
  return encodeBackup(doc);
}

void main() {
  group('isEncryptedBackup', () {
    test('true for armored output, false for plain backup JSON', () async {
      final armored = await _encryptFast('{"backupVersion":1}', 'pw');
      expect(isEncryptedBackup(armored), isTrue);
      expect(isEncryptedBackup('   \n$armored'), isTrue, reason: 'leading ws');
      expect(isEncryptedBackup('{"backupVersion":1,"core":{}}'), isFalse);
      expect(isEncryptedBackup(''), isFalse);
    });
  });

  group('round-trip', () {
    test(
      'Argon2id + XChaCha20-Poly1305 reproduces the exact plaintext',
      () async {
        const json = '{"backupVersion":1,"hello":"world \u00e9\u2603"}';
        final armored = await _encryptFast(json, 'correct horse battery');
        expect(await decryptBackup(armored, 'correct horse battery'), json);
      },
    );

    test('PBKDF2-HMAC-SHA256 KDF round-trips', () async {
      const json = '{"backupVersion":1}';
      final armored = await _encryptFast(json, 'pw', kdfId: kKdfPbkdf2Sha256);
      expect(await decryptBackup(armored, 'pw'), json);
    });

    test('AES-256-GCM cipher round-trips', () async {
      const json = '{"backupVersion":1}';
      final armored = await _encryptFast(json, 'pw', cipherId: kCipherAesGcm);
      expect(await decryptBackup(armored, 'pw'), json);
    });

    test(
      'a full BackupDocument survives encrypt -> decrypt -> decode intact',
      () async {
        final json = _sampleBackupJson();
        final armored = await _encryptFast(json, 'pw');
        final recovered = await decryptBackup(armored, 'pw');
        expect(recovered, json, reason: 'byte-identical to the plain export');

        final read = decodeBackup(recovered);
        expect(read.fatal, isFalse);
        expect(read.hasErrors, isFalse);
        expect(read.document.core.choreographers.single.name, 'Cary Ravitz');
        expect(
          read.document.core.choreographers.single.email,
          'cary@example.com',
        );
      },
    );
  });

  group('freshness', () {
    test('two exports of the same input differ (fresh salt + nonce)', () async {
      const json = '{"backupVersion":1}';
      final a = await _encryptFast(json, 'pw');
      final b = await _encryptFast(json, 'pw');
      expect(a, isNot(equals(b)));
      // …but both decrypt to the same plaintext.
      expect(await decryptBackup(a, 'pw'), json);
      expect(await decryptBackup(b, 'pw'), json);
    });
  });

  group('no plaintext leakage', () {
    test('ciphertext contains none of the plaintext PII', () async {
      final json = _sampleBackupJson();
      expect(json, contains('Cary Ravitz'));
      expect(json, contains('cary@example.com'));

      final armored = await _encryptFast(json, 'pw');
      expect(armored.contains('Cary Ravitz'), isFalse);
      expect(armored.contains('cary@example.com'), isFalse);

      // Also check the raw decoded container bytes, not just the armor text.
      final body = armored
          .split('\n')
          .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
          .join();
      final raw = utf8.decode(base64.decode(body), allowMalformed: true);
      expect(raw.contains('Cary Ravitz'), isFalse);
      expect(raw.contains('cary@example.com'), isFalse);
    });
  });

  group('wrong / empty passphrase', () {
    test('wrong passphrase -> BackupDecryptException, no output', () async {
      final armored = await _encryptFast('{"backupVersion":1}', 'right');
      await expectLater(
        decryptBackup(armored, 'wrong'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('empty passphrase on decrypt -> BackupDecryptException', () async {
      final armored = await _encryptFast('{"backupVersion":1}', 'right');
      await expectLater(
        decryptBackup(armored, ''),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test(
      'empty passphrase on encrypt is rejected (UI also guards this)',
      () async {
        await expectLater(
          encryptBackup('{}', ''),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  group('tamper detection', () {
    Future<List<String>> lines(String armored) async =>
        armored.split('\n').toList();

    test('flipping a ciphertext byte fails authentication', () async {
      final armored = await _encryptFast('{"backupVersion":1}', 'pw');
      final ls = await lines(armored);
      // The last non-empty base64 line holds ciphertext/tag bytes.
      final idx = ls.lastIndexWhere(
        (l) => l.trim().isNotEmpty && !l.startsWith('-----'),
      );
      final line = ls[idx];
      // Flip a character to a different valid base64 char.
      final ch = line[0];
      ls[idx] = (ch == 'A' ? 'B' : 'A') + line.substring(1);
      await expectLater(
        decryptBackup(ls.join('\n'), 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('flipping a header byte (AAD) fails authentication', () async {
      final armored = await _encryptFast('{"backupVersion":1}', 'pw');
      final body = armored
          .split('\n')
          .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
          .join();
      final raw = base64.decode(body);
      // Byte 5 is kdfId — part of the authenticated header. Flip it.
      raw[5] = raw[5] ^ 0xFF;
      final tampered =
          '$_sampleReconstructPrefix${base64.encode(raw)}\n$_sampleReconstructSuffix';
      await expectLater(
        decryptBackup(tampered, 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });
  });

  group('malformed / unsupported input fails closed', () {
    test('non-armored text', () async {
      await expectLater(
        decryptBackup('not an encrypted backup', 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('armored but invalid base64', () async {
      final bad =
          '$_sampleReconstructPrefix!!!not base64!!!\n'
          '$_sampleReconstructSuffix';
      await expectLater(
        decryptBackup(bad, 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('truncated container (too short for a header + MAC)', () async {
      final tiny = base64.encode([0x43, 0x43, 0x45, 0x42, 0x01]);
      final armored =
          '$_sampleReconstructPrefix$tiny\n$_sampleReconstructSuffix';
      await expectLater(
        decryptBackup(armored, 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('wrong magic marker', () async {
      // A well-formed-length but wrong-magic container.
      final bytes = List<int>.filled(200, 0);
      final armored =
          '$_sampleReconstructPrefix${base64.encode(bytes)}\n$_sampleReconstructSuffix';
      await expectLater(
        decryptBackup(armored, 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('oversized armored input rejected before decrypting', () async {
      final huge =
          '$_sampleReconstructPrefix'
          '${'A' * (kMaxEncryptedBackupBytes + 1)}\n'
          '$_sampleReconstructSuffix';
      await expectLater(
        decryptBackup(huge, 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('unsupported version', () async {
      final armored = await _encryptFast('{"backupVersion":1}', 'pw');
      final body = armored
          .split('\n')
          .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
          .join();
      final raw = base64.decode(body);
      raw[4] = 0xFE; // version byte -> unsupported
      final tampered =
          '$_sampleReconstructPrefix${base64.encode(raw)}\n$_sampleReconstructSuffix';
      await expectLater(
        decryptBackup(tampered, 'pw'),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test(
      'hostile Argon2 memory param above the safety cap is rejected',
      () async {
        final armored = await _encryptFast('{"backupVersion":1}', 'pw');
        final body = armored
            .split('\n')
            .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
            .join();
        final raw = base64.decode(body);
        // kdfParam1 (memoryKiB) is a uint32 BE at offset 7; set it to ~4 GiB.
        raw[7] = 0xFF;
        raw[8] = 0xFF;
        raw[9] = 0xFF;
        raw[10] = 0xFF;
        final tampered =
            '$_sampleReconstructPrefix${base64.encode(raw)}\n$_sampleReconstructSuffix';
        await expectLater(
          decryptBackup(tampered, 'pw'),
          throwsA(isA<BackupDecryptException>()),
        );
      },
    );
  });

  group('isolate-backed default (decryptBackupOffThread)', () {
    // These exercise the REAL isolate-backed default (Isolate.run), not the
    // in-process seam, to prove the fail-closed contract holds across the
    // isolate boundary: Isolate.run forwards errors via Isolate.exit (transfer
    // semantics), so our String-only BackupDecryptException propagates intact
    // and callers' `on BackupDecryptException` path runs.
    test('correct passphrase round-trips through the real isolate', () async {
      const json = '{"backupVersion":1,"hello":"world"}';
      final armored = await _encryptFast(json, 'open sesame');
      expect(await decryptBackupOffThread(armored, 'open sesame'), json);
    });

    test(
      'wrong passphrase surfaces as BackupDecryptException across the isolate',
      () async {
        final armored = await _encryptFast('{"backupVersion":1}', 'right');
        await expectLater(
          decryptBackupOffThread(armored, 'wrong'),
          throwsA(isA<BackupDecryptException>()),
        );
      },
    );

    test(
      'tampered/truncated container surfaces as BackupDecryptException across '
      'the isolate',
      () async {
        final tiny = base64.encode([0x43, 0x43, 0x45, 0x42, 0x01]);
        final armored =
            '$_sampleReconstructPrefix$tiny\n$_sampleReconstructSuffix';
        await expectLater(
          decryptBackupOffThread(armored, 'pw'),
          throwsA(isA<BackupDecryptException>()),
        );
      },
    );

    test(
      'valid armored + wrong passphrase (encrypted off-thread too)',
      () async {
        final armored = await encryptBackupOffThread(
          '{"backupVersion":1}',
          'pw',
        );
        expect(isEncryptedBackup(armored), isTrue);
        await expectLater(
          decryptBackupOffThread(armored, 'nope'),
          throwsA(isA<BackupDecryptException>()),
        );
      },
    );
  });

  group('production defaults', () {
    test('match the intended OWASP-baseline parameters', () {
      expect(kDefaultArgon2MemoryKiB, 19456);
      expect(kDefaultArgon2Iterations, 2);
      expect(kDefaultArgon2Parallelism, 1);
      expect(kDefaultPbkdf2Iterations, 600000);
    });
  });
}

// Armor markers reproduced for tests that reconstruct a container by hand.
const _sampleReconstructPrefix =
    '-----BEGIN CALLERS COMPENDIUM ENCRYPTED BACKUP-----\n';
const _sampleReconstructSuffix =
    '-----END CALLERS COMPENDIUM ENCRYPTED BACKUP-----\n';
