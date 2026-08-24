import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../util/text_sanitizer.dart';
import '../validation/validation.dart';

/// Maximum UTF-16 code units retained for one user-authored move wording.
const int kMaxMoveWordingLength = 512;

/// Maximum number of move wording entries retained in one dialect.
const int kMaxMoveWordingEntries = 256;

/// Fixed branch keys supported by parameter-dependent display wordings.
const Map<String, Set<String>> kMoveWordingBranchKeys = {
  'form_a_long_wave': {'inOnly', 'outOnly', 'inAndOut', 'neither'},
  'promenade': {'ordinary', 'singleFile'},
};

/// A role display term: singular plus plural (plural derived with a basic
/// consonant+y→ies / +s rule unless given explicitly — "Lady" → "Ladies",
/// but "Boy" → "Boys" since the `y` follows a vowel).
@immutable
class RoleTerm {
  // ignore: prefer_initializing_formals
  const RoleTerm(this.singular, {String? plural}) : _plural = plural;

  static const _vowels = {'a', 'e', 'i', 'o', 'u'};

  final String singular;
  final String? _plural;
  String get plural {
    if (_plural != null) return _plural;
    if (singular.length > 1 &&
        singular.endsWith('y') &&
        !_vowels.contains(singular[singular.length - 2].toLowerCase())) {
      return '${singular.substring(0, singular.length - 1)}ies';
    }
    return '${singular}s';
  }

  /// JSON form: always writes the resolved [plural] so the exact display
  /// pluralization round-trips (independent of the derivation rule).
  Map<String, Object?> toJson() => {'singular': singular, 'plural': plural};

  /// Parses a [RoleTerm] from [toJson] output, tolerating malformed persisted
  /// data. Returns `null` when the entry is unusable (missing/blank/non-string
  /// `singular`). A missing/blank/non-string `plural` falls back to the derived
  /// plural.
  static RoleTerm? fromJson(Map<String, Object?> json) {
    final rawSingular = json['singular'];
    if (rawSingular is! String || rawSingular.isEmpty) return null;
    final rawPlural = json['plural'];
    final plural = (rawPlural is String && rawPlural.isNotEmpty)
        ? rawPlural
        : null;
    return RoleTerm(rawSingular, plural: plural);
  }

  @override
  bool operator ==(Object other) =>
      other is RoleTerm && other.singular == singular && other.plural == plural;

  @override
  int get hashCode => Object.hash(singular, plural);
}

const MapEquality<Object?, Object?> _mapEq = MapEquality<Object?, Object?>();
const ListEquality<Object?> _listEq = ListEquality<Object?>();
const DeepCollectionEquality _deepEq = DeepCollectionEquality();

/// A user-level presentation mapping applied at render time. Storage is
/// always canonical; dialects are named, switchable, and purely local.
@immutable
class Dialect {
  Dialect({
    required this.name,
    Map<String, RoleTerm> roles = const {},
    Map<String, String> moves = const {},
    Map<String, String> dancers = const {},
    Map<String, String> moveWordings = const {},
    Map<String, Map<String, String>> moveWordingBranches = const {},
    List<String> discouragedTerms = const [],
  }) : roles = Map.unmodifiable(roles),
       moves = Map.unmodifiable(moves),
       dancers = Map.unmodifiable(dancers),
       moveWordings = Map.unmodifiable(moveWordings),
       moveWordingBranches = Map<String, Map<String, String>>.unmodifiable(
         moveWordingBranches.map(
           (key, value) =>
               MapEntry(key, Map<String, String>.unmodifiable(value)),
         ),
       ),
       discouragedTerms = List.unmodifiable(
         discouragedTerms.map((t) => t.toLowerCase()),
       );

  final String name;

  /// Canonical role id (`role1`/`role2`) → display term.
  final Map<String, RoleTerm> roles;

  /// Canonical move id → display substitution. `%S` injects the figure's
  /// shoulder/hand side ("%S shoulder round" → "right shoulder round").
  final Map<String, String> moves;

  /// Canonical positional/relational dancer token (e.g. `neighbors`,
  /// `nextNeighbors`) → display substitution. Parallel to [moves]; the
  /// role-driven tokens `role1s`/`role2s` are intentionally excluded (they flow
  /// through role-term substitution instead).
  final Map<String, String> dancers;

  /// Canonical move id → display-only wording template. Template placeholders
  /// are resolved by [FigureRenderer]; canonical rendering never reads this map.
  final Map<String, String> moveWordings;

  /// Canonical move ID → fixed parameter branch ID → display-only wording
  /// template. Branches are resolved by [FigureRenderer] from effective params.
  final Map<String, Map<String, String>> moveWordingBranches;

  /// Terms the entry editor flags (struck through, never blocked).
  /// User-editable data with shipped defaults — not hardcoded policy.
  final List<String> discouragedTerms;

  /// The canonical/no-op dialect: renders canonical vocabulary untouched.
  static final Dialect canonical = Dialect(name: 'Canonical');

  /// Default preset (community-current positional terms) and the app's
  /// out-of-box active dialect.
  static final Dialect larksRobins = Dialect(
    name: 'Larks/Robins',
    roles: const {'role1': RoleTerm('lark'), 'role2': RoleTerm('robin')},
    discouragedTerms: defaultDiscouragedTerms,
  );

  static final Dialect leadsFollows = Dialect(
    name: 'Leads/Follows',
    roles: const {'role1': RoleTerm('lead'), 'role2': RoleTerm('follow')},
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

  /// Resolves [name] to a [Dialect], searching user-defined [candidates] first
  /// (so a custom dialect wins over a shipped preset with the same name), then
  /// the shipped [presets] via [forName]. Returns `null` when [name] is `null`
  /// or matches nothing — callers fall back to a default.
  ///
  /// Supersedes [forName] for callers that also have a library of custom,
  /// user-created dialects to search.
  static Dialect? resolveByName(
    String? name, {
    Iterable<Dialect> candidates = const [],
  }) {
    if (name == null) return null;
    for (final d in candidates) {
      if (d.name == name) return d;
    }
    return forName(name);
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
    Map<String, String>? dancers,
    Map<String, String>? moveWordings,
    Map<String, Map<String, String>>? moveWordingBranches,
    List<String>? discouragedTerms,
  }) => Dialect(
    name: name ?? this.name,
    roles: roles ?? this.roles,
    moves: moves ?? this.moves,
    dancers: dancers ?? this.dancers,
    moveWordings: moveWordings ?? this.moveWordings,
    moveWordingBranches: moveWordingBranches ?? this.moveWordingBranches,
    discouragedTerms: discouragedTerms ?? this.discouragedTerms,
  );

  /// Serializes the whole dialect (name + role terms + move substitutions +
  /// dancer substitutions + move wording templates + discouraged terms) so a
  /// fully-custom dialect can be persisted, not just a preset name.
  Map<String, Object?> toJson() => {
    'name': name,
    'roles': {for (final e in roles.entries) e.key: e.value.toJson()},
    'moves': Map<String, String>.from(moves),
    'dancers': Map<String, String>.from(dancers),
    'moveWordings': Map<String, String>.from(moveWordings),
    'moveWordingBranches': {
      for (final entry in moveWordingBranches.entries)
        entry.key: Map<String, String>.from(entry.value),
    },
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
          final term = RoleTerm.fromJson(value.cast<String, Object?>());
          if (term != null) roles[entry.key.toString()] = term;
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
    final dancers = <String, String>{};
    final dancersJson = json['dancers'];
    if (dancersJson is Map) {
      for (final entry in dancersJson.entries) {
        final value = entry.value;
        if (value is String) dancers[entry.key.toString()] = value;
      }
    }
    final moveWordings = <String, String>{};
    final moveWordingBranches = <String, Map<String, String>>{};
    var wordingCount = 0;
    final moveWordingsJson = json['moveWordings'];
    if (moveWordingsJson is Map) {
      for (final entry in moveWordingsJson.entries) {
        if (wordingCount >= kMaxMoveWordingEntries) break;
        final value = entry.value;
        if (value is! String) continue;
        final sanitized = sanitizeImportedText(value, allowLineBreaks: false);
        if (sanitized.trim().isEmpty) continue;
        moveWordings[entry.key
            .toString()] = sanitized.length <= kMaxMoveWordingLength
            ? sanitized
            : sanitized.substring(0, kMaxMoveWordingLength);
        wordingCount++;
      }
    }
    final branchesJson = json['moveWordingBranches'];
    if (branchesJson is Map) {
      final legacyCircle = branchesJson['circle'];
      if (legacyCircle is Map && legacyCircle['ordinary'] is String) {
        final sanitized = sanitizeImportedText(
          legacyCircle['ordinary'] as String,
          allowLineBreaks: false,
        );
        final hadCircleWording = moveWordings.containsKey('circle');
        if (sanitized.trim().isNotEmpty &&
            (hadCircleWording || wordingCount < kMaxMoveWordingEntries)) {
          moveWordings['circle'] = sanitized.length <= kMaxMoveWordingLength
              ? sanitized
              : sanitized.substring(0, kMaxMoveWordingLength);
          if (!hadCircleWording) wordingCount++;
        }
      }
      for (final moveEntry in branchesJson.entries) {
        if (wordingCount >= kMaxMoveWordingEntries) break;
        final moveId = moveEntry.key.toString();
        final allowedBranches = kMoveWordingBranchKeys[moveId];
        if (allowedBranches == null || moveEntry.value is! Map) continue;
        final branches = <String, String>{};
        for (final branchEntry in (moveEntry.value as Map).entries) {
          if (wordingCount >= kMaxMoveWordingEntries) break;
          final branchId = branchEntry.key.toString();
          if (!allowedBranches.contains(branchId) ||
              branchEntry.value is! String) {
            continue;
          }
          final sanitized = sanitizeImportedText(
            branchEntry.value as String,
            allowLineBreaks: false,
          );
          if (sanitized.trim().isEmpty) continue;
          branches[branchId] = sanitized.length <= kMaxMoveWordingLength
              ? sanitized
              : sanitized.substring(0, kMaxMoveWordingLength);
          wordingCount++;
        }
        if (branches.isNotEmpty) moveWordingBranches[moveId] = branches;
      }
    }
    final discouraged = <String>[];
    final discouragedJson = json['discouragedTerms'];
    if (discouragedJson is List) {
      for (final t in discouragedJson) {
        if (t is String) discouraged.add(t);
      }
    }
    final rawName = json['name'];
    return Dialect(
      name: rawName is String ? rawName : customName,
      roles: roles,
      moves: moves,
      dancers: dancers,
      moveWordings: moveWordings,
      moveWordingBranches: moveWordingBranches,
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
            data: {'source': source},
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
            data: {
              'source': source,
              'existing': existing,
              'substitution': substitution,
            },
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
    for (final e in dancers.entries) {
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
      _mapEq.equals(other.dancers, dancers) &&
      _mapEq.equals(other.moveWordings, moveWordings) &&
      _deepEq.equals(other.moveWordingBranches, moveWordingBranches) &&
      _listEq.equals(other.discouragedTerms, discouragedTerms);

  @override
  int get hashCode => Object.hash(
    name,
    _mapEq.hash(roles),
    _mapEq.hash(moves),
    _mapEq.hash(dancers),
    _mapEq.hash(moveWordings),
    _deepEq.hash(moveWordingBranches),
    _listEq.hash(discouragedTerms),
  );
}
