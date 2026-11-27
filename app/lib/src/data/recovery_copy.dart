import 'dart:io';

import 'package:compendium_core/compendium_core.dart'
    show EgressClass, classifySettingsKey, fieldClassifications;
import 'package:sqlite3/sqlite3.dart' as sql;

import 'backup_service.dart' show isBackupEligibleSettingKey;

/// A copy of a library that is too old for this version to open (below the
/// schema floor), made so the caller can take it off a phone or tablet and
/// update it with the bridge release on a computer (pre-release audit finding
/// F-01; route in `docs/user/faq.md`, "My data is too old to open on my phone
/// or tablet").
///
/// The live database, and the raw snapshot "Back up + reset" writes, hold data
/// the privacy registry says must never leave the device by any route
/// ([EgressClass.deviceScoped]: unsaved editor drafts, Device Sync state,
/// per-installation markers) or may travel only to the sync store
/// ([EgressClass.protocolIdentifier], [EgressClass.storeAddress]). The copy
/// keeps what a backup file may carry and nothing else (maintainer decision,
/// 2026-11-27, decision-sheet question 39):
///
/// - a settings row survives only if the registry classifies its key
///   [EgressClass.shareable], or [EgressClass.deviceLocal] and a backup carries
///   it ([isBackupEligibleSettingKey]). A key the registry does not know is
///   dropped, so the rule fails closed;
/// - every table with a column the registry classes as anything other than
///   shareable, deviceLocal or derived (the Device Sync tables and the
///   normalisation repair log) is emptied, as is any table with a column the
///   registry does not know, except the internal tables of a full-text index;
/// - the file is then rebuilt with `VACUUM`, so deleted rows leave nothing
///   behind in free pages, and checked with `PRAGMA integrity_check`.
///
/// Tables are emptied rather than dropped: the bridge release (v0.10.0-beta)
/// adds columns to `baseline_state` when it opens a v39 file, which fails if
/// the table is gone.
///
/// [source] is never written: the copy is taken with `VACUUM INTO`, which reads
/// the committed state, write-ahead log included.
///
/// Returns [destination]. On any failure the partial copy is deleted and the
/// error rethrown; nothing is shared that was not fully scrubbed.
Future<File> writeRecoveryCopy({
  required File source,
  required File destination,
}) async {
  await destination.parent.create(recursive: true);
  _deleteCopy(destination);
  try {
    final src = sql.sqlite3.open(source.path);
    try {
      src.execute('VACUUM INTO ?', [destination.path]);
    } finally {
      src.dispose();
    }
    final db = sql.sqlite3.open(destination.path);
    try {
      _scrub(db);
    } finally {
      db.dispose();
    }
    return destination;
  } on Object {
    // diagnostics: silent — rethrown; the caller reports the failure.
    _deleteCopy(destination);
    rethrow;
  }
}

/// Whether a settings row with [key] stays in a recovery copy. See
/// [writeRecoveryCopy] for the rule.
bool keepSettingInRecoveryCopy(String key) {
  final classification = classifySettingsKey(key);
  if (classification == null) return false;
  switch (classification.egress) {
    case EgressClass.shareable:
      return true;
    case EgressClass.deviceLocal:
      return isBackupEligibleSettingKey(key);
    case EgressClass.deviceScoped:
    case EgressClass.derived:
    case EgressClass.protocolIdentifier:
    case EgressClass.storeAddress:
      return false;
  }
}

/// The key/value settings table, whose rows [keepSettingInRecoveryCopy] judges
/// one key at a time.
const String _settingsTable = 'settings';

/// The egress classes a recovery copy may carry in a table column.
const Set<EgressClass> _keptColumnClasses = {
  EgressClass.shareable,
  EgressClass.deviceLocal,
  EgressClass.derived,
};

/// Suffixes SQLite's FTS5 gives the internal tables behind a full-text index.
const List<String> _fts5ShadowSuffixes = [
  '_config',
  '_content',
  '_data',
  '_docsize',
  '_idx',
];

void _scrub(sql.Database db) {
  // A copy shared on its own must not need a write-ahead log beside it.
  db.execute('PRAGMA journal_mode = DELETE');
  db.execute('PRAGMA secure_delete = ON');

  final tables = <String>[];
  final virtualTables = <String>{};
  for (final row in db.select(
    "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'",
  )) {
    final name = row['name'] as String;
    tables.add(name);
    final createSql = (row['sql'] as String?) ?? '';
    if (createSql.toUpperCase().startsWith('CREATE VIRTUAL TABLE')) {
      virtualTables.add(name);
    }
  }

  db.execute('BEGIN');
  try {
    for (final table in tables) {
      if (_isFts5Shadow(table, virtualTables)) continue;
      if (table == _settingsTable) {
        _scrubSettings(db);
        continue;
      }
      if (!_tableMayTravel(db, table)) {
        db.execute('DELETE FROM "${table.replaceAll('"', '""')}"');
      }
    }
    db.execute('COMMIT');
  } on Object {
    // diagnostics: silent — rethrown after the rollback.
    db.execute('ROLLBACK');
    rethrow;
  }

  db.execute('VACUUM');
  final check = db.select('PRAGMA integrity_check');
  final result = check.isEmpty ? null : check.first.values.first;
  if (check.length != 1 || result != 'ok') {
    throw StateError('Recovery copy failed its integrity check.');
  }
}

bool _isFts5Shadow(String table, Set<String> virtualTables) {
  for (final vtab in virtualTables) {
    for (final suffix in _fts5ShadowSuffixes) {
      if (table == '$vtab$suffix') return true;
    }
  }
  return false;
}

/// Whether every column of [table] is one a recovery copy may carry. A column
/// the registry does not classify fails closed.
bool _tableMayTravel(sql.Database db, String table) {
  final columns = db.select('SELECT name FROM pragma_table_info(?)', [table]);
  if (columns.isEmpty) return false;
  for (final column in columns) {
    final classification = fieldClassifications['$table.${column['name']}'];
    if (classification == null) return false;
    if (!_keptColumnClasses.contains(classification.egress)) return false;
  }
  return true;
}

void _scrubSettings(sql.Database db) {
  final keys = [
    for (final row in db.select('SELECT key FROM $_settingsTable'))
      row['key'] as String,
  ];
  for (final key in keys) {
    if (!keepSettingInRecoveryCopy(key)) {
      db.execute('DELETE FROM $_settingsTable WHERE key = ?', [key]);
    }
  }
}

void _deleteCopy(File file) {
  for (final path in [file.path, '${file.path}-journal', '${file.path}-wal']) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // diagnostics: silent — a leftover partial copy is overwritten next time.
    }
  }
}
