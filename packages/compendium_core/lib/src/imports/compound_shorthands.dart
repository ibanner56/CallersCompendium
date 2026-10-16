import 'dart:convert';

import 'package:meta/meta.dart';

import '../storage/repositories/user_glossary_repository.dart'
    show maxUserGlossaryNameLength;
import '../sync/canonical_json.dart';
import '../taxonomy/compound_definition.dart'
    show maxCompoundParamKeyLength, maxCompoundParams;
import 'shorthand_mappings.dart'
    show maxShorthandTokenLength, normalizeShorthandToken;

/// The settings key of the user's compound shorthands (#709): a JSON array of
/// `{token, compound, name, args}` objects (see [CompoundShorthands.toJson]).
/// Kept apart from `shorthand_mappings`, which every older build reads and
/// rewrites whole, dropping any mapping it cannot decode.
const String compoundShorthandsSettingKey = 'compound_shorthands';

/// Upper bound on how many compound shorthands are decoded from storage.
/// Mirrors the figure shorthands' bound.
const int maxCompoundShorthands = 500;

/// Upper bound on a text argument's length. A text parameter fills a figure's
/// free-text slot, which is short.
const int maxCompoundShorthandTextArgLength = 1000;

/// One compound shorthand (#709): a [token], typed as a whole free-text line,
/// that stands for one of the user's own compound figures with fixed
/// arguments. Typing it inserts the compound as a placeholder row, which is
/// expanded with the compound as it is when the dance is saved.
///
/// [compoundId] is the compound's glossary entry id. [compoundName] is its name
/// when the shorthand was saved, as stored (canonical glossary text): what the
/// shorthand is shown by when the compound has since been deleted.
@immutable
class CompoundShorthand {
  CompoundShorthand({
    required this.token,
    required this.compoundId,
    required this.compoundName,
    Map<String, Object?> args = const {},
  }) : args = Map.unmodifiable(args);

  /// The user-entered token, with its casing kept for display.
  final String token;

  final String compoundId;
  final String compoundName;

  /// The value each of the compound's parameters takes, by key. Unmodifiable.
  final Map<String, Object?> args;

  /// The trimmed, lowercased token used for matching and uniqueness, shared
  /// with figure shorthands ([normalizeShorthandToken]).
  String get normalizedToken => normalizeShorthandToken(token);

  Map<String, Object?> toJson() => {
    'token': token,
    'compound': compoundId,
    'name': compoundName,
    'args': args,
  };

  @override
  bool operator ==(Object other) =>
      other is CompoundShorthand &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;

  @override
  String toString() => 'CompoundShorthand($token → $compoundId)';
}

/// The user's compound shorthands, in display order, with the whole-line
/// resolution the free-text entry path uses (#709). Flutter-free.
@immutable
class CompoundShorthands {
  CompoundShorthands(List<CompoundShorthand> shorthands)
    : shorthands = List.unmodifiable(shorthands),
      _byToken = {for (final s in shorthands.reversed) s.normalizedToken: s};

  /// The shorthands in display order. Unmodifiable.
  final List<CompoundShorthand> shorthands;

  final Map<String, CompoundShorthand> _byToken;

  static final CompoundShorthands empty = CompoundShorthands(const []);

  bool get isEmpty => shorthands.isEmpty;

  /// The shorthand whose token is the whole of [line], ignoring case and
  /// surrounding space, or null. A beat count typed with the token is not
  /// handled here: the caller splits it off first ([splitShorthandCount]). When two share a token the first wins, as
  /// [decode] keeps.
  CompoundShorthand? resolve(String line) {
    final key = normalizeShorthandToken(line);
    return key.isEmpty ? null : _byToken[key];
  }

  List<Object?> toJson() => [for (final s in shorthands) s.toJson()];

  /// Decodes a stored value defensively, never throwing: [stored] may be the
  /// decoded JSON list or its string. Anything else yields [empty].
  ///
  /// An entry is kept only whole: a non-empty token within
  /// [maxShorthandTokenLength], a non-empty compound id and a name within the
  /// glossary's name bound, and at most [maxCompoundParams] arguments, each
  /// keyed within [maxCompoundParamKeyLength] and holding a string (within
  /// [maxCompoundShorthandTextArgLength]), a number or a bool. Whether the
  /// compound exists or accepts the arguments is not checked here: it is the
  /// user's data, which can change after the shorthand is saved, so it is
  /// checked each time the shorthand is shown or used. A token already taken
  /// keeps its first entry. At most [maxCompoundShorthands] are kept.
  static CompoundShorthands decode(Object? stored) {
    var raw = stored;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return empty;
      }
    }
    if (raw is! List) return empty;
    final result = <CompoundShorthand>[];
    final tokens = <String>{};
    for (final entry in raw) {
      if (result.length >= maxCompoundShorthands) break;
      final shorthand = _decodeOne(entry);
      if (shorthand == null || !tokens.add(shorthand.normalizedToken)) {
        continue;
      }
      result.add(shorthand);
    }
    return CompoundShorthands(result);
  }

  /// Whether [shorthand] is one [decode] keeps: what is saved must survive the
  /// next load, so the controller refuses anything else.
  static bool keeps(CompoundShorthand shorthand) =>
      _decodeOne(shorthand.toJson()) != null;

  static CompoundShorthand? _decodeOne(Object? entry) {
    if (entry is! Map) return null;
    final rawToken = entry['token'];
    final id = entry['compound'];
    final name = entry['name'];
    final rawArgs = entry['args'];
    if (rawToken is! String || id is! String || name is! String) return null;
    final token = rawToken.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) return null;
    if (id.isEmpty || id.length > maxUserGlossaryNameLength) return null;
    if (name.isEmpty || name.length > maxUserGlossaryNameLength) return null;
    if (rawArgs is! Map || rawArgs.length > maxCompoundParams) return null;
    final args = <String, Object?>{};
    for (final MapEntry(:key, :value) in rawArgs.entries) {
      if (key is! String ||
          key.isEmpty ||
          key.length > maxCompoundParamKeyLength) {
        return null;
      }
      final ok = switch (value) {
        final String text => text.length <= maxCompoundShorthandTextArgLength,
        num() || bool() => true,
        _ => false,
      };
      if (!ok) return null;
      args[key] = value;
    }
    return CompoundShorthand(
      token: token,
      compoundId: id,
      compoundName: name,
      args: args,
    );
  }
}
