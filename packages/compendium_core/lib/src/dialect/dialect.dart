import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../validation/validation.dart';

/// A role display term: singular plus plural (plural derived with a basic
/// y→ies / +s rule unless given explicitly — "Lady" → "Ladies").
@immutable
class RoleTerm {
  // ignore: prefer_initializing_formals
  const RoleTerm(this.singular, {String? plural}) : _plural = plural;

  final String singular;
  final String? _plural;
  String get plural {
    if (_plural != null) return _plural;
    if (singular.endsWith('y')) {
      return '${singular.substring(0, singular.length - 1)}ies';
    }
    return '${singular}s';
  }

  /// JSON form: always writes the resolved [plural] so the exact display
  /// pluralization round-trips (independent of the derivation rule).
  Map<String, Object?> toJson() => {'singular': singular, 'plural': plural};

  /// Parses a [RoleTerm] from [toJson] output. A missing/blank `plural`
  /// falls back to the derived plural.
  static RoleTerm fromJson(Map<String, Object?> json) {
    final singular = (json['singular'] as String?) ?? '';
    final plural = json['plural'] as String?;
    return RoleTerm(
      singular,
      plural: (plural != null && plural.isNotEmpty) ? plural : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoleTerm && other.singular == singular && other.plural == plural;

  @override
  int get hashCode => Object.hash(singular, plural);
}

const MapEquality<Object?, Object?> _mapEq = MapEquality<Object?, Object?>();
const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// A user-level presentation mapping applied at render time. Storage is
/// always canonical; dialects are named, switchable, and purely local.
@immutable
class Dialect {
  Dialect({
    required this.name,
    Map<String, RoleTerm> roles = const {},
    Map<String, String> moves = const {},
    List<String> discouragedTerms = const [],
  }) : roles = Map.unmodifiable(roles),
       moves = Map.unmodifiable(moves),
       discouragedTerms = List.unmodifiable(
         discouragedTerms.map((t) => t.toLowerCase()),
       );

  final String name;

  /// Canonical role id (`role1`/`role2`) → display term.
  final Map<String, RoleTerm> roles;

  /// Canonical move id → display substitution. `%S` injects the figure's
  /// shoulder/hand side ("%S shoulder round" → "right shoulder round").
  final Map<String, String> moves;

  /// Terms the entry editor flags (struck through, never blocked).
  /// User-editable data with shipped defaults — not hardcoded policy.
  final List<String> discouragedTerms;

  /// The canonical/no-op dialect: renders canonical vocabulary untouched.
  static final Dialect canonical = Dialect(name: 'Canonical');

  /// Default preset (community-current positional terms) and the app's
  /// out-of-box active dialect.
  static final Dialect larksRobins = Dialect(
    name: 'Larks/Robins',
    roles: const {'role1': RoleTerm('Lark'), 'role2': RoleTerm('Robin')},
    discouragedTerms: defaultDiscouragedTerms,
  );

  static final Dialect leadsFollows = Dialect(
    name: 'Leads/Follows',
    roles: const {'role1': RoleTerm('Lead'), 'role2': RoleTerm('Follow')},
    discouragedTerms: defaultDiscouragedTerms,
  );

  /// The name used for a user-customized dialect (any dialect not identical to
  /// a shipped preset). Gendered role terms, if wanted, are entered here rather
  /// than shipped as presets.
  static const String customName = 'Custom';

  /// All shipped dialect presets, in display order.
  ///
  /// `canonical` is first (the identity/no-op dialect); `larksRobins` is the
  /// modern gender-free default and the app's out-of-box active dialect. Only
  /// role-neutral presets are shipped — gendered role terms are entered via the
  /// custom role-terms editor, not baked in.
  ///
  /// The list is unmodifiable — callers must not mutate it.
  static final List<Dialect> presets = List.unmodifiable([
    canonical,
    larksRobins,
    leadsFollows,
  ]);

  /// Returns the preset whose [Dialect.name] exactly matches [presetName],
  /// or `null` if no preset with that name exists.
  static Dialect? forName(String presetName) {
    for (final d in presets) {
      if (d.name == presetName) return d;
    }
    return null;
  }

  /// Shipped default for the discouraged-terms list (editable by users).
  static const List<String> defaultDiscouragedTerms = [
    'gypsy',
    'gyre',
    'gents',
    'gent',
    'ladies',
    'lady',
    'men',
    'women',
    'ravens',
  ];

  Dialect copyWith({
    String? name,
    Map<String, RoleTerm>? roles,
    Map<String, String>? moves,
    List<String>? discouragedTerms,
  }) => Dialect(
    name: name ?? this.name,
    roles: roles ?? this.roles,
    moves: moves ?? this.moves,
    discouragedTerms: discouragedTerms ?? this.discouragedTerms,
  );

  /// Serializes the whole dialect (name + role terms + move substitutions +
  /// discouraged terms) so a fully-custom dialect can be persisted, not just a
  /// preset name.
  Map<String, Object?> toJson() => {
    'name': name,
    'roles': {for (final e in roles.entries) e.key: e.value.toJson()},
    'moves': Map<String, String>.from(moves),
    'discouragedTerms': List<String>.from(discouragedTerms),
  };

  /// Reconstructs a [Dialect] from [toJson] output. Missing sections default to
  /// empty; malformed entries are skipped rather than throwing.
  static Dialect fromJson(Map<String, Object?> json) {
    final roles = <String, RoleTerm>{};
    final rolesJson = json['roles'];
    if (rolesJson is Map) {
      for (final entry in rolesJson.entries) {
        final value = entry.value;
        if (value is Map) {
          roles[entry.key.toString()] = RoleTerm.fromJson(
            value.cast<String, Object?>(),
          );
        }
      }
    }
    final moves = <String, String>{};
    final movesJson = json['moves'];
    if (movesJson is Map) {
      for (final entry in movesJson.entries) {
        final value = entry.value;
        if (value is String) moves[entry.key.toString()] = value;
      }
    }
    final discouraged = <String>[];
    final discouragedJson = json['discouragedTerms'];
    if (discouragedJson is List) {
      for (final t in discouragedJson) {
        if (t is String) discouraged.add(t);
      }
    }
    return Dialect(
      name: (json['name'] as String?) ?? customName,
      roles: roles,
      moves: moves,
      discouragedTerms: discouraged,
    );
  }

  /// Rejects mappings that would make canonicalization ambiguous: two
  /// canonical terms substituted by the same word, or a substitution that
  /// collides with another entry's canonical term.
  List<ValidationIssue> validate() {
    final issues = <ValidationIssue>[];
    final seen = <String, String>{}; // lowercased substitution → source
    void check(String source, String substitution) {
      final key = substitution.toLowerCase().replaceAll('%s', '').trim();
      if (key.isEmpty) {
        issues.add(
          ValidationIssue(
            severity: ValidationSeverity.error,
            code: 'empty_substitution',
            message: 'substitution for "$source" is empty',
          ),
        );
        return;
      }
      final existing = seen[key];
      if (existing != null) {
        issues.add(
          ValidationIssue(
            severity: ValidationSeverity.error,
            code: 'dialect_collision',
            message:
                '"$source" and "$existing" both map to '
                '"$substitution" — reversal would be ambiguous',
          ),
        );
      } else {
        seen[key] = source;
      }
    }

    for (final e in roles.entries) {
      check(e.key, e.value.singular);
    }
    for (final e in moves.entries) {
      check(e.key, e.value);
    }
    return issues;
  }

  @override
  bool operator ==(Object other) =>
      other is Dialect &&
      other.name == name &&
      _mapEq.equals(other.roles, roles) &&
      _mapEq.equals(other.moves, moves) &&
      _listEq.equals(other.discouragedTerms, discouragedTerms);

  @override
  int get hashCode => Object.hash(
    name,
    _mapEq.hash(roles),
    _mapEq.hash(moves),
    _listEq.hash(discouragedTerms),
  );
}
