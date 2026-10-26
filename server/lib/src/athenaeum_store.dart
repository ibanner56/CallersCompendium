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
typedef AthenaeumOperationalFailureSink =
    void Function(String source, Object error);

class AthenaeumQuotaLimits {
  const AthenaeumQuotaLimits({
    this.maxBlobs = maxStoreBlobs,
    this.maxBytes = maxStoreBytes,
    this.maxDevices = maxStoreDevices,
  });

  final int maxBlobs;
  final int maxBytes;
  final int maxDevices;
}

const int maxBlobBytes = 1024 * 1024;
const int maxManifestBytes = 16 * 1024 * 1024;
const int maxMissingHashes = 10000;

/// The largest `POST /v1/blobs/batch` request body: room for the
/// [syncBlobBatchMaxHashes] hashes it may name, with generous whitespace.
const int maxBlobBatchRequestBytes = 64 * 1024;
const int maxJsonDepth = 32;
const int maxGzipBytes = 32 * 1024 * 1024;
const int maxStoreBlobs = 100000;
const int maxStoreBytes = 250 * 1024 * 1024;
const int maxStoreDevices = 32;
const Duration storeDisuseTtl = Duration(days: 30);
const Duration uploadGracePeriod = Duration(hours: 24);
const Duration breakGlassLinkabilityPeriod = Duration(days: 30);
const Duration diagnosticRetentionPeriod = Duration(days: 30);
const int maxDiagnosticRows = 10000;
const int maxStoreCreationsPerMinute = 60;
const int maxFailedResolutionsPerIp = 10;
const int maxFailedResolutionsPerIpBurst = 20;
const int maxFailedResolutionsServerWide = 1000;
const int maxPendingDeletionRetriesPerRequest = 16;
const int maxPendingDeletionRetriesPerSweep = 1000;

/// Wall-clock budget for the cleanup a single request performs. The job-count
/// cap alone does not bound latency: one directory job is a recursive delete.
/// The budget is checked between jobs, so a job that has started always
/// finishes, and at least one job runs per call so the queue still drains.
const Duration requestPendingDeletionBudget = Duration(milliseconds: 50);

/// Milliseconds a connection waits for a competing writer before failing with
/// `SQLITE_BUSY`; sqlite3's default is `0`, which fails at once.
///
/// The value is an implementer's choice, not a measured budget, and is
/// deliberately short. The server is one isolate and sqlite3's API is
/// synchronous, so a wait stalls *every* request, not just the one that hit the
/// lock. The only competing writer is the operator's break-glass process, whose
/// store-database work is read-only, so contention is rare; the wait exists to
/// ride out a brief overlap, and bounds the stall a stuck lock can cause to a
/// quarter second. Do not copy the client's 30 s here
/// (`compendiumSqliteBusyTimeoutMs`): that trades a lost write for a frozen
/// server.
const int athenaeumSqliteBusyTimeoutMs = 250;

final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _epochPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _temporaryBlobPattern = RegExp(
  r'^([0-9a-f]{64})\.[0-9]+\.[0-9]+\.[0-9a-f]+\.tmp$',
);

class AthenaeumStore {
  AthenaeumStore({
    required AthenaeumConfig config,
    sqlite3.Database? database,
    sqlite3.Database? breakGlassDatabase,
    sqlite3.Database? diagnosticDatabase,
    DirectoryDelete? deleteDirectory,
    FileDelete? deleteFile,
    DateTime Function()? clock,
    Duration Function()? elapsed,
    this.quotaLimits = const AthenaeumQuotaLimits(),
    this.diagnosticRowLimit = maxDiagnosticRows,
    this.operationalFailureSink,
  }) : config = config,
       _database = database ?? _openDatabase(config.dataDirectory),
       _breakGlassDatabase =
           breakGlassDatabase ?? _openBreakGlassDatabase(config.dataDirectory),
       _diagnosticDatabase =
           diagnosticDatabase ?? _openDiagnosticDatabase(config.dataDirectory),
       _deleteDirectory = deleteDirectory ?? _deleteDirectoryRecursively,
       _deleteFile = deleteFile ?? _deleteFileSync,
       _clock = clock ?? DateTime.now,
       _elapsed = elapsed ?? _monotonicElapsed() {
    Directory(config.dataDirectory).createSync(recursive: true);
    _database.execute('PRAGMA busy_timeout = $athenaeumSqliteBusyTimeoutMs');
    _breakGlassDatabase.execute(
      'PRAGMA busy_timeout = $athenaeumSqliteBusyTimeoutMs',
    );
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA journal_mode = WAL');
    for (final table in athenaeumTableSchemas) {
      _database.execute(table.createSql());
    }
    _database.execute(
      'CREATE INDEX IF NOT EXISTS deletion_jobs_queued_at_idx '
      'ON deletion_jobs (queued_at)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS blob_deletion_jobs_queued_at_idx '
      'ON blob_deletion_jobs (queued_at)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS stores_last_seen_idx '
      'ON stores (last_seen)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS manifest_refs_hash_idx '
      'ON manifest_refs (id_key, epoch, hash)',
    );
    for (final table in breakGlassTableSchemas) {
      _breakGlassDatabase.execute(table.createSql());
    }
    _breakGlassDatabase.execute(
      'CREATE INDEX IF NOT EXISTS break_glass_access_linkable_idx '
      'ON break_glass_access (accessed_at) WHERE id_key IS NOT NULL',
    );
    for (final table in diagnosticTableSchemas) {
      _diagnosticDatabase.execute(table.createSql());
    }
    _diagnosticDatabase.execute(
      'CREATE INDEX IF NOT EXISTS diagnostic_events_recorded_at_idx '
      'ON diagnostic_events (recorded_at)',
    );
    _indexUnindexedManifests();
    _reconcileOrphanedBlobFiles();
    retryPendingDeletions();
  }

  /// Opens the store for the operator's `--break-glass` read, and nothing else.
  ///
  /// The documented procedure runs this in a second process against the live
  /// volume, so it must not contend with the server: `athenaeum.sqlite` is
  /// opened `OpenMode.readOnly`, and none of the full constructor's startup
  /// work runs (no schema or index creation, no manifest indexing, no orphan
  /// blob reconcile, no pending-deletion retry). Under WAL a reader never
  /// blocks the server's writer. Only `lookup` and `manifest` are meant to be
  /// called on it; any write to the store database throws.
  ///
  /// The break-glass log database stays writable, because
  /// [recordBreakGlassAccess] must still record the access there. The
  /// diagnostics database is not opened at all (an in-memory stand-in keeps
  /// the field non-null), so the live one is never touched.
  ///
  /// Throws if `athenaeum.sqlite` does not exist; unlike the full
  /// constructor it never creates an empty one.
  AthenaeumStore.breakGlass({required AthenaeumConfig config})
    : config = config,
      _database = sqlite3.sqlite3.open(
        p.join(config.dataDirectory, 'athenaeum.sqlite'),
        mode: sqlite3.OpenMode.readOnly,
      ),
      _breakGlassDatabase = _openBreakGlassDatabase(config.dataDirectory),
      _diagnosticDatabase = sqlite3.sqlite3.openInMemory(),
      _deleteDirectory = _deleteDirectoryRecursively,
      _deleteFile = _deleteFileSync,
      _clock = DateTime.now,
      _elapsed = _monotonicElapsed(),
      operationalFailureSink = null,
      quotaLimits = const AthenaeumQuotaLimits(),
      diagnosticRowLimit = maxDiagnosticRows {
    _database.execute('PRAGMA busy_timeout = $athenaeumSqliteBusyTimeoutMs');
    _breakGlassDatabase.execute(
      'PRAGMA busy_timeout = $athenaeumSqliteBusyTimeoutMs',
    );
    for (final table in breakGlassTableSchemas) {
      _breakGlassDatabase.execute(table.createSql());
    }
    _breakGlassDatabase.execute(
      'CREATE INDEX IF NOT EXISTS break_glass_access_linkable_idx '
      'ON break_glass_access (accessed_at) WHERE id_key IS NOT NULL',
    );
  }

  final AthenaeumConfig config;
  final sqlite3.Database _database;
  final sqlite3.Database _breakGlassDatabase;
  final sqlite3.Database _diagnosticDatabase;
  final DirectoryDelete _deleteDirectory;
  final FileDelete _deleteFile;
  final DateTime Function() _clock;

  /// Monotonic elapsed time, used only for request-path budgets. [_clock] is
  /// wall time and can step backwards, so it is kept for persisted timestamps.
  final Duration Function() _elapsed;
  final AthenaeumOperationalFailureSink? operationalFailureSink;
  final AthenaeumQuotaLimits quotaLimits;
  final int diagnosticRowLimit;

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

  static sqlite3.Database _openDiagnosticDatabase(String dataDirectory) {
    Directory(dataDirectory).createSync(recursive: true);
    return sqlite3.sqlite3.open(
      p.join(dataDirectory, 'athenaeum-diagnostics.sqlite'),
    );
  }

  Directory get blobDirectory =>
      Directory(p.join(config.dataDirectory, 'blobs'));

  void checkHealth() {
    _database.select('SELECT 1');
    _breakGlassDatabase.select('SELECT 1');
    _diagnosticDatabase.select('SELECT 1');
  }

  /// Builds `manifest_refs` for every unindexed manifest, and drops index rows
  /// whose manifest is gone.
  ///
  /// A database written before #1910 has no index, and an earlier server
  /// image run after a rollback writes and deletes manifests without touching
  /// it, so this runs on every start rather than once. A body that does not
  /// decode is left unindexed rather than failing startup; GC then reads it
  /// the way it did before the index existed (see [collectGarbage]).
  void _indexUnindexedManifests() {
    final orphans = _database.select(
      'SELECT id_key, epoch, device_id FROM indexed_manifests i '
      'WHERE NOT EXISTS (SELECT 1 FROM manifests m '
      'WHERE m.id_key = i.id_key AND m.epoch = i.epoch '
      'AND m.device_id = i.device_id)',
    );
    for (final row in orphans) {
      _inTransaction(
        () => _deleteManifestRefs(
          row['id_key'] as String,
          row['epoch'] as String,
          row['device_id'] as String,
        ),
      );
    }
    final unindexed = _database.select(
      'SELECT m.rowid AS rowid, m.etag AS etag FROM manifests m '
      'WHERE $_manifestUnindexedSql',
    );
    for (final row in unindexed) {
      final body = _database.select(
        'SELECT id_key, epoch, device_id, body FROM manifests WHERE rowid = ?',
        [row['rowid']],
      ).single;
      final Set<String> hashes;
      try {
        hashes = _hashesNamedByManifest(body['body'] as List<int>);
      } on FormatException {
        continue;
      }
      _inTransaction(
        () => _replaceManifestRefs(
          body['id_key'] as String,
          body['epoch'] as String,
          body['device_id'] as String,
          row['etag'] as String,
          hashes,
        ),
      );
    }
  }

  /// Matches a `manifests m` row whose `manifest_refs` were not read from its
  /// current body. Reads `etag`, never `body`.
  static const String _manifestUnindexedSql =
      'NOT EXISTS (SELECT 1 FROM indexed_manifests i '
      'WHERE i.id_key = m.id_key AND i.epoch = m.epoch '
      'AND i.device_id = m.device_id AND i.etag = m.etag)';

  /// The blob hashes a stored manifest body names: every hash-shaped string
  /// under `records.<kind>.<id>`. Anything else in the body names nothing.
  /// Throws [FormatException] if the body is not UTF-8 JSON.
  static Set<String> _hashesNamedByManifest(List<int> body) {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map || decoded['records'] is! Map) return const {};
    return {
      for (final kind in (decoded['records'] as Map).values)
        if (kind is Map)
          for (final hash in kind.values)
            if (hash is String && _hashPattern.hasMatch(hash)) hash,
    };
  }

  /// Makes [hashes] the `manifest_refs` rows for one device's manifest and
  /// records [etag] as the body they were read from. Caller holds the write
  /// transaction.
  void _replaceManifestRefs(
    String idKey,
    String epoch,
    String deviceId,
    String etag,
    Set<String> hashes,
  ) {
    final existing = {
      for (final row in _database.select(
        'SELECT hash FROM manifest_refs '
        'WHERE id_key = ? AND epoch = ? AND device_id = ?',
        [idKey, epoch, deviceId],
      ))
        row['hash'] as String,
    };
    final delete = _database.prepare(
      'DELETE FROM manifest_refs '
      'WHERE id_key = ? AND epoch = ? AND device_id = ? AND hash = ?',
    );
    final insert = _database.prepare(
      'INSERT INTO manifest_refs (id_key, epoch, device_id, hash) '
      'VALUES (?, ?, ?, ?)',
    );
    try {
      for (final hash in existing.difference(hashes)) {
        delete.execute([idKey, epoch, deviceId, hash]);
      }
      for (final hash in hashes.difference(existing)) {
        insert.execute([idKey, epoch, deviceId, hash]);
      }
    } finally {
      delete.close();
      insert.close();
    }
    _database.execute(
      'INSERT INTO indexed_manifests (id_key, epoch, device_id, etag) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT (id_key, epoch, device_id) DO UPDATE SET '
      'etag = excluded.etag',
      [idKey, epoch, deviceId, etag],
    );
  }

  /// Removes one device's `manifest_refs` rows. Caller holds the write
  /// transaction.
  void _deleteManifestRefs(String idKey, String epoch, String deviceId) {
    _database.execute(
      'DELETE FROM manifest_refs '
      'WHERE id_key = ? AND epoch = ? AND device_id = ?',
      [idKey, epoch, deviceId],
    );
    _database.execute(
      'DELETE FROM indexed_manifests '
      'WHERE id_key = ? AND epoch = ? AND device_id = ?',
      [idKey, epoch, deviceId],
    );
  }

  void _inTransaction(void Function() body) {
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      body();
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

  /// Queues crash-orphaned final blob files and temporary upload artifacts.
  ///
  /// `dart:io` has no lazy synchronous directory iteration, so this still
  /// blocks startup; it bounds the work instead. The tree is walked one
  /// `<idKey>/<epoch>` directory at a time rather than listed whole, each
  /// epoch's refs are read with one select rather than one per file, and each
  /// epoch's jobs are queued in one transaction.
  void _reconcileOrphanedBlobFiles() {
    if (!blobDirectory.existsSync()) return;
    final queuedAt = _clock().millisecondsSinceEpoch ~/ 1000;
    for (final idDirectory in blobDirectory.listSync().whereType<Directory>()) {
      final idKey = p.basename(idDirectory.path);
      if (!_hashPattern.hasMatch(idKey)) continue;
      for (final epochDirectory
          in idDirectory.listSync().whereType<Directory>()) {
        final epoch = p.basename(epochDirectory.path);
        if (!_epochPattern.hasMatch(epoch)) continue;
        _queueOrphansInEpoch(idKey, epoch, epochDirectory, queuedAt);
      }
    }
  }

  void _queueOrphansInEpoch(
    String idKey,
    String epoch,
    Directory epochDirectory,
    int queuedAt,
  ) {
    Set<String>? referenced;
    var inTransaction = false;
    try {
      for (final entity in epochDirectory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final segments = p.split(
          p.relative(entity.path, from: epochDirectory.path),
        );
        if (segments.length != 3) continue;
        final filename = segments[2];
        final temporaryMatch = _temporaryBlobPattern.firstMatch(filename);
        final hash = temporaryMatch?.group(1) ?? filename;
        if (!_hashPattern.hasMatch(hash) ||
            segments[0] != hash.substring(0, 2) ||
            segments[1] != hash.substring(2, 4) ||
            (temporaryMatch == null && filename != hash)) {
          continue;
        }
        if (!inTransaction) {
          _database.execute('BEGIN IMMEDIATE');
          inTransaction = true;
        }
        if (temporaryMatch == null) {
          referenced ??= {
            for (final row in _database.select(
              'SELECT hash FROM blob_refs WHERE id_key = ? AND epoch = ?',
              [idKey, epoch],
            ))
              row['hash'] as String,
          };
          if (referenced.contains(hash)) continue;
        }
        _database.execute(
          'INSERT OR IGNORE INTO blob_deletion_jobs '
          '(id_key, epoch, hash, queued_at) VALUES (?, ?, ?, ?)',
          [idKey, epoch, hash, queuedAt],
        );
      }
      if (inTransaction) {
        _database.execute('COMMIT');
        inTransaction = false;
      }
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        rethrow;
      }
    }
  }

  void close() {
    _database.close();
    _breakGlassDatabase.close();
    _diagnosticDatabase.close();
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
      'SELECT COUNT(*) AS count FROM blob_refs WHERE id_key = ?',
      [store.idKey],
    );
    final byteRows = _database.select(
      'SELECT COALESCE(SUM(size), 0) AS bytes FROM blob_refs WHERE id_key = ?',
      [store.idKey],
    );
    final pending = _pendingDeletionUsage(store.idKey);
    return StoreMetadata(
      epoch: store.epoch,
      devices: [for (final row in deviceRows) row['device_id'] as String],
      blobs: ((blobRows.single['count'] as int?) ?? 0) + pending.blobs,
      bytes:
          (byteRows.single['bytes'] as int) +
          pending.bytes +
          _manifestBytes(store.idKey),
      maxBlobs: quotaLimits.maxBlobs,
      maxBytes: quotaLimits.maxBytes,
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

  /// Stores one device's manifest. [referencedHashes] are the blob hashes its
  /// `records` name, which the caller has already decoded; they become the
  /// rows GC reads instead of the body, in the same transaction.
  bool putManifest({
    required String idKey,
    required String epoch,
    required String deviceId,
    required String etag,
    required int writtenAt,
    required Uint8List body,
    required Iterable<String> referencedHashes,
  }) {
    final hashes = referencedHashes.toSet();
    hashes.forEach(_validateHash);
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final current = lookup(idKey);
      if (current == null) throw const StoreMissing();
      if (current.epoch != epoch) throw const StoreEpochMismatch();
      final existed = _manifestExists(idKey, epoch, deviceId);
      _checkManifestDeviceQuota(idKey, epoch, deviceId, existed: existed);
      if (body.length > _manifestByteLimit(current, deviceId)) {
        throw const StoreQuotaExceeded('byte quota exhausted');
      }
      _database.execute(
        'INSERT INTO manifests (id_key, epoch, device_id, etag, written_at, body) '
        'VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (id_key, epoch, device_id) DO UPDATE SET '
        'etag = excluded.etag, written_at = excluded.written_at, body = excluded.body',
        [idKey, epoch, deviceId, etag, writtenAt, body],
      );
      _replaceManifestRefs(idKey, epoch, deviceId, etag, hashes);
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

  /// Returns the largest manifest body, in bytes, this device may upload.
  int manifestUploadPreflight({
    required String idKey,
    required String epoch,
    required String deviceId,
  }) {
    final current = lookup(idKey);
    if (current == null) throw const StoreMissing();
    if (current.epoch != epoch) throw const StoreEpochMismatch();
    _checkManifestDeviceQuota(idKey, epoch, deviceId);
    final limit = _manifestByteLimit(current, deviceId);
    if (limit <= 0) throw const StoreQuotaExceeded('byte quota exhausted');
    return limit;
  }

  /// Bytes available to [deviceId]'s manifest: the store's remaining byte
  /// quota with that device's current manifest treated as replaced.
  int _manifestByteLimit(StoreRow current, String deviceId) {
    final idKey = current.idKey;
    final blobBytes =
        _database.select(
              'SELECT COALESCE(SUM(size), 0) AS bytes FROM blob_refs '
              'WHERE id_key = ?',
              [idKey],
            ).single['bytes']
            as int;
    final used =
        max(current.bytesUsed, blobBytes) +
        _pendingDeletionUsage(idKey).bytes +
        _manifestBytes(
          idKey,
          excludingEpoch: current.epoch,
          excludingDeviceId: deviceId,
        );
    return min(maxManifestBytes, quotaLimits.maxBytes - used);
  }

  int _manifestBytes(
    String idKey, {
    String? excludingEpoch,
    String? excludingDeviceId,
  }) =>
      _database.select(
            'SELECT COALESCE(SUM(LENGTH(body)), 0) AS bytes FROM manifests '
            'WHERE id_key = ? '
            'AND NOT (epoch IS ? AND device_id IS ?)',
            [idKey, excludingEpoch, excludingDeviceId],
          ).single['bytes']
          as int;

  bool _manifestExists(String idKey, String epoch, String deviceId) =>
      _database.select(
        'SELECT 1 FROM manifests WHERE id_key = ? AND epoch = ? '
        'AND device_id = ?',
        [idKey, epoch, deviceId],
      ).isNotEmpty;

  void _checkManifestDeviceQuota(
    String idKey,
    String epoch,
    String deviceId, {
    bool? existed,
  }) {
    if (existed ?? _manifestExists(idKey, epoch, deviceId)) return;
    final count =
        _database.select(
              'SELECT COUNT(*) AS count FROM manifests '
              'WHERE id_key = ? AND epoch = ?',
              [idKey, epoch],
            ).single['count']
            as int;
    if (count >= quotaLimits.maxDevices) {
      throw const StoreQuotaExceeded('device quota exhausted');
    }
  }

  void deleteManifest(String idKey, String epoch, String deviceId) {
    _inTransaction(() {
      _database.execute(
        'DELETE FROM manifests WHERE id_key = ? AND epoch = ? AND device_id = ?',
        [idKey, epoch, deviceId],
      );
      _deleteManifestRefs(idKey, epoch, deviceId);
    });
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
      // A ref without its file is reported missing so the client re-uploads it
      // and `putBlob` can repair the file (sync-spec §7.1).
      present.addAll(
        rows
            .map((row) => row['hash'] as String)
            .where((hash) => blobFile(idKey, epoch, hash).existsSync()),
      );
    }
    return [
      for (final hash in hashes)
        if (!present.contains(hash)) hash,
    ];
  }

  void collectGarbage(
    String idKey,
    String epoch, {
    DateTime? now,
    int? retryMaxJobs = maxPendingDeletionRetriesPerRequest,
  }) {
    final cutoff =
        (now ?? _clock()).subtract(uploadGracePeriod).millisecondsSinceEpoch ~/
        1000;
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      // Reachability comes from `manifest_refs`, written at manifest PUT. A
      // stale row for a device keeps a blob alive, never the reverse.
      final stale = _database.select(
        'SELECT hash, size FROM blob_refs b '
        'WHERE id_key = ? AND epoch = ? AND uploaded_at < ? '
        'AND NOT EXISTS (SELECT 1 FROM manifest_refs r '
        'WHERE r.id_key = b.id_key AND r.epoch = b.epoch AND r.hash = b.hash)',
        [idKey, epoch, cutoff],
      );
      final candidates = <String>{
        for (final row in stale) row['hash'] as String,
      };
      if (candidates.isNotEmpty) {
        // Only a manifest the index does not cover is decoded: one whose body
        // did not decode at startup, which throws here as it always has.
        final manifestRows = _database.select(
          'SELECT m.rowid AS rowid FROM manifests m '
          'WHERE m.id_key = ? AND m.epoch = ? AND $_manifestUnindexedSql',
          [idKey, epoch],
        );
        for (final manifestRow in manifestRows) {
          final body =
              _database.select('SELECT body FROM manifests WHERE rowid = ?', [
                    manifestRow['rowid'],
                  ]).single['body']
                  as List<int>;
          candidates.removeAll(_hashesNamedByManifest(body));
          if (candidates.isEmpty) break;
        }
      }
      for (final row in stale) {
        final hash = row['hash'] as String;
        if (!candidates.contains(hash)) continue;
        _validateHash(hash);
        _database.execute(
          'DELETE FROM blob_refs WHERE id_key = ? AND epoch = ? AND hash = ?',
          [idKey, epoch, hash],
        );
        _database.execute(
          'INSERT OR IGNORE INTO blob_deletion_jobs '
          '(id_key, epoch, hash, queued_at) VALUES (?, ?, ?, ?)',
          [idKey, epoch, hash, _clock().millisecondsSinceEpoch ~/ 1000],
        );
        _database.execute(
          'UPDATE stores SET bytes_used = MAX(0, bytes_used - ?) '
          'WHERE id_key = ? AND epoch = ?',
          [row['size'], idKey, epoch],
        );
      }
      _database.execute('COMMIT');
      inTransaction = false;
      if (retryMaxJobs != null) {
        retryPendingBlobDeletions(maxJobs: retryMaxJobs);
      }
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        rethrow;
      }
    }
  }

  void collectGarbageForStore(
    String idKey, {
    DateTime? now,
    int? retryMaxJobs = maxPendingDeletionRetriesPerRequest,
  }) {
    final epochs = _database
        .select(
          'SELECT epoch FROM blob_refs WHERE id_key = ? '
          'UNION SELECT epoch FROM manifests WHERE id_key = ?',
          [idKey, idKey],
        )
        .map((row) => row['epoch'] as String)
        .toList();
    for (final epoch in epochs) {
      collectGarbage(idKey, epoch, now: now, retryMaxJobs: null);
    }
    if (retryMaxJobs != null) {
      retryPendingBlobDeletions(maxJobs: retryMaxJobs);
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
      try {
        deleteStore(idKey, retryGlobal: false);
      } on Object catch (error) {
        _reportOperationalFailure('store_deletion', error);
      }
    }
    final epochs = _database.select(
      'SELECT id_key, epoch FROM blob_refs '
      'UNION SELECT id_key, epoch FROM manifests',
    );
    for (final row in epochs) {
      try {
        collectGarbage(
          row['id_key'] as String,
          row['epoch'] as String,
          now: current,
          retryMaxJobs: null,
        );
      } on Object catch (error) {
        _reportOperationalFailure('garbage_collection', error);
      }
    }
    try {
      purgeExpiredBreakGlassAccess(now: current);
    } on Object catch (error) {
      _reportOperationalFailure('break_glass_retention', error);
    }
    try {
      purgeExpiredDiagnostics(now: current);
    } on Object catch (error) {
      _reportOperationalFailure('diagnostic_retention', error);
    }
    try {
      retryPendingDeletions(
        maxJobs: maxPendingDeletionRetriesPerSweep,
        reportFailures: true,
      );
    } on Object catch (error) {
      _reportOperationalFailure('deletion_retry', error);
    }
  }

  void _reportOperationalFailure(String source, Object error) {
    final sink = operationalFailureSink;
    if (sink != null) {
      sink(source, error);
      return;
    }
    stderr.writeln('Athenaeum $source failed (${error.runtimeType})');
  }

  int blobUploadLimit(String idKey, String epoch, String hash) {
    if (blobRef(idKey, epoch, hash) != null) return maxBlobBytes;
    final current = lookup(idKey);
    if (current == null) throw const StoreEpochMismatch();
    final count =
        _database.select(
              'SELECT COUNT(*) AS count FROM blob_refs WHERE id_key = ?',
              [idKey],
            ).single['count']
            as int;
    final pending = _pendingDeletionUsage(
      idKey,
      excludingEpoch: epoch,
      excludingHash: hash,
    );
    if (count + pending.blobs >= quotaLimits.maxBlobs) {
      throw const StoreQuotaExceeded('blob quota exhausted');
    }
    final aggregateBytes =
        _database.select(
              'SELECT COALESCE(SUM(size), 0) AS bytes FROM blob_refs '
              'WHERE id_key = ?',
              [idKey],
            ).single['bytes']
            as int;
    final bytesUsed =
        max(current.bytesUsed, aggregateBytes) +
        pending.bytes +
        _manifestBytes(idKey);
    if (bytesUsed >= quotaLimits.maxBytes) {
      throw const StoreQuotaExceeded('byte quota exhausted');
    }

    return min(maxBlobBytes, quotaLimits.maxBytes - bytesUsed);
  }

  _DeletionUsage _pendingDeletionUsage(
    String idKey, {
    String? excludingEpoch,
    String? excludingHash,
  }) {
    final excluded = {?excludingHash};
    var usage = const _DeletionUsage();
    final accountedPaths = <String>{};
    final directoryRows = _database.select(
      'SELECT epoch FROM deletion_jobs WHERE id_key = ?',
      [idKey],
    );
    if (directoryRows.isNotEmpty) {
      final liveRows = _database.select(
        'SELECT refs.epoch, refs.hash FROM blob_refs AS refs '
        'INNER JOIN deletion_jobs AS jobs '
        'ON jobs.id_key = refs.id_key AND jobs.epoch = refs.epoch '
        'WHERE refs.id_key = ?',
        [idKey],
      );
      for (final row in liveRows) {
        accountedPaths.add(
          blobFile(idKey, row['epoch'] as String, row['hash'] as String).path,
        );
      }
      if (excludingEpoch != null) {
        for (final hash in excluded) {
          accountedPaths.add(blobFile(idKey, excludingEpoch, hash).path);
        }
      }
    }
    final rows = _database.select(
      'SELECT epoch, hash FROM blob_deletion_jobs WHERE id_key = ?',
      [idKey],
    );
    for (final row in rows) {
      final epoch = row['epoch'] as String;
      final hash = row['hash'] as String;
      final isExcluded = epoch == excludingEpoch && excluded.contains(hash);
      if (!isExcluded && blobRef(idKey, epoch, hash) == null) {
        final file = blobFile(idKey, epoch, hash);
        if (file.existsSync() && accountedPaths.add(file.path)) {
          usage = usage.add(bytes: file.lengthSync(), blobs: 1);
        }
      }
      for (final file in _temporaryBlobFiles(idKey, epoch, hash)) {
        if (accountedPaths.add(file.path)) {
          usage = usage.add(bytes: file.lengthSync(), blobs: 1);
        }
      }
    }
    for (final row in directoryRows) {
      final directory = Directory(
        p.join(blobDirectory.path, idKey, row['epoch'] as String),
      );
      usage = usage.add(
        usage: _directoryUsage(directory, accountedPaths: accountedPaths),
      );
    }
    return usage;
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

  void recordDiagnostic({
    required int status,
    required String? idKey,
    required String? hash,
    DateTime? recordedAt,
  }) {
    final now = recordedAt ?? _clock();
    purgeExpiredDiagnostics(now: now);
    final count =
        _diagnosticDatabase
                .select('SELECT COUNT(*) AS count FROM diagnostic_events')
                .single['count']
            as int;
    if (count >= diagnosticRowLimit) {
      _diagnosticDatabase.execute(
        'DELETE FROM diagnostic_events WHERE rowid IN ('
        'SELECT rowid FROM diagnostic_events ORDER BY recorded_at LIMIT 1)',
      );
    }
    _diagnosticDatabase.execute(
      'INSERT INTO diagnostic_events (status, id_key, hash, recorded_at) '
      'VALUES (?, ?, ?, ?)',
      [status, idKey, hash, now.millisecondsSinceEpoch ~/ 1000],
    );
  }

  void purgeExpiredDiagnostics({DateTime? now}) {
    final cutoff =
        (now ?? _clock())
            .subtract(diagnosticRetentionPeriod)
            .millisecondsSinceEpoch ~/
        1000;
    _diagnosticDatabase.execute(
      'DELETE FROM diagnostic_events WHERE recorded_at < ?',
      [cutoff],
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
      final existing = blobRef(idKey, epoch, hash);
      if (existing != null) {
        file = blobFile(idKey, epoch, hash);
        if (!file.existsSync()) {
          // The ref survived but its file did not. Rewrite the file only; the
          // ref, `uploaded_at` and `bytes_used` already account for it, so
          // quota is not charged again.
          if (body.length != existing.size || rawBodyHash(body) != hash) {
            throw const StoreBlobMismatch();
          }
          file.parent.createSync(recursive: true);
          temporary = _temporaryBlobFile(file);
          temporary.writeAsBytesSync(body, flush: true);
          temporary.renameSync(file.path);
        }
        _database.execute('ROLLBACK');
        inTransaction = false;
        return false;
      }
      final current = lookup(idKey);
      if (current == null) throw const StoreEpochMismatch();
      final count =
          _database.select(
                'SELECT COUNT(*) AS count FROM blob_refs WHERE id_key = ?',
                [idKey],
              ).single['count']
              as int;
      final aggregateBytes =
          _database.select(
                'SELECT COALESCE(SUM(size), 0) AS bytes FROM blob_refs '
                'WHERE id_key = ?',
                [idKey],
              ).single['bytes']
              as int;
      final pending = _pendingDeletionUsage(
        idKey,
        excludingEpoch: epoch,
        excludingHash: hash,
      );
      final bytesUsed =
          max(current.bytesUsed, aggregateBytes) +
          pending.bytes +
          _manifestBytes(idKey);
      if (count + pending.blobs >= quotaLimits.maxBlobs) {
        throw const StoreQuotaExceeded('blob quota exhausted');
      }
      if (bytesUsed > quotaLimits.maxBytes - body.length) {
        throw const StoreQuotaExceeded('byte quota exhausted');
      }
      file = blobFile(idKey, epoch, hash);
      file.parent.createSync(recursive: true);
      temporary = _temporaryBlobFile(file);
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

  /// Stores a batch of blobs whose hashes the caller has verified, in one
  /// transaction with one quota computation (spec §5.2, `PUT /v1/blobs/batch`),
  /// and returns the status a single `PUT` would have answered for each, in
  /// order: `201` stored, `200` already held (its file rewritten if it was
  /// lost, as [putBlob] does), `400` a lost file whose bytes do not match the
  /// recorded size, or `507` past the store's quota. Once one blob is past the
  /// quota every later new blob is too, so what a batch stores is a prefix of
  /// its new blobs, as a run of single uploads would have.
  ///
  /// Throws [StoreEpochMismatch] when the store is gone.
  List<int> putBlobs({
    required String idKey,
    required String epoch,
    required List<({String hash, Uint8List body})> blobs,
  }) {
    final statuses = <int>[];
    final written = <File>[];
    final temporaries = <File>[];
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final current = lookup(idKey);
      if (current == null) throw const StoreEpochMismatch();
      var count =
          _database.select(
                'SELECT COUNT(*) AS count FROM blob_refs WHERE id_key = ?',
                [idKey],
              ).single['count']
              as int;
      final aggregateBytes =
          _database.select(
                'SELECT COALESCE(SUM(size), 0) AS bytes FROM blob_refs '
                'WHERE id_key = ?',
                [idKey],
              ).single['bytes']
              as int;
      // Live bytes, without pending deletions: those depend on which blob is
      // asking, since a single PUT leaves out its own hash's pending file.
      var bytesUsed =
          max(current.bytesUsed, aggregateBytes) + _manifestBytes(idKey);
      // With nothing pending, which is the usual case, every blob's pending
      // usage is zero and is computed once. Otherwise each new blob's is
      // computed as its own PUT would compute it, against the rows this
      // batch has already inserted.
      final nothingPending = _pendingDeletionUsage(
        idKey,
        excludingEpoch: epoch,
      ).isEmpty;
      var full = false;
      var added = 0;
      final now = _clock().millisecondsSinceEpoch ~/ 1000;
      for (final (:hash, :body) in blobs) {
        final file = blobFile(idKey, epoch, hash);
        final existing = blobRef(idKey, epoch, hash);
        if (existing != null) {
          if (!file.existsSync()) {
            if (body.length != existing.size) {
              statuses.add(400);
              continue;
            }
            file.parent.createSync(recursive: true);
            final temporary = _temporaryBlobFile(file);
            temporaries.add(temporary);
            temporary.writeAsBytesSync(body, flush: true);
            temporary.renameSync(file.path);
          }
          statuses.add(200);
          continue;
        }
        // Once one new blob is refused, every later one is too, even one
        // small enough to fit: the client stops at the first refusal anyway,
        // and what a batch stores stays a prefix of what it carried.
        if (full) {
          statuses.add(507);
          continue;
        }
        final pending = nothingPending
            ? const _DeletionUsage()
            : _pendingDeletionUsage(
                idKey,
                excludingEpoch: epoch,
                excludingHash: hash,
              );
        if (count + pending.blobs >= quotaLimits.maxBlobs ||
            bytesUsed + pending.bytes > quotaLimits.maxBytes - body.length) {
          full = true;
          statuses.add(507);
          continue;
        }
        file.parent.createSync(recursive: true);
        final temporary = _temporaryBlobFile(file);
        temporaries.add(temporary);
        temporary.writeAsBytesSync(body, flush: true);
        temporary.renameSync(file.path);
        written.add(file);
        _database.execute(
          'INSERT INTO blob_refs (id_key, epoch, hash, size, uploaded_at) '
          'VALUES (?, ?, ?, ?, ?)',
          [idKey, epoch, hash, body.length, now],
        );
        count++;
        bytesUsed += body.length;
        added += body.length;
        statuses.add(201);
      }
      _database.execute(
        'UPDATE stores SET bytes_used = bytes_used + ?, last_seen = ? '
        'WHERE id_key = ? AND epoch = ?',
        [added, now, idKey, epoch],
      );
      _database.execute('COMMIT');
      inTransaction = false;
      return statuses;
    } catch (error) {
      try {
        if (inTransaction) _database.execute('ROLLBACK');
      } finally {
        for (final file in written) {
          if (file.existsSync()) file.deleteSync();
        }
        for (final temporary in temporaries) {
          if (temporary.existsSync()) temporary.deleteSync();
        }
      }
      rethrow;
    }
  }

  File _temporaryBlobFile(File file) {
    final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
    return File(
      '${file.path}.$pid.${_clock().microsecondsSinceEpoch}.$nonce.tmp',
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

  sqlite3.Database get breakGlassDatabase => _breakGlassDatabase;

  sqlite3.Database get database => _database;

  sqlite3.Database get diagnosticDatabase => _diagnosticDatabase;

  void deleteStore(String idKey, {bool retryGlobal = true}) {
    late final String epoch;
    late final Set<String> epochs;
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
      epochs = <String>{
        epoch,
        for (final row in _database.select(
          'SELECT epoch FROM manifests WHERE id_key = ? '
          'UNION SELECT epoch FROM blob_refs WHERE id_key = ? '
          'UNION SELECT epoch FROM blob_deletion_jobs WHERE id_key = ? '
          'UNION SELECT epoch FROM deletion_jobs WHERE id_key = ?',
          [idKey, idKey, idKey, idKey],
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
      _database.execute('DELETE FROM manifest_refs WHERE id_key = ?', [idKey]);
      _database.execute('DELETE FROM indexed_manifests WHERE id_key = ?', [
        idKey,
      ]);
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
    for (final queuedEpoch in epochs) {
      try {
        _retryPendingDirectory(idKey, queuedEpoch);
      } on Object catch (error) {
        stderr.writeln(
          'Athenaeum post-delete directory cleanup failed '
          '(${error.runtimeType})',
        );
      }
    }
    if (retryGlobal) {
      try {
        retryPendingDeletions();
      } on Object catch (error) {
        stderr.writeln(
          'Athenaeum post-delete cleanup retry failed '
          '(${error.runtimeType})',
        );
      }
    }
  }

  void retryPendingDeletions({
    int maxJobs = maxPendingDeletionRetriesPerRequest,
    bool reportFailures = false,
    Duration? maxDuration,
  }) {
    final started = _elapsed();
    bool budgetSpent() =>
        maxDuration != null && _elapsed() - started >= maxDuration;
    final rows = _database.select(
      'SELECT id_key, epoch FROM deletion_jobs '
      'ORDER BY queued_at, rowid LIMIT ?',
      [maxJobs],
    );
    var ran = 0;
    for (final row in rows) {
      if (ran > 0 && budgetSpent()) return;
      final idKey = row['id_key'] as String;
      final epoch = row['epoch'] as String;
      _retryPendingDirectory(idKey, epoch, reportFailure: reportFailures);
      ran++;
    }
    if (ran > 0 && budgetSpent()) return;
    // maxJobs caps the whole call, not each queue.
    if (ran >= maxJobs) return;
    retryPendingBlobDeletions(
      maxJobs: maxJobs - ran,
      reportFailures: reportFailures,
      budgetSpent: maxDuration == null ? null : budgetSpent,
      jobsAlreadyRun: ran,
    );
  }

  void _retryPendingDirectory(
    String idKey,
    String epoch, {
    bool reportFailure = false,
  }) {
    var inTransaction = false;
    try {
      _database.execute('BEGIN IMMEDIATE');
      inTransaction = true;
      final refs = _database.select(
        'SELECT 1 FROM manifests WHERE id_key = ? AND epoch = ? '
        'UNION SELECT 1 FROM blob_refs WHERE id_key = ? AND epoch = ? LIMIT 1',
        [idKey, epoch, idKey, epoch],
      );
      if (refs.isNotEmpty) {
        _database.execute('COMMIT');
        inTransaction = false;
        _database.execute(
          'UPDATE deletion_jobs SET queued_at = ('
          'SELECT COALESCE(MAX(queued_at), -1) + 1 FROM deletion_jobs'
          ') WHERE id_key = ? AND epoch = ?',
          [idKey, epoch],
        );
        return;
      }
      try {
        _deleteDirectory(Directory(p.join(blobDirectory.path, idKey, epoch)));
      } on FileSystemException catch (error) {
        _database.execute('ROLLBACK');
        inTransaction = false;
        if (reportFailure) {
          _reportOperationalFailure('deletion_retry', error);
        }
        _database.execute(
          'UPDATE deletion_jobs SET queued_at = ('
          'SELECT COALESCE(MAX(queued_at), -1) + 1 FROM deletion_jobs'
          ') WHERE id_key = ? AND epoch = ?',
          [idKey, epoch],
        );
        return;
      }
      _database.execute(
        'DELETE FROM blob_deletion_jobs WHERE id_key = ? AND epoch = ?',
        [idKey, epoch],
      );
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

  void retryPendingBlobDeletions({
    int maxJobs = maxPendingDeletionRetriesPerRequest,
    bool reportFailures = false,
    bool Function()? budgetSpent,
    int jobsAlreadyRun = 0,
  }) {
    var ran = jobsAlreadyRun;
    final rows = _database.select(
      'SELECT id_key, epoch, hash FROM blob_deletion_jobs '
      'ORDER BY queued_at, rowid LIMIT ?',
      [maxJobs],
    );
    for (final row in rows) {
      if (ran > 0 && budgetSpent != null && budgetSpent()) return;
      ran++;
      final idKey = row['id_key'] as String;
      final epoch = row['epoch'] as String;
      final hash = row['hash'] as String;
      _validateHash(hash);
      var inTransaction = false;
      try {
        _database.execute('BEGIN IMMEDIATE');
        inTransaction = true;
        final currentRef = blobRef(idKey, epoch, hash);
        try {
          if (currentRef == null) {
            final file = blobFile(idKey, epoch, hash);
            if (file.existsSync()) _deleteFile(file);
          }
          for (final file in _temporaryBlobFiles(idKey, epoch, hash)) {
            _deleteFile(file);
          }
        } on FileSystemException catch (error) {
          _database.execute('ROLLBACK');
          inTransaction = false;
          if (reportFailures) {
            _reportOperationalFailure('blob_deletion_retry', error);
          }
          _database.execute(
            'UPDATE blob_deletion_jobs SET queued_at = ('
            'SELECT COALESCE(MAX(queued_at), -1) + 1 '
            'FROM blob_deletion_jobs'
            ') WHERE id_key = ? AND epoch = ? AND hash = ?',
            [idKey, epoch, hash],
          );
          continue;
        }
        _database.execute(
          'DELETE FROM blob_deletion_jobs '
          'WHERE id_key = ? AND epoch = ? AND hash = ?',
          [idKey, epoch, hash],
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

  static Duration Function() _monotonicElapsed() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  Iterable<File> _temporaryBlobFiles(String idKey, String epoch, String hash) {
    final directory = blobFile(idKey, epoch, hash).parent;
    if (!directory.existsSync()) return const <File>[];
    return directory.listSync().whereType<File>().where((file) {
      final match = _temporaryBlobPattern.firstMatch(p.basename(file.path));
      return match?.group(1) == hash;
    });
  }

  _DeletionUsage _directoryUsage(
    Directory directory, {
    required Set<String> accountedPaths,
  }) {
    if (!directory.existsSync()) return const _DeletionUsage();
    var usage = const _DeletionUsage();
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File && accountedPaths.add(entity.path)) {
        usage = usage.add(bytes: entity.lengthSync(), blobs: 1);
      }
    }
    return usage;
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

/// The store row is gone: deleted, or reaped by a sweep, after the caller's own
/// `lookup`. Distinct from [StoreEpochMismatch], which a manifest write raises
/// only for a store that exists under a different epoch (deleted and recreated).
/// Raised by `manifestUploadPreflight` and `putManifest`; the blob and deletion
/// paths still signal a missing row with [StoreEpochMismatch].
class StoreMissing implements Exception {
  const StoreMissing();
}

/// A repair upload whose body does not match the stored blob's size or hash.
class StoreBlobMismatch implements Exception {
  const StoreBlobMismatch();
}

class StoreQuotaExceeded implements Exception {
  const StoreQuotaExceeded(this.message);

  final String message;
}

class _DeletionUsage {
  const _DeletionUsage({this.blobs = 0, this.bytes = 0});

  final int blobs;
  final int bytes;

  bool get isEmpty => blobs == 0 && bytes == 0;

  _DeletionUsage add({_DeletionUsage? usage, int blobs = 0, int bytes = 0}) =>
      _DeletionUsage(
        blobs: this.blobs + (usage?.blobs ?? blobs),
        bytes: this.bytes + (usage?.bytes ?? bytes),
      );
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
    required this.maxBlobs,
    required this.maxBytes,
  });

  final String epoch;
  final List<String> devices;
  final int blobs;
  final int bytes;
  final int maxBlobs;
  final int maxBytes;

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'devices': devices,
    'quota': {
      'blobs': blobs,
      'bytes': bytes,
      'maxBlobs': maxBlobs,
      'maxBytes': maxBytes,
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
