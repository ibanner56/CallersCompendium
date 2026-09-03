class AthenaeumTableSchema {
  const AthenaeumTableSchema(this.name, this.columns, {this.tableConstraint});

  final String name;
  final Map<String, String> columns;
  final String? tableConstraint;

  String createSql() {
    final definitions = [
      for (final entry in columns.entries) '${entry.key} ${entry.value}',
    ];
    if (tableConstraint != null) definitions.add(tableConstraint!);
    return '''
CREATE TABLE IF NOT EXISTS $name (
  ${definitions.join(',\n  ')}
)
''';
  }
}

const List<AthenaeumTableSchema> athenaeumTableSchemas = [
  AthenaeumTableSchema('stores', {
    'id_key': 'TEXT PRIMARY KEY',
    'epoch': 'TEXT NOT NULL',
    'created_at': 'INTEGER NOT NULL',
    'last_seen': 'INTEGER NOT NULL',
    'bytes_used': 'INTEGER NOT NULL',
  }),
  AthenaeumTableSchema('manifests', {
    'id_key': 'TEXT NOT NULL',
    'epoch': 'TEXT NOT NULL',
    'device_id': 'TEXT NOT NULL',
    'etag': 'TEXT NOT NULL',
    'written_at': 'INTEGER NOT NULL',
    'body': 'BLOB NOT NULL',
  }, tableConstraint: 'PRIMARY KEY (id_key, epoch, device_id)'),
  AthenaeumTableSchema('blob_refs', {
    'id_key': 'TEXT NOT NULL',
    'epoch': 'TEXT NOT NULL',
    'hash': 'TEXT NOT NULL',
    'size': 'INTEGER NOT NULL',
    'uploaded_at': 'INTEGER NOT NULL',
  }, tableConstraint: 'PRIMARY KEY (id_key, epoch, hash)'),
  AthenaeumTableSchema('deletion_jobs', {
    'id_key': 'TEXT NOT NULL',
    'epoch': 'TEXT NOT NULL',
    'queued_at': 'INTEGER NOT NULL',
  }, tableConstraint: 'PRIMARY KEY (id_key, epoch)'),
];

const List<AthenaeumTableSchema> breakGlassTableSchemas = [
  AthenaeumTableSchema('break_glass_access', {
    'id_key': 'TEXT',
    'accessed_at': 'INTEGER NOT NULL',
  }),
];

List<String> get serverSqliteFields => [
  for (final table in athenaeumTableSchemas)
    for (final column in table.columns.keys) '${table.name}.$column',
];

List<String> get serverBreakGlassSqliteFields => [
  for (final table in breakGlassTableSchemas)
    for (final column in table.columns.keys) '${table.name}.$column',
];

const List<String> serverFilesystemFields = ['blob_files.body'];
