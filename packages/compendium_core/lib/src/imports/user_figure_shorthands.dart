import 'dart:convert';

import 'package:meta/meta.dart';

import '../storage/repositories/user_glossary_repository.dart'
    show maxUserGlossaryNameLength;
import '../sync/canonical_json.dart';
import '../taxonomy/user_figure_definition.dart' show maxUserFigureDefaultBeats;
import '../taxonomy/user_figure_use.dart';
import 'shorthand_mappings.dart'
    show maxShorthandTokenLength, normalizeShorthandToken;

/// The settings key of the user's shorthands for their own new figures
/// (#1023): a JSON array of `{token, figure, name, args, beats?}` objects (see
/// [UserFigureShorthands.toJson]).
///
/// A key of its own, beside `compound_shorthands`: `shorthand_mappings` is
/// read and rewritten whole by every older build, which would drop a mapping
/// holding a use (plan C7), and this one is gated with the figures themselves
/// (`glossary.v2`), while compound shorthands sync under `glossary.v1`.
const String userFigureShorthandsSettingKey = 'user_figure_shorthands';

/// Upper bound on how many shorthands for the user's figures are decoded from
/// storage. Mirrors the other shorthands' bound.
const int maxUserFigureShorthands = 500;

/// One shorthand for a figure of the user's own (#1023): a [token], typed as
/// a whole free-text line, that inserts a use of the figure with fixed
/// arguments and, optionally, beats.
///
/// [figureId] is the figure's glossary entry id. [figureName] is its name when
/// the shorthand was saved, as stored (canonical glossary text): what the
/// shorthand is shown by when the figure has since been deleted.
@immutable
class UserFigureShorthand {
  UserFigureShorthand({
    required this.token,
    required this.figureId,
    required this.figureName,
    Map<String, Object?> args = const {},
    this.beats,
  }) : args = Map.unmodifiable(args);

  /// The user-entered token, with its casing kept for display.
  final String token;

  final String figureId;
  final String figureName;

  /// The value each of the figure's parameters takes, by key. Unmodifiable.
  final Map<String, Object?> args;

  /// The use's beats, or null for the figure's default beats when typed.
  final int? beats;

  /// The trimmed, lowercased token used for matching and uniqueness, shared
  /// with the other shorthands ([normalizeShorthandToken]).
  String get normalizedToken => normalizeShorthandToken(token);

  Map<String, Object?> toJson() => {
    'token': token,
    'figure': figureId,
    'name': figureName,
    'args': args,
    if (beats != null) 'beats': beats,
  };

  @override
  bool operator ==(Object other) =>
      other is UserFigureShorthand &&
      canonicalJson(other.toJson()) == canonicalJson(toJson());

  @override
  int get hashCode => canonicalJson(toJson()).hashCode;

  @override
  String toString() => 'UserFigureShorthand($token → $figureId)';
}

/// The user's shorthands for their own figures, in display order, with the
/// whole-line resolution the free-text entry path uses (#1023).
/// Flutter-free.
@immutable
class UserFigureShorthands {
  UserFigureShorthands(List<UserFigureShorthand> shorthands)
    : shorthands = List.unmodifiable(shorthands),
      _byToken = {for (final s in shorthands.reversed) s.normalizedToken: s};

  /// The shorthands in display order. Unmodifiable.
  final List<UserFigureShorthand> shorthands;

  final Map<String, UserFigureShorthand> _byToken;

  static final UserFigureShorthands empty = UserFigureShorthands(const []);

  bool get isEmpty => shorthands.isEmpty;

  /// The shorthand whose token is the whole of [line], ignoring case and
  /// surrounding space, or null. When two share a token the first wins, as
  /// [decode] keeps.
  UserFigureShorthand? resolve(String line) {
    final key = normalizeShorthandToken(line);
    return key.isEmpty ? null : _byToken[key];
  }

  List<Object?> toJson() => [for (final s in shorthands) s.toJson()];

  /// Decodes a stored value defensively, never throwing: [stored] may be the
  /// decoded JSON list or its string. Anything else yields [empty].
  ///
  /// An entry is kept only whole: a non-empty token within
  /// [maxShorthandTokenLength], a name within the glossary's name bound,
  /// beats from 1 to [maxUserFigureDefaultBeats] when present, and a figure
  /// id and arguments a use could hold ([userFigureUseOf]: the same id shape
  /// and argument bounds, so a shorthand never inserts a use that reads back
  /// as plain text). Whether the figure exists or accepts the arguments is not
  /// checked here: it is the user's data, which can change after the
  /// shorthand is saved, so it is checked each time the shorthand is shown or
  /// used. A token already taken keeps its first entry. At most
  /// [maxUserFigureShorthands] are kept.
  static UserFigureShorthands decode(Object? stored) {
    var raw = stored;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return empty;
      }
    }
    if (raw is! List) return empty;
    final result = <UserFigureShorthand>[];
    final tokens = <String>{};
    for (final entry in raw) {
      if (result.length >= maxUserFigureShorthands) break;
      final shorthand = _decodeOne(entry);
      if (shorthand == null || !tokens.add(shorthand.normalizedToken)) {
        continue;
      }
      result.add(shorthand);
    }
    return UserFigureShorthands(result);
  }

  /// Whether [shorthand] is one [decode] keeps: what is saved must survive the
  /// next load, so the controller refuses anything else.
  static bool keeps(UserFigureShorthand shorthand) =>
      _decodeOne(shorthand.toJson()) != null;

  static UserFigureShorthand? _decodeOne(Object? entry) {
    if (entry is! Map) return null;
    final rawToken = entry['token'];
    final id = entry['figure'];
    final name = entry['name'];
    final rawArgs = entry['args'];
    final beats = entry['beats'];
    if (rawToken is! String || id is! String || name is! String) return null;
    final token = rawToken.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) return null;
    if (name.isEmpty || name.length > maxUserGlossaryNameLength) return null;
    if (beats != null &&
        (beats is! int || beats < 1 || beats > maxUserFigureDefaultBeats)) {
      return null;
    }
    if (rawArgs is! Map) return null;
    final args = <String, Object?>{};
    for (final MapEntry(:key, :value) in rawArgs.entries) {
      if (key is! String) return null;
      args[key] = value;
    }
    // The use this shorthand inserts must be one a use can be.
    final use = userFigureUseOf(
      userFigureUseFigure(id: id, args: args, text: ''),
    );
    if (use == null) return null;
    return UserFigureShorthand(
      token: token,
      figureId: id,
      figureName: name,
      args: use.args,
      beats: beats as int?,
    );
  }
}
