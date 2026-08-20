/// Persisted, app-wide configuration for the program matrix's columns
/// (issue #935).
///
/// The matrix's built-in columns are **derived, present-only** from the
/// taxonomy at build time (see [buildProgramMatrix]); there is no stored column
/// list to edit. This config layers user intent — hide, reorder, rename, and
/// (from Phase 4/5) parameterized / compound custom columns — over that derived
/// output, keyed by the stable column-id strings the matrix already uses
/// (`swing:partner`, `hey:full`, `do_si_do`, `customMove`, …). An **empty**
/// config (every collection empty) is the canonical "today's defaults": it must
/// reproduce the matrix exactly as it built before this config existed.
///
/// ## Phase boundaries
///
/// This is the Phase 2 model. [buildProgramMatrix] honours [hidden] and [order]
/// for built-in columns, and [matrixColumnLabel] honours [renames]. The
/// [parameterized] and [compound] lists are defined and round-trip through the
/// codec, but **do not yet affect figure routing** — Phase 4 adds parameterized
/// matching (replacing built-in membership) and Phase 5 adds compound sequence
/// matching (additive). Their ids are treated as inert if they appear in
/// [order] / [hidden] before those phases land.
///
/// ## Id namespacing (a security/robustness boundary)
///
/// A custom column's id is an **opaque, namespaced** token — `param:<uuid>` or
/// `compound:<uuid>` — so it can never collide with a built-in / split / alias /
/// [customMove] id, no matter how the taxonomy grows. The codec enforces the
/// namespace prefix and cross-list uniqueness on decode, rejecting anything that
/// could shadow a built-in column or another custom column. This is validated at
/// the trust boundary (a restored backup blob is untrusted input — see
/// `backup_settings_schema.dart`): malformed input is rejected, never coerced.
library;

/// Namespace prefix for a parameterized custom column id.
const String parameterizedColumnIdPrefix = 'param:';

/// Namespace prefix for a compound custom column id.
const String compoundColumnIdPrefix = 'compound:';

/// The current [MatrixColumnConfig] JSON schema version. Bumped only on a
/// breaking shape change; [MatrixColumnConfig.decode] tolerates older/newer
/// minor differences (unknown fields ignored, dangling ids kept inert).
const int matrixColumnConfigSchemaVersion = 1;

/// Thrown by [MatrixColumnConfig.decode] when its input is structurally
/// malformed (wrong container kind, wrong value types, a mis-namespaced or
/// duplicate custom id). The app layer catches this — via
/// [MatrixColumnConfig.tryDecode] — and falls back to the empty default rather
/// than letting a corrupt persisted/restored blob abort startup.
class MatrixColumnConfigFormatException implements FormatException {
  const MatrixColumnConfigFormatException(this.message, [this.source]);

  @override
  final String message;

  @override
  final dynamic source;

  @override
  int get offset => -1;

  @override
  String toString() => 'MatrixColumnConfigFormatException: $message';
}

/// A user-defined column that captures a specific figure — a single canonical
/// [baseMove] whose effective params satisfy every entry in [params] (exact
/// equality; Phase 4 §D3). Phase 2 defines and round-trips it; matching /
/// routing is Phase 4.
class ParameterizedColumn {
  const ParameterizedColumn({
    required this.id,
    required this.baseMove,
    this.params = const {},
  });

  /// Opaque, namespaced id (`param:<uuid>`). Never a built-in column id.
  final String id;

  /// The canonical move id this column matches (e.g. `swing`).
  final String baseMove;

  /// Effective-param constraints, all of which a figure must satisfy to match.
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => {
    'id': id,
    'baseMove': baseMove,
    'params': params,
  };

  static ParameterizedColumn _fromJson(Object? raw) {
    if (raw is! Map) {
      throw const MatrixColumnConfigFormatException(
        'parameterized entry must be an object',
      );
    }
    final id = raw['id'];
    final baseMove = raw['baseMove'];
    if (id is! String || !id.startsWith(parameterizedColumnIdPrefix)) {
      throw MatrixColumnConfigFormatException(
        'parameterized id must be a "$parameterizedColumnIdPrefix…" string',
        id,
      );
    }
    if (baseMove is! String || baseMove.isEmpty) {
      throw const MatrixColumnConfigFormatException(
        'parameterized baseMove must be a non-empty string',
      );
    }
    return ParameterizedColumn(
      id: id,
      baseMove: baseMove,
      params: _stringKeyedMap(raw['params']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ParameterizedColumn &&
      other.id == id &&
      other.baseMove == baseMove &&
      _mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(id, baseMove, _mapHash(params));
}

/// One step of a [CompoundColumn]: a single figure match by canonical [move]
/// and exact effective-[params] (Phase 5 §D3). Phase 2 defines and round-trips
/// it; matching is Phase 5.
class StepMatcher {
  const StepMatcher({required this.move, this.params = const {}});

  final String move;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => {'move': move, 'params': params};

  static StepMatcher _fromJson(Object? raw) {
    if (raw is! Map) {
      throw const MatrixColumnConfigFormatException(
        'compound step must be an object',
      );
    }
    final move = raw['move'];
    if (move is! String || move.isEmpty) {
      throw const MatrixColumnConfigFormatException(
        'compound step move must be a non-empty string',
      );
    }
    return StepMatcher(move: move, params: _stringKeyedMap(raw['params']));
  }

  @override
  bool operator ==(Object other) =>
      other is StepMatcher &&
      other.move == move &&
      _mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(move, _mapHash(params));
}

/// A user-defined column that flags a **contiguous figure sequence** within a
/// dance (Phase 5 §D2). Phase 2 defines and round-trips it; matching is Phase 5.
class CompoundColumn {
  const CompoundColumn({required this.id, this.steps = const []});

  /// Opaque, namespaced id (`compound:<uuid>`). Never a built-in column id.
  final String id;

  /// The ordered, strictly-adjacent run of figure matchers.
  final List<StepMatcher> steps;

  Map<String, Object?> toJson() => {
    'id': id,
    'steps': [for (final s in steps) s.toJson()],
  };

  static CompoundColumn _fromJson(Object? raw) {
    if (raw is! Map) {
      throw const MatrixColumnConfigFormatException(
        'compound entry must be an object',
      );
    }
    final id = raw['id'];
    if (id is! String || !id.startsWith(compoundColumnIdPrefix)) {
      throw MatrixColumnConfigFormatException(
        'compound id must be a "$compoundColumnIdPrefix…" string',
        id,
      );
    }
    final rawSteps = raw['steps'];
    if (rawSteps is! List) {
      throw const MatrixColumnConfigFormatException(
        'compound steps must be a list',
      );
    }
    return CompoundColumn(
      id: id,
      steps: [for (final s in rawSteps) StepMatcher._fromJson(s)],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CompoundColumn &&
      other.id == id &&
      _listEquals(other.steps, steps);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(steps));
}

/// App-wide program-matrix column configuration. Immutable; an empty instance
/// ([MatrixColumnConfig.empty]) is today's defaults.
class MatrixColumnConfig {
  const MatrixColumnConfig({
    this.schemaVersion = matrixColumnConfigSchemaVersion,
    this.order = const [],
    this.hidden = const {},
    this.renames = const {},
    this.parameterized = const [],
    this.compound = const [],
  });

  /// The canonical "today's defaults" — every collection empty. A matrix built
  /// with this must be identical, field-by-field, to one built with no config.
  static const MatrixColumnConfig empty = MatrixColumnConfig();

  /// JSON schema version this config was written under. Reserved for future
  /// migrations; see [matrixColumnConfigSchemaVersion].
  final int schemaVersion;

  /// A single ordered list of column ids (built-in and custom ids may
  /// interleave). Ids present in the built matrix but absent from [order] keep
  /// their natural derived order **after** the ordered ids. Ids listed here but
  /// not present in a given matrix are inert.
  final List<String> order;

  /// Column ids removed from **display** (analysis is untouched). Inert if an
  /// id is not present in a given matrix.
  final Set<String> hidden;

  /// Column id → label override, applied in [matrixColumnLabel]. Custom-column
  /// labels are also stored here, under the custom id.
  final Map<String, String> renames;

  /// User parameterized columns (Phase 4 routing).
  final List<ParameterizedColumn> parameterized;

  /// User compound columns (Phase 5 matching).
  final List<CompoundColumn> compound;

  /// Whether this is the defaults (empty) config — a cheap identity the matrix
  /// builder uses to skip all config work on the overwhelmingly common path.
  bool get isEmpty =>
      order.isEmpty &&
      hidden.isEmpty &&
      renames.isEmpty &&
      parameterized.isEmpty &&
      compound.isEmpty;

  MatrixColumnConfig copyWith({
    List<String>? order,
    Set<String>? hidden,
    Map<String, String>? renames,
    List<ParameterizedColumn>? parameterized,
    List<CompoundColumn>? compound,
  }) => MatrixColumnConfig(
    schemaVersion: schemaVersion,
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    renames: renames ?? this.renames,
    parameterized: parameterized ?? this.parameterized,
    compound: compound ?? this.compound,
  );

  /// The set of every custom column id declared here (parameterized + compound).
  Set<String> get customColumnIds => {
    for (final p in parameterized) p.id,
    for (final c in compound) c.id,
  };

  /// JSON-encodable map. [hidden] is emitted as a sorted list for deterministic
  /// output (JSON has no set type).
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'order': order,
    'hidden': hidden.toList()..sort(),
    'renames': renames,
    'parameterized': [for (final p in parameterized) p.toJson()],
    'compound': [for (final c in compound) c.toJson()],
  };

  /// Decodes [raw] (a JSON value as returned by `SettingsRepository.get`).
  ///
  /// `null` decodes to [empty]. A well-formed map decodes to a config, tolerating
  /// unknown/dangling built-in ids (kept inert). **Throws**
  /// [MatrixColumnConfigFormatException] for structurally malformed input
  /// (wrong types, mis-namespaced or duplicate custom ids) — callers that must
  /// not throw use [tryDecode].
  static MatrixColumnConfig decode(Object? raw) {
    if (raw == null) return empty;
    if (raw is! Map) {
      throw MatrixColumnConfigFormatException('config must be an object', raw);
    }

    final rawVersion = raw['schemaVersion'];
    final version = switch (rawVersion) {
      null => matrixColumnConfigSchemaVersion,
      final int v => v,
      _ => throw const MatrixColumnConfigFormatException(
        'schemaVersion must be an integer',
      ),
    };

    final order = _stringList(raw['order'], 'order');
    final hidden = _stringList(raw['hidden'], 'hidden').toSet();
    final renames = _stringStringMap(raw['renames']);

    final parameterized = _decodeList(
      raw['parameterized'],
      'parameterized',
      ParameterizedColumn._fromJson,
    );
    final compound = _decodeList(
      raw['compound'],
      'compound',
      CompoundColumn._fromJson,
    );

    // Uniqueness + namespacing across all custom ids: a custom id must never
    // collide with another custom id (which would make one unreachable) — the
    // namespace prefix is already enforced per-entry above.
    final seen = <String>{};
    for (final id in [
      for (final p in parameterized) p.id,
      for (final c in compound) c.id,
    ]) {
      if (!seen.add(id)) {
        throw MatrixColumnConfigFormatException('duplicate custom id', id);
      }
    }

    return MatrixColumnConfig(
      schemaVersion: version,
      order: order,
      hidden: hidden,
      renames: renames,
      parameterized: parameterized,
      compound: compound,
    );
  }

  /// Like [decode] but returns `null` instead of throwing on malformed input.
  /// Used at trust boundaries (persisted-config load, backup restore) where a
  /// corrupt blob must fall back to the default rather than crash.
  static MatrixColumnConfig? tryDecode(Object? raw) {
    try {
      return decode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MatrixColumnConfig &&
      other.schemaVersion == schemaVersion &&
      _listEquals(other.order, order) &&
      _setEquals(other.hidden, hidden) &&
      _mapEquals(other.renames, renames) &&
      _listEquals(other.parameterized, parameterized) &&
      _listEquals(other.compound, compound);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    Object.hashAll(order),
    Object.hashAllUnordered(hidden),
    _mapHash(renames),
    Object.hashAll(parameterized),
    Object.hashAll(compound),
  );
}

/// A custom (parameterized/compound) column paired with the label it currently
/// displays — the input the "restore removed defaults" reset needs to append
/// custom columns in label order. [label] is the column's effective header
/// (its rename if set, else its Phase 4/5 default), resolved by the caller.
typedef CustomColumnLabel = ({String id, String label});

/// Computes the `order` list produced by the **"restore removed defaults"**
/// reset (issue #935, decision D4): the built-in columns return to their
/// catalog order, and every custom column is appended after them, sorted by its
/// displayed [label] using case-insensitive Unicode code-point ordering (with
/// the opaque id as a stable final tie-break). Renames and the custom columns
/// themselves are preserved by the caller — this only rebuilds ordering; it
/// never drops a column.
///
/// Pure and taxonomy-free so it can be unit-tested directly. [catalogOrder] is
/// the built-in column ids in [builtInColumnCatalog] order; [customs] are the
/// config's parameterized+compound columns with their displayed labels.
List<String> restoreRemovedDefaultsOrder({
  required List<String> catalogOrder,
  required List<CustomColumnLabel> customs,
}) {
  final sortedCustoms = [...customs]
    ..sort((a, b) {
      final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
      if (byLabel != 0) return byLabel;
      return a.id.compareTo(b.id);
    });
  return [...catalogOrder, for (final c in sortedCustoms) c.id];
}

List<String> _stringList(Object? raw, String field) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw MatrixColumnConfigFormatException('$field must be a list', raw);
  }
  return [
    for (final e in raw)
      if (e is String)
        e
      else
        throw MatrixColumnConfigFormatException(
          '$field entries must be strings',
          e,
        ),
  ];
}

Map<String, String> _stringStringMap(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw MatrixColumnConfigFormatException('renames must be an object', raw);
  }
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is! String || v is! String) {
      throw const MatrixColumnConfigFormatException(
        'renames keys and values must be strings',
      );
    }
    out[k] = v;
  });
  return out;
}

Map<String, Object?> _stringKeyedMap(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw MatrixColumnConfigFormatException('params must be an object', raw);
  }
  final out = <String, Object?>{};
  raw.forEach((k, v) {
    if (k is! String) {
      throw const MatrixColumnConfigFormatException(
        'param keys must be strings',
      );
    }
    out[k] = v;
  });
  return out;
}

List<T> _decodeList<T>(Object? raw, String field, T Function(Object?) item) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw MatrixColumnConfigFormatException('$field must be a list', raw);
  }
  return [for (final e in raw) item(e)];
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered([
  for (final e in map.entries) Object.hash(e.key, e.value),
]);
