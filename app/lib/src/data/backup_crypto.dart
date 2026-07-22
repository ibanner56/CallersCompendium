import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show fillBytesWithSecureRandom;
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Optional passphrase-encrypted backup container (issue #461).
///
/// Wraps the *plaintext* backup JSON produced by `encodeBackup` in a versioned,
/// authenticated encrypted container so a user can export a backup that is
/// useless without their passphrase. The plain (unencrypted) JSON export stays
/// the default and is unaffected; this module is a pure **String → String**
/// transform (plaintext JSON ⇄ armored ciphertext text) that slots into the
/// existing save/restore seams without disturbing them.
///
/// Whole-database / at-rest (sqlcipher) encryption is explicitly OUT OF SCOPE —
/// nothing here touches `openAppDatabase()`.
///
/// ## Container format (`CCEB`, version 1)
/// A binary container, then ASCII-armored (base64, PEM-style) so it is
/// text-safe: it travels through the String-based [BackupSaver]/[BackupPicker]
/// seams and the restore dialog's paste field unchanged, and an older app fed
/// the armored text simply fails closed (non-JSON → a clean, non-destructive
/// "not a valid backup" refusal).
///
/// ```
/// Binary header H (every byte below is authenticated as the AEAD AAD):
///   off  size  field
///   0    4     magic = ASCII "CCEB"
///   4    1     containerVersion (= 1)
///   5    1     kdfId    (1 = argon2id, 2 = pbkdf2-hmac-sha256)
///   6    1     cipherId (1 = xchacha20-poly1305, 2 = aes-256-gcm)
///   7    4     kdfParam1 (uint32 BE): argon2 memoryKiB | pbkdf2 iterations
///   11   4     kdfParam2 (uint32 BE): argon2 iterations (passes) | 0
///   15   1     kdfParam3 (uint8):     argon2 parallelism         | 0
///   16   1     saltLen (= 16)
///   17   16    salt (fresh random per export)
///   33   1     nonceLen (24 xchacha20 | 12 aes-gcm)
///   34   N     nonce (fresh random per export)
/// Body: AEAD-sealed bytes = ciphertext || 16-byte tag, over UTF-8(plaintext
///       JSON), with aad = H.
/// ```
///
/// The header is the AEAD's Additional Authenticated Data, so flipping any
/// header byte (a KDF param, salt, nonce, version…) OR any ciphertext/tag byte
/// makes authenticated decryption fail — tamper-evidence is constant-time and
/// handled by the AEAD, never a hand-rolled tag compare.

// ---------------------------------------------------------------------------
// Format constants
// ---------------------------------------------------------------------------

/// ASCII "CCEB" — Caller's Compendium Encrypted Backup — the container's
/// integrity magic (checked after de-armoring).
const List<int> _magic = <int>[0x43, 0x43, 0x45, 0x42];

/// Current container format version.
const int kEncryptedBackupVersion = 1;

/// KDF identifiers stored in the header.
const int kKdfArgon2id = 1;
const int kKdfPbkdf2Sha256 = 2;

/// AEAD cipher identifiers stored in the header.
const int kCipherXChaCha20Poly1305 = 1;
const int kCipherAesGcm = 2;

/// Fixed sizes (bytes).
const int _saltLength = 16;
const int _keyLength = 32; // 256-bit key for both ciphers.
const int _macLength = 16; // Poly1305 / GCM tag.
const int _xchachaNonceLength = 24;
const int _aesGcmNonceLength = 12;

// Header field offsets.
const int _offVersion = 4;
const int _offKdfId = 5;
const int _offCipherId = 6;
const int _offKdfParam1 = 7;
const int _offKdfParam2 = 11;
const int _offKdfParam3 = 15;
const int _offSaltLen = 16;
const int _offSalt = 17;
// Followed by: nonceLen (1) at _offSalt + _saltLength, then the nonce.

/// Default Argon2id parameters (OWASP baseline, tuned so the pure-Dart KDF stays
/// tolerable on mobile): 19 MiB memory, 2 passes, 1 lane, 256-bit output.
const int kDefaultArgon2MemoryKiB = 19456; // 19 MiB
const int kDefaultArgon2Iterations = 2;
const int kDefaultArgon2Parallelism = 1;

/// Default PBKDF2-HMAC-SHA256 iteration count (OWASP 2023) for the fallback KDF.
const int kDefaultPbkdf2Iterations = 600000;

/// Hard bounds enforced when *reading* a container, so a hostile/tampered header
/// cannot request a pathological KDF cost (e.g. multi-GiB Argon2 memory) and
/// exhaust memory before authentication even runs (OWASP A04/A05: fail closed on
/// untrusted input).
const int _minArgon2MemoryKiB = 8;
const int _maxArgon2MemoryKiB = 262144; // 256 MiB
const int _minArgon2Iterations = 1;
const int _maxArgon2Iterations = 16;
const int _minArgon2Parallelism = 1;
const int _maxArgon2Parallelism = 4;
const int _minPbkdf2Iterations = 1;
const int _maxPbkdf2Iterations = 10000000;

/// Ceiling on the armored container we will accept for decryption, mirroring the
/// restore read cap. Bounds allocation from a hostile/oversized paste before any
/// base64 decode (the file path is already capped by `readBackupFile`).
const int kMaxEncryptedBackupBytes = 50 * 1024 * 1024;

/// PEM-style armor markers. The BEGIN marker doubles as the import-time
/// detection signal ([isEncryptedBackup]) and makes the file human-recognizable
/// (and obviously not JSON, so older apps refuse it cleanly).
const String _armorBegin =
    '-----BEGIN CALLERS COMPENDIUM ENCRYPTED BACKUP-----';
const String _armorEnd = '-----END CALLERS COMPENDIUM ENCRYPTED BACKUP-----';
const int _armorLineWidth = 64;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Raised when an encrypted backup cannot be decrypted — a wrong or empty
/// passphrase, a tampered/corrupt container, or a malformed/unsupported/oversized
/// header. Carries only a friendly, user-facing [message]; it never embeds key
/// material, the passphrase, or recovered plaintext, so surfacing it (or logging
/// it) can't leak secrets.
class BackupDecryptException implements Exception {
  const BackupDecryptException([this.message = _defaultMessage]);

  static const String _defaultMessage =
      "Couldn't decrypt this backup — the passphrase may be wrong or the file "
      'may be corrupted. Your data is unchanged.';

  /// Safe to show to the user as-is.
  final String message;

  @override
  String toString() => 'BackupDecryptException: $message';
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// Whether [text] is (claims to be) an encrypted backup container, detected by
/// the leading armor marker. Cheap and allocation-free; the real integrity magic
/// and header are validated later by [decryptBackup].
bool isEncryptedBackup(String text) => text.trimLeft().startsWith(_armorBegin);

// ---------------------------------------------------------------------------
// Off-thread seams
// ---------------------------------------------------------------------------

/// Signature of the export-time encrypt step. Overridable so widget tests can
/// inject a cheap in-line implementation instead of the isolate-backed default.
typedef BackupEncryptor =
    Future<String> Function(String plaintextJson, String passphrase);

/// Signature of the import-time decrypt step. See [BackupEncryptor].
typedef BackupDecryptor =
    Future<String> Function(String armored, String passphrase);

/// Production [BackupEncryptor]: runs [encryptBackup] in a background isolate so
/// the memory-hard Argon2id KDF never blocks the UI thread (a backup is a
/// one-off action, not a hotpath).
Future<String> encryptBackupOffThread(
  String plaintextJson,
  String passphrase,
) => Isolate.run(() => encryptBackup(plaintextJson, passphrase));

/// Production [BackupDecryptor]: runs [decryptBackup] in a background isolate.
/// A thrown [BackupDecryptException] carries only a String, so it propagates
/// back across the isolate boundary intact.
Future<String> decryptBackupOffThread(String armored, String passphrase) =>
    Isolate.run(() => decryptBackup(armored, passphrase));

// ---------------------------------------------------------------------------
// Encrypt
// ---------------------------------------------------------------------------

/// Encrypts [plaintextJson] under [passphrase] into an armored encrypted-backup
/// container.
///
/// Uses Argon2id + XChaCha20-Poly1305 by default. A fresh random salt and nonce
/// are generated for every call, so encrypting the same input twice yields
/// different output. The KDF cost is overridable so tests can run cheaply;
/// production callers should keep the defaults.
///
/// [random] is a test seam for deterministic salt/nonce; production uses a
/// cryptographically secure source.
Future<String> encryptBackup(
  String plaintextJson,
  String passphrase, {
  int kdfId = kKdfArgon2id,
  int cipherId = kCipherXChaCha20Poly1305,
  int argon2MemoryKiB = kDefaultArgon2MemoryKiB,
  int argon2Iterations = kDefaultArgon2Iterations,
  int argon2Parallelism = kDefaultArgon2Parallelism,
  int pbkdf2Iterations = kDefaultPbkdf2Iterations,
  @visibleForTesting Random? random,
}) async {
  if (passphrase.isEmpty) {
    throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
  }

  final nonceLength = _nonceLengthFor(cipherId);
  final salt = _randomBytes(_saltLength, random);
  final nonce = _randomBytes(nonceLength, random);

  final int p1, p2, p3;
  switch (kdfId) {
    case kKdfArgon2id:
      p1 = argon2MemoryKiB;
      p2 = argon2Iterations;
      p3 = argon2Parallelism;
    case kKdfPbkdf2Sha256:
      p1 = pbkdf2Iterations;
      p2 = 0;
      p3 = 0;
    default:
      throw ArgumentError.value(kdfId, 'kdfId', 'unsupported KDF');
  }

  final header = _buildHeader(
    kdfId: kdfId,
    cipherId: cipherId,
    kdfParam1: p1,
    kdfParam2: p2,
    kdfParam3: p3,
    salt: salt,
    nonce: nonce,
  );

  final key = await _deriveKey(
    passphrase: passphrase,
    salt: salt,
    kdfId: kdfId,
    kdfParam1: p1,
    kdfParam2: p2,
    kdfParam3: p3,
  );

  final cipher = _cipherFor(cipherId);
  final secretBox = await cipher.encrypt(
    utf8.encode(plaintextJson),
    secretKey: key,
    nonce: nonce,
    aad: header,
  );

  final container = BytesBuilder(copy: false)
    ..add(header)
    ..add(secretBox.cipherText)
    ..add(secretBox.mac.bytes);

  return _armor(container.takeBytes());
}

// ---------------------------------------------------------------------------
// Decrypt
// ---------------------------------------------------------------------------

/// Decrypts an armored container produced by [encryptBackup] and returns the
/// recovered plaintext backup JSON.
///
/// Treats [armored] as fully untrusted: the header is validated (magic, version,
/// known KDF/cipher ids, exact salt/nonce lengths, KDF params within safe
/// bounds) *before* any key derivation, the input size is capped, and any
/// failure — malformed, oversized, tampered, unsupported, or a wrong/empty
/// passphrase — throws [BackupDecryptException] with a non-leaky message. It
/// fails **closed**: it never returns partial output.
Future<String> decryptBackup(String armored, String passphrase) async {
  if (passphrase.isEmpty) throw const BackupDecryptException();
  if (armored.length > kMaxEncryptedBackupBytes) {
    throw const BackupDecryptException();
  }

  final container = _dearmor(armored);

  // Minimum viable container: full header up to (and including) the nonce, plus
  // at least a MAC. saltLen is fixed at 16, so the smallest header ends after
  // the shortest supported nonce (AES-GCM, 12).
  final minHeader = _offSalt + _saltLength + 1 + _aesGcmNonceLength;
  if (container.length < minHeader + _macLength) {
    throw const BackupDecryptException();
  }

  for (var i = 0; i < _magic.length; i++) {
    if (container[i] != _magic[i]) throw const BackupDecryptException();
  }
  if (container[_offVersion] != kEncryptedBackupVersion) {
    throw const BackupDecryptException();
  }

  final kdfId = container[_offKdfId];
  final cipherId = container[_offCipherId];
  final bytes = ByteData.sublistView(container);
  final p1 = bytes.getUint32(_offKdfParam1);
  final p2 = bytes.getUint32(_offKdfParam2);
  final p3 = container[_offKdfParam3];

  _validateKdfParams(kdfId, p1, p2, p3);

  if (container[_offSaltLen] != _saltLength) {
    throw const BackupDecryptException();
  }
  final salt = container.sublist(_offSalt, _offSalt + _saltLength);

  final offNonceLen = _offSalt + _saltLength;
  final nonceLen = container[offNonceLen];
  if (nonceLen != _expectedNonceLengthFor(cipherId)) {
    throw const BackupDecryptException();
  }
  final offNonce = offNonceLen + 1;
  final offBody = offNonce + nonceLen;
  if (container.length < offBody + _macLength) {
    throw const BackupDecryptException();
  }
  final nonce = container.sublist(offNonce, offBody);
  final header = container.sublist(0, offBody);

  final cipherText = container.sublist(offBody, container.length - _macLength);
  final mac = container.sublist(container.length - _macLength);

  final SecretKey key;
  try {
    key = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      kdfId: kdfId,
      kdfParam1: p1,
      kdfParam2: p2,
      kdfParam3: p3,
    );
  } on Object {
    // Never surface KDF internals; treat any derivation failure as undecryptable.
    throw const BackupDecryptException();
  }

  final cipher = _cipherFor(cipherId);
  final List<int> clear;
  try {
    clear = await cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
      aad: header,
    );
  } on SecretBoxAuthenticationError {
    // Wrong passphrase or a tampered container — the AEAD tag didn't verify.
    throw const BackupDecryptException();
  } on Object {
    throw const BackupDecryptException();
  }

  try {
    return utf8.decode(clear);
  } on FormatException {
    // Authenticated bytes should be valid UTF-8; if not, fail closed rather than
    // return replacement characters.
    throw const BackupDecryptException();
  }
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

int _nonceLengthFor(int cipherId) {
  switch (cipherId) {
    case kCipherXChaCha20Poly1305:
      return _xchachaNonceLength;
    case kCipherAesGcm:
      return _aesGcmNonceLength;
    default:
      throw ArgumentError.value(cipherId, 'cipherId', 'unsupported cipher');
  }
}

/// Like [_nonceLengthFor] but for the untrusted read path: an unknown cipher id
/// is a decrypt failure, not a programming error.
int _expectedNonceLengthFor(int cipherId) {
  switch (cipherId) {
    case kCipherXChaCha20Poly1305:
      return _xchachaNonceLength;
    case kCipherAesGcm:
      return _aesGcmNonceLength;
    default:
      throw const BackupDecryptException();
  }
}

Cipher _cipherFor(int cipherId) {
  switch (cipherId) {
    case kCipherXChaCha20Poly1305:
      return Xchacha20.poly1305Aead();
    case kCipherAesGcm:
      return AesGcm.with256bits(nonceLength: _aesGcmNonceLength);
    default:
      throw const BackupDecryptException();
  }
}

void _validateKdfParams(int kdfId, int p1, int p2, int p3) {
  switch (kdfId) {
    case kKdfArgon2id:
      if (p1 < _minArgon2MemoryKiB ||
          p1 > _maxArgon2MemoryKiB ||
          p2 < _minArgon2Iterations ||
          p2 > _maxArgon2Iterations ||
          p3 < _minArgon2Parallelism ||
          p3 > _maxArgon2Parallelism) {
        throw const BackupDecryptException();
      }
    case kKdfPbkdf2Sha256:
      if (p1 < _minPbkdf2Iterations || p1 > _maxPbkdf2Iterations) {
        throw const BackupDecryptException();
      }
    default:
      throw const BackupDecryptException();
  }
}

Future<SecretKey> _deriveKey({
  required String passphrase,
  required List<int> salt,
  required int kdfId,
  required int kdfParam1,
  required int kdfParam2,
  required int kdfParam3,
}) {
  final secret = SecretKey(utf8.encode(passphrase));
  switch (kdfId) {
    case kKdfArgon2id:
      return Argon2id(
        memory: kdfParam1,
        iterations: kdfParam2,
        parallelism: kdfParam3,
        hashLength: _keyLength,
      ).deriveKey(secretKey: secret, nonce: salt);
    case kKdfPbkdf2Sha256:
      return Pbkdf2.hmacSha256(
        iterations: kdfParam1,
        bits: _keyLength * 8,
      ).deriveKey(secretKey: secret, nonce: salt);
    default:
      throw const BackupDecryptException();
  }
}

Uint8List _buildHeader({
  required int kdfId,
  required int cipherId,
  required int kdfParam1,
  required int kdfParam2,
  required int kdfParam3,
  required List<int> salt,
  required List<int> nonce,
}) {
  final header = BytesBuilder(copy: false);
  header.add(_magic);
  header.addByte(kEncryptedBackupVersion);
  header.addByte(kdfId);
  header.addByte(cipherId);
  final params = ByteData(9)
    ..setUint32(0, kdfParam1)
    ..setUint32(4, kdfParam2)
    ..setUint8(8, kdfParam3);
  header.add(params.buffer.asUint8List());
  header.addByte(salt.length);
  header.add(salt);
  header.addByte(nonce.length);
  header.add(nonce);
  return header.takeBytes();
}

Uint8List _randomBytes(int length, Random? random) {
  final bytes = Uint8List(length);
  fillBytesWithSecureRandom(bytes, random: random);
  return bytes;
}

String _armor(Uint8List container) {
  final b64 = base64.encode(container);
  final buffer = StringBuffer()..writeln(_armorBegin);
  for (var i = 0; i < b64.length; i += _armorLineWidth) {
    final end = (i + _armorLineWidth < b64.length)
        ? i + _armorLineWidth
        : b64.length;
    buffer.writeln(b64.substring(i, end));
  }
  buffer.writeln(_armorEnd);
  return buffer.toString();
}

Uint8List _dearmor(String armored) {
  final trimmed = armored.trim();
  final beginIdx = trimmed.indexOf(_armorBegin);
  final endIdx = trimmed.indexOf(_armorEnd);
  if (beginIdx < 0 || endIdx < 0 || endIdx <= beginIdx) {
    throw const BackupDecryptException();
  }
  final body = trimmed.substring(beginIdx + _armorBegin.length, endIdx);
  // Strip all whitespace (line wrapping) to recover the base64 payload.
  final b64 = body.replaceAll(RegExp(r'\s'), '');
  if (b64.isEmpty || b64.length > kMaxEncryptedBackupBytes) {
    throw const BackupDecryptException();
  }
  try {
    return base64.decode(b64);
  } on FormatException {
    throw const BackupDecryptException();
  }
}
