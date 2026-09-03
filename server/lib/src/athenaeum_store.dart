import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'athenaeum_config.dart';

const int maxBlobBytes = 1024 * 1024;
const int maxManifestBytes = 16 * 1024 * 1024;
const int maxMissingHashes = 10000;
const int maxJsonDepth = 32;
const int maxGzipBytes = 32 * 1024 * 1024;
const int maxStoreCreationsPerMinute = 60;
const int maxFailedResolutionsPerIp = 10;
const int maxFailedResolutionsPerIpBurst = 20;
const int maxFailedResolutionsServerWide = 1000;

final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');

class AthenaeumStore {
  AthenaeumStore({required AthenaeumConfig config, sqlite3.Database? database})
    : config = config,
      _database = database ?? _openDatabase(config.dataDirectory) {
    Directory(config.dataDirectory).createSync(recursive: true);
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS stores (
        id_key TEXT PRIMARY KEY,
        epoch TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        bytes_used INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS manifests (
        id_key TEXT NOT NULL,
        epoch TEXT NOT NULL,
        device_id TEXT NOT NULL,
        etag TEXT NOT NULL,
        written_at INTEGER NOT NULL,
        body BLOB NOT NULL,
        PRIMARY KEY (id_key, epoch, device_id)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS blob_refs (
        id_key TEXT NOT NULL,
        epoch TEXT NOT NULL,
        hash TEXT NOT NULL,
        size INTEGER NOT NULL,
        uploaded_at INTEGER NOT NULL,
        PRIMARY KEY (id_key, epoch, hash)
      )
    ''');
  }

  final AthenaeumConfig config;
  final sqlite3.Database _database;

  static sqlite3.Database _openDatabase(String dataDirectory) {
    Directory(dataDirectory).createSync(recursive: true);
    return sqlite3.sqlite3.open(p.join(dataDirectory, 'athenaeum.sqlite'));
  }

  Directory get blobDirectory =>
      Directory(p.join(config.dataDirectory, 'blobs'));

  void close() => _database.close();

  StoreRow? lookup(String idKey) {
    final rows = _database.select(
      'SELECT id_key, epoch, created_at, last_seen, bytes_used '
      'FROM stores WHERE id_key = ?',
      [idKey],
    );
    if (rows.isEmpty) return null;
    return StoreRow.fromRow(rows.single);
  }

  StoreRow create(String idKey) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final epoch = _randomEpoch();
    _database.execute('BEGIN IMMEDIATE');
    final existing = lookup(idKey);
    if (existing != null) {
      _database.execute('ROLLBACK');
      throw StoreAlreadyExists(existing);
    }
    try {
      _database.execute(
        'INSERT INTO stores (id_key, epoch, created_at, last_seen, bytes_used) '
        'VALUES (?, ?, ?, ?, 0)',
        [idKey, epoch, now, now],
      );
      _database.execute('COMMIT');
    } on sqlite3.SqliteException {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return lookup(idKey)!;
  }

  void touch(String idKey) {
    _database.execute('UPDATE stores SET last_seen = ? WHERE id_key = ?', [
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      idKey,
    ]);
  }

  StoreMetadata metadata(StoreRow store) {
    final deviceRows = _database.select(
      'SELECT device_id FROM manifests WHERE id_key = ? AND epoch = ? '
      'ORDER BY device_id',
      [store.idKey, store.epoch],
    );
    final blobRows = _database.select(
      'SELECT COUNT(*) AS count FROM blob_refs WHERE id_key = ? AND epoch = ?',
      [store.idKey, store.epoch],
    );
    return StoreMetadata(
      epoch: store.epoch,
      devices: [for (final row in deviceRows) row['device_id'] as String],
      blobs: (blobRows.single['count'] as int?) ?? 0,
      bytes: store.bytesUsed,
    );
  }

  ManifestRow? manifest(String idKey, String epoch, String deviceId) {
    final rows = _database.select(
      'SELECT etag, written_at, body FROM manifests '
      'WHERE id_key = ? AND epoch = ? AND device_id = ?',
      [idKey, epoch, deviceId],
    );
    if (rows.isEmpty) return null;
    return ManifestRow(
      etag: rows.single['etag'] as String,
      writtenAt: rows.single['written_at'] as int,
      body: Uint8List.fromList(rows.single['body'] as List<int>),
    );
  }

  void putManifest({
    required String idKey,
    required String epoch,
    required String deviceId,
    required String etag,
    required int writtenAt,
    required Uint8List body,
  }) {
    _database.execute(
      'INSERT INTO manifests (id_key, epoch, device_id, etag, written_at, body) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (id_key, epoch, device_id) DO UPDATE SET '
      'etag = excluded.etag, written_at = excluded.written_at, body = excluded.body',
      [idKey, epoch, deviceId, etag, writtenAt, body],
    );
  }

  void deleteManifest(String idKey, String epoch, String deviceId) {
    _database.execute(
      'DELETE FROM manifests WHERE id_key = ? AND epoch = ? AND device_id = ?',
      [idKey, epoch, deviceId],
    );
  }

  BlobRef? blobRef(String idKey, String epoch, String hash) {
    final rows = _database.select(
      'SELECT size, uploaded_at FROM blob_refs '
      'WHERE id_key = ? AND epoch = ? AND hash = ?',
      [idKey, epoch, hash],
    );
    if (rows.isEmpty) return null;
    return BlobRef(
      size: rows.single['size'] as int,
      uploadedAt: rows.single['uploaded_at'] as int,
    );
  }

  List<String> missingBlobs(String idKey, String epoch, List<String> hashes) {
    final present = <String>{};
    for (final hash in hashes) {
      if (blobRef(idKey, epoch, hash) != null) present.add(hash);
    }
    return [
      for (final hash in hashes)
        if (!present.contains(hash)) hash,
    ];
  }

  void putBlob({
    required String idKey,
    required String epoch,
    required String hash,
    required Uint8List body,
  }) {
    final existing = blobRef(idKey, epoch, hash);
    if (existing != null) return;
    final file = blobFile(idKey, epoch, hash);
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.$pid.tmp');
    temporary.writeAsBytesSync(body, flush: true);
    temporary.renameSync(file.path);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _database.execute(
      'INSERT INTO blob_refs (id_key, epoch, hash, size, uploaded_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [idKey, epoch, hash, body.length, now],
    );
    _database.execute(
      'UPDATE stores SET bytes_used = bytes_used + ?, last_seen = ? '
      'WHERE id_key = ? AND epoch = ?',
      [body.length, now, idKey, epoch],
    );
  }

  File blobFile(String idKey, String epoch, String hash) {
    _validateHash(hash);
    return File(
      p.join(
        blobDirectory.path,
        idKey,
        epoch,
        hash.substring(0, 2),
        hash.substring(2, 4),
        hash,
      ),
    );
  }

  void deleteStore(String idKey) {
    final rows = _database.select('SELECT epoch FROM stores WHERE id_key = ?', [
      idKey,
    ]);
    if (rows.isEmpty) return;
    final epoch = rows.single['epoch'] as String;
    _database.execute('DELETE FROM manifests WHERE id_key = ?', [idKey]);
    _database.execute('DELETE FROM blob_refs WHERE id_key = ?', [idKey]);
    _database.execute('DELETE FROM stores WHERE id_key = ?', [idKey]);
    final directory = Directory(p.join(blobDirectory.path, idKey, epoch));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  static void validateDeviceId(String value) {
    if (!_deviceIdPattern.hasMatch(value)) {
      throw const FormatException('invalid device id');
    }
  }

  static void _validateHash(String value) {
    if (!_hashPattern.hasMatch(value)) {
      throw const FormatException('invalid blob hash');
    }
  }

  static String _randomEpoch() {
    final random = AthenaeumConfig.generatePepper();
    return random.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class StoreAlreadyExists implements Exception {
  const StoreAlreadyExists(this.store);

  final StoreRow store;
}

class StoreRow {
  const StoreRow({
    required this.idKey,
    required this.epoch,
    required this.createdAt,
    required this.lastSeen,
    required this.bytesUsed,
  });

  factory StoreRow.fromRow(Map<String, Object?> row) => StoreRow(
    idKey: row['id_key'] as String,
    epoch: row['epoch'] as String,
    createdAt: row['created_at'] as int,
    lastSeen: row['last_seen'] as int,
    bytesUsed: row['bytes_used'] as int,
  );

  final String idKey;
  final String epoch;
  final int createdAt;
  final int lastSeen;
  final int bytesUsed;
}

class StoreMetadata {
  const StoreMetadata({
    required this.epoch,
    required this.devices,
    required this.blobs,
    required this.bytes,
  });

  final String epoch;
  final List<String> devices;
  final int blobs;
  final int bytes;

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'devices': devices,
    'quota': {
      'blobs': blobs,
      'bytes': bytes,
      'maxBlobs': 100000,
      'maxBytes': 250 * 1024 * 1024,
    },
  };
}

class ManifestRow {
  const ManifestRow({
    required this.etag,
    required this.writtenAt,
    required this.body,
  });

  final String etag;
  final int writtenAt;
  final Uint8List body;
}

class BlobRef {
  const BlobRef({required this.size, required this.uploadedAt});

  final int size;
  final int uploadedAt;
}

String rawBodyHash(Uint8List body) => sha256.convert(body).toString();

String epochFromManifest(Uint8List body) {
  final value = jsonDecode(utf8.decode(body));
  if (value is! Map || value['epoch'] is! String) {
    throw const FormatException('manifest epoch is required');
  }
  return value['epoch'] as String;
}

int writtenAtFromManifest(Uint8List body) {
  final value = jsonDecode(utf8.decode(body));
  if (value is! Map || value['writtenAt'] is! String) {
    throw const FormatException('manifest writtenAt is required');
  }
  final parsed = DateTime.tryParse(value['writtenAt'] as String);
  if (parsed == null) throw const FormatException('invalid manifest timestamp');
  return parsed.millisecondsSinceEpoch ~/ 1000;
}

void validateJsonDepth(Object? value, [int depth = 0]) {
  if (depth > maxJsonDepth) {
    throw const FormatException('JSON nesting depth exceeds limit');
  }
  if (value is Map) {
    for (final child in value.values) {
      validateJsonDepth(child, depth + 1);
    }
  } else if (value is List) {
    for (final child in value) {
      validateJsonDepth(child, depth + 1);
    }
  }
}
