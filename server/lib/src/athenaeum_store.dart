import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'athenaeum_config.dart';
import 'athenaeum_schema.dart';

typedef DirectoryDelete = void Function(Directory directory);
typedef FileDelete = void Function(File file);

const int maxBlobBytes = 1024 * 1024;
const int maxManifestBytes = 16 * 1024 * 1024;
const int maxMissingHashes = 10000;
const int maxJsonDepth = 32;
const int maxGzipBytes = 32 * 1024 * 1024;
const int maxStoreBlobs = 100000;
const int maxStoreBytes = 250 * 1024 * 1024;
const int maxStoreDevices = 32;
const Duration storeDisuseTtl = Duration(days: 30);
const Duration uploadGracePeriod = Duration(hours: 24);
const Duration breakGlassLinkabilityPeriod = Duration(days: 30);
const int maxStoreCreationsPerMinute = 60;
const int maxFailedResolutionsPerIp = 10;
const int maxFailedResolutionsPerIpBurst = 20;
const int maxFailedResolutionsServerWide = 1000;

final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');

class AthenaeumStore {
  AthenaeumStore({
    required AthenaeumConfig config,
    sqlite3.Database? database,
    sqlite3.Database? breakGlassDatabase,
    DirectoryDelete? deleteDirectory,
    FileDelete? deleteFile,
    DateTime Function()? clock,
  }) : config = config,
       _database = database ?? _openDatabase(config.dataDirectory),
       _breakGlassDatabase =
           breakGlassDatabase ?? _openBreakGlassDatabase(config.dataDirectory),
       _deleteDirectory = deleteDirectory ?? _deleteDirectoryRecursively,
       _deleteFile = deleteFile ?? _deleteFileSync,
       _clock = clock ?? DateTime.now {
    Directory(config.dataDirectory).createSync(recursive: true);
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA journal_mode = WAL');
    for (final table in athenaeumTableSchemas) {
      _database.execute(table.createSql());
    }
    for (final table in breakGlassTableSchemas) {
      _breakGlassDatabase.execute(table.createSql());
    }
    retryPendingDeletions();
  }

  final AthenaeumConfig config;
  final sqlite3.Database _database;
  final sqlite3.Database _breakGlassDatabase;
  final DirectoryDelete _deleteDirectory;
  final FileDelete _deleteFile;
  final DateTime Function() _clock;

  static sqlite3.Database _openDatabase(String dataDirectory) {
    Directory(dataDirectory).createSync(recursive: true);
    return sqlite3.sqlite3.open(p.join(dataDirectory, 'athenaeum.sqlite'));
  }

  static sqlite3.Database _openBreakGlassDatabase(String dataDirectory) {
    Directory(dataDirectory).createSync(recursive: true);
    return sqlite3.sqlite3.open(
      p.join(dataDirectory, 'athenaeum-break-glass.sqlite'),
    );
  }

  Directory get blobDirectory =>
      Directory(p.join(config.dataDirectory, 'blobs'));

  void close() {
    _database.close();
    _breakGlassDatabase.close();
  }

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
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    final epoch = _randomEpoch();
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final existing = lookup(idKey);
      if (existing != null) {
        _database.execute('ROLLBACK');
        inTransaction = false;
        throw StoreAlreadyExists(existing);
      }
      _database.execute(
        'INSERT INTO stores (id_key, epoch, created_at, last_seen, bytes_used) '
        'VALUES (?, ?, ?, ?, 0)',
        [idKey, epoch, now, now],
      );
      _database.execute('COMMIT');
      inTransaction = false;
    } on sqlite3.SqliteException {
      if (inTransaction) _database.execute('ROLLBACK');
      rethrow;
    }
    return lookup(idKey)!;
  }

  void touch(String idKey) {
    _database.execute('UPDATE stores SET last_seen = ? WHERE id_key = ?', [
      _clock().millisecondsSinceEpoch ~/ 1000,
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

  bool putManifest({
    required String idKey,
    required String epoch,
    required String deviceId,
    required String etag,
    required int writtenAt,
    required Uint8List body,
  }) {
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final current = lookup(idKey);
      if (current == null || current.epoch != epoch) {
        throw const StoreEpochMismatch();
      }
      final existed = _database.select(
        'SELECT 1 FROM manifests WHERE id_key = ? AND epoch = ? '
        'AND device_id = ?',
        [idKey, epoch, deviceId],
      ).isNotEmpty;
      if (!existed) {
        final count =
            _database.select(
                  'SELECT COUNT(*) AS count FROM manifests WHERE id_key = ? AND epoch = ?',
                  [idKey, epoch],
                ).single['count']
                as int;
        if (count >= maxStoreDevices) {
          throw const StoreQuotaExceeded('device quota exhausted');
        }
      }
      _database.execute(
        'INSERT INTO manifests (id_key, epoch, device_id, etag, written_at, body) '
        'VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (id_key, epoch, device_id) DO UPDATE SET '
        'etag = excluded.etag, written_at = excluded.written_at, body = excluded.body',
        [idKey, epoch, deviceId, etag, writtenAt, body],
      );
      _database.execute('COMMIT');
      inTransaction = false;
      return !existed;
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        rethrow;
      }
    }
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
    const batchSize = 500;
    for (var offset = 0; offset < hashes.length; offset += batchSize) {
      final batch = hashes.skip(offset).take(batchSize).toList();
      final placeholders = List<String>.filled(batch.length, '?').join(', ');
      final rows = _database.select(
        'SELECT hash FROM blob_refs WHERE id_key = ? AND epoch = ? '
        'AND hash IN ($placeholders)',
        [idKey, epoch, ...batch],
      );
      present.addAll(rows.map((row) => row['hash'] as String));
    }
    return [
      for (final hash in hashes)
        if (!present.contains(hash)) hash,
    ];
  }

  void collectGarbage(String idKey, String epoch, {DateTime? now}) {
    final cutoff =
        (now ?? _clock()).subtract(uploadGracePeriod).millisecondsSinceEpoch ~/
        1000;
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final referenced = <String>{};
      final manifests = _database.select(
        'SELECT body FROM manifests WHERE id_key = ? AND epoch = ?',
        [idKey, epoch],
      );
      for (final row in manifests) {
        final decoded = jsonDecode(utf8.decode(row['body'] as List<int>));
        if (decoded is! Map || decoded['records'] is! Map) continue;
        final records = decoded['records'] as Map;
        for (final kind in records.values) {
          if (kind is! Map) continue;
          for (final hash in kind.values) {
            if (hash is String && _hashPattern.hasMatch(hash)) {
              referenced.add(hash);
            }
          }
        }
      }
      final stale = _database.select(
        'SELECT hash, size FROM blob_refs '
        'WHERE id_key = ? AND epoch = ? AND uploaded_at < ?',
        [idKey, epoch, cutoff],
      );
      for (final row in stale) {
        final hash = row['hash'] as String;
        if (referenced.contains(hash)) continue;
        _validateHash(hash);
        final file = blobFile(idKey, epoch, hash);
        if (file.existsSync()) _deleteFile(file);
        _database.execute(
          'DELETE FROM blob_refs WHERE id_key = ? AND epoch = ? AND hash = ?',
          [idKey, epoch, hash],
        );
        _database.execute(
          'UPDATE stores SET bytes_used = MAX(0, bytes_used - ?) '
          'WHERE id_key = ? AND epoch = ?',
          [row['size'], idKey, epoch],
        );
      }
      _database.execute('COMMIT');
      inTransaction = false;
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        rethrow;
      }
    }
  }

  void sweep({DateTime? now}) {
    final current = now ?? _clock();
    final cutoff =
        current.subtract(storeDisuseTtl).millisecondsSinceEpoch ~/ 1000;
    final expired = _database
        .select('SELECT id_key FROM stores WHERE last_seen < ?', [cutoff])
        .map((row) => row['id_key'] as String)
        .toList();
    for (final idKey in expired) {
      deleteStore(idKey);
    }
    final activeStores = _database.select('SELECT id_key, epoch FROM stores');
    for (final row in activeStores) {
      collectGarbage(
        row['id_key'] as String,
        row['epoch'] as String,
        now: current,
      );
    }
    purgeExpiredBreakGlassAccess(now: current);
  }

  void recordBreakGlassAccess(String syncId, {DateTime? accessedAt}) {
    final now = accessedAt ?? _clock();
    purgeExpiredBreakGlassAccess(now: now);
    final idKey = deriveIncomingSyncIdKey(syncId, config.pepper);
    _breakGlassDatabase.execute(
      'INSERT INTO break_glass_access (id_key, accessed_at) VALUES (?, ?)',
      [idKey, now.millisecondsSinceEpoch ~/ 1000],
    );
  }

  void purgeExpiredBreakGlassAccess({DateTime? now}) {
    final cutoff =
        (now ?? _clock())
            .subtract(breakGlassLinkabilityPeriod)
            .millisecondsSinceEpoch ~/
        1000;
    _breakGlassDatabase.execute(
      'UPDATE break_glass_access SET id_key = NULL '
      'WHERE id_key IS NOT NULL AND accessed_at < ?',
      [cutoff],
    );
  }

  bool putBlob({
    required String idKey,
    required String epoch,
    required String hash,
    required Uint8List body,
  }) {
    var inTransaction = false;
    var published = false;
    File? file;
    File? temporary;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      if (blobRef(idKey, epoch, hash) != null) {
        _database.execute('ROLLBACK');
        inTransaction = false;
        return false;
      }
      final current = lookup(idKey);
      if (current != null && current.epoch == epoch) {
        final count =
            _database.select(
                  'SELECT COUNT(*) AS count FROM blob_refs WHERE id_key = ? AND epoch = ?',
                  [idKey, epoch],
                ).single['count']
                as int;
        if (count >= maxStoreBlobs) {
          throw const StoreQuotaExceeded('blob quota exhausted');
        }
        if (current.bytesUsed > maxStoreBytes - body.length) {
          throw const StoreQuotaExceeded('byte quota exhausted');
        }
      }
      file = blobFile(idKey, epoch, hash);
      file.parent.createSync(recursive: true);
      final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
      temporary = File(
        '${file.path}.$pid.${_clock().microsecondsSinceEpoch}.$nonce.tmp',
      );
      temporary.writeAsBytesSync(body, flush: true);
      temporary.renameSync(file.path);
      published = true;
      final now = _clock().millisecondsSinceEpoch ~/ 1000;
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
      _database.execute('COMMIT');
      inTransaction = false;
      return true;
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        if (published && file != null && file.existsSync()) {
          file.deleteSync();
        }
        if (temporary != null && temporary.existsSync()) {
          temporary.deleteSync();
        }
        rethrow;
      }
    }
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

  sqlite3.Database get breakGlassDatabase => _breakGlassDatabase;

  sqlite3.Database get database => _database;

  void deleteStore(String idKey) {
    late final String epoch;
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final rows = _database.select(
        'SELECT epoch FROM stores WHERE id_key = ?',
        [idKey],
      );
      if (rows.isEmpty) {
        _database.execute('ROLLBACK');
        inTransaction = false;
        return;
      }
      epoch = rows.single['epoch'] as String;
      final epochs = <String>{
        epoch,
        for (final row in _database.select(
          'SELECT epoch FROM manifests WHERE id_key = ? '
          'UNION SELECT epoch FROM blob_refs WHERE id_key = ?',
          [idKey, idKey],
        ))
          row['epoch'] as String,
      };
      for (final queuedEpoch in epochs) {
        _database.execute(
          'INSERT OR IGNORE INTO deletion_jobs (id_key, epoch, queued_at) '
          'VALUES (?, ?, ?)',
          [idKey, queuedEpoch, _clock().millisecondsSinceEpoch ~/ 1000],
        );
      }
      _database.execute('DELETE FROM manifests WHERE id_key = ?', [idKey]);
      _database.execute('DELETE FROM blob_refs WHERE id_key = ?', [idKey]);
      _database.execute('DELETE FROM stores WHERE id_key = ?', [idKey]);
      _database.execute('COMMIT');
      inTransaction = false;
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        rethrow;
      }
    }
    retryPendingDeletions();
  }

  void retryPendingDeletions() {
    final rows = _database.select(
      'SELECT id_key, epoch FROM deletion_jobs ORDER BY queued_at',
    );
    for (final row in rows) {
      final idKey = row['id_key'] as String;
      final epoch = row['epoch'] as String;
      final directory = Directory(p.join(blobDirectory.path, idKey, epoch));
      try {
        _deleteDirectory(directory);
      } on FileSystemException {
        continue;
      }
      var inTransaction = false;
      try {
        _database.execute('BEGIN IMMEDIATE');
        inTransaction = true;
        _database.execute(
          'DELETE FROM deletion_jobs WHERE id_key = ? AND epoch = ?',
          [idKey, epoch],
        );
        _database.execute('COMMIT');
        inTransaction = false;
      } catch (error) {
        try {
          if (inTransaction) _database.execute('ROLLBACK');
        } finally {
          rethrow;
        }
      }
    }
  }

  static void _deleteDirectoryRecursively(Directory directory) {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  static void _deleteFileSync(File file) => file.deleteSync();

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
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class StoreAlreadyExists implements Exception {
  const StoreAlreadyExists(this.store);

  final StoreRow store;
}

class StoreEpochMismatch implements Exception {
  const StoreEpochMismatch();
}

class StoreQuotaExceeded implements Exception {
  const StoreQuotaExceeded(this.message);

  final String message;
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
      'maxBlobs': maxStoreBlobs,
      'maxBytes': maxStoreBytes,
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
