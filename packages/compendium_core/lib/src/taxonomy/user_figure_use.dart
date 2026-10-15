import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../model/figure.dart';
import '../model/user_glossary.dart';
import '../storage/shareable_text.dart';
import 'user_figure_definition.dart';

/// The `params` key holding the id of the figure of your own a use refers to
/// (#1023).
///
/// A use of a figure of your own is a free-text [customMove] figure: its
/// `text` is the line last rendered from the definition, which every build
/// shows, and three keys inside `params` refer to the definition. Older
/// builds keep `params` whole ([figureFromJson]), where a new top-level key
/// would make a peer refuse the dance. The reference is soft (sync-spec
/// §6.15): a device without the definition shows the `text`. Decided by the
/// maintainer in planning (#1023 consolidated spec, decision 1); the three
/// flat keys are the implementer's choice, so the structured search filter
/// can address the id by a plain JSON path.
const String userFigureRefKey = 'userFigure';

/// The `params` key holding a use's arguments: every declared parameter's
/// value at the time it was written, by key.
const String userFigureArgsKey = 'userFigureArgs';

/// The `params` key holding a short hash of the use's `text`
/// ([userFigureTextCheck]). When the text no longer matches it, a build that
/// does not know these keys has edited the line, and the use reads as plain
/// text rather than overwriting what was typed (implementer's choice).
const String userFigureCheckKey = 'userFigureCheck';

/// The three `params` keys a use of a figure of your own adds to a
/// [customMove] figure.
const Set<String> userFigureReferenceKeys = {
  userFigureRefKey,
  userFigureArgsKey,
  userFigureCheckKey,
};

/// Longest id a use may refer to: a UUID, with room to spare.
const int _maxRefLength = 64;

/// Longest text argument a use may carry.
const int maxUserFigureTextArgLength = 1000;

final RegExp _refShape = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _checkShape = RegExp(r'^[0-9a-f]{8}$');

/// The check stored beside a use's [text]: the first 32 bits of the SHA-256
/// of the text as the repository stores it ([normalizeShareableText]), so
/// saving a dance can never change the text out from under its check.
String userFigureTextCheck(String text) => sha256
    .convert(utf8.encode(normalizeShareableText(text)))
    .toString()
    .substring(0, 8);

/// A use of a figure of your own, read from a [customMove] figure (#1023).
final class UserFigureUse {
  UserFigureUse._({
    required this.id,
    required Map<String, Object?> args,
    required this.check,
    required this.text,
  }) : args = Map.unmodifiable(args);

  /// The id of the glossary entry defining the figure.
  final String id;

  /// The arguments the use was written with, by parameter key.
  final Map<String, Object?> args;

  final String check;

  /// The stored line: the fallback every build can show.
  final String text;

  /// Whether the stored line is still the one written beside the reference.
  /// A detached use reads as plain text.
  bool get attached => userFigureTextCheck(text) == check;
}

/// The use of a figure of your own that [figure] holds, or null when it holds
/// none, or holds one this build cannot read: a reference key with a value of
/// the wrong shape, or arguments over a bound. Such a figure is plain text.
UserFigureUse? userFigureUseOf(Figure figure) {
  if (!figure.isCustom) return null;
  final params = figure.params;
  final id = params[userFigureRefKey];
  final args = params[userFigureArgsKey];
  final check = params[userFigureCheckKey];
  final text = params['text'];
  if (id is! String ||
      id.length > _maxRefLength ||
      !_refShape.hasMatch(id) ||
      args is! Map ||
      args.length > maxUserFigureParams ||
      check is! String ||
      !_checkShape.hasMatch(check) ||
      text is! String) {
    return null;
  }
  final decoded = <String, Object?>{};
  for (final MapEntry(:key, :value) in args.entries) {
    if (key is! String || key.length > maxUserFigureParamKeyLength) {
      return null;
    }
    if (value is String) {
      if (value.length > maxUserFigureTextArgLength) return null;
    } else if (value is! num && value is! bool && value != null) {
      return null;
    }
    decoded[key] = value;
  }
  return UserFigureUse._(id: id, args: decoded, check: check, text: text);
}

/// Whether [figure] carries any of the reference keys, readable or not.
bool hasUserFigureReferenceKeys(Figure figure) =>
    figure.isCustom &&
    userFigureReferenceKeys.any((key) => figure.params.containsKey(key));

/// A use of the figure of your own [id] with [args], whose fallback line is
/// [text] (the canonical render, role words as tokens).
///
/// Always [CustomOrigin.userEntered]: an import-gap custom is one an importer
/// could not parse, and #417's re-parse offer must never replace a use.
Figure userFigureUseFigure({
  required String id,
  required Map<String, Object?> args,
  required String text,
  int? beats,
  String? note,
  bool progression = false,
}) => Figure(
  move: customMove,
  params: {
    'text': text,
    'beats': ?beats,
    userFigureRefKey: id,
    userFigureArgsKey: Map<String, Object?>.unmodifiable(args),
    userFigureCheckKey: userFigureTextCheck(text),
  },
  note: note,
  progression: progression,
);

/// [figure] with its reference removed: a plain free-text figure showing
/// [text], or the line it last stored when [text] is null. What deleting a
/// definition does to its uses (maintainer decision 2: frozen as plain
/// text); the caller passes the line the use renders to now, so freezing
/// keeps what the user last saw rather than a line stored before an edit.
Figure detachUserFigureUse(Figure figure, {String? text}) {
  if (!hasUserFigureReferenceKeys(figure)) return figure;
  return figure.copyWith(
    params: {
      for (final entry in figure.params.entries)
        if (!userFigureReferenceKeys.contains(entry.key))
          entry.key: entry.key == 'text' && text != null ? text : entry.value,
    },
  );
}

/// [figures] with [transform] applied to every leaf, inside meanwhile and
/// modifier containers too. Returns [figures] itself when nothing changed, so
/// a caller can tell whether a dance needs writing.
List<Figure> mapFigureLeaves(
  List<Figure> figures,
  Figure Function(Figure leaf) transform,
) {
  var changed = false;
  final out = <Figure>[];
  for (final figure in figures) {
    final mapped = _mapLeaf(figure, transform);
    if (!identical(mapped, figure)) changed = true;
    out.add(mapped);
  }
  return changed ? List.unmodifiable(out) : figures;
}

Figure _mapLeaf(Figure figure, Figure Function(Figure leaf) transform) {
  if (!figure.isContainer) return transform(figure);
  final children = figure.subFigures;
  final mapped = mapFigureLeaves(children, transform);
  if (identical(mapped, children)) return figure;
  return figure.copyWith(params: {...figure.params, 'figures': mapped});
}

/// The ids of the figures of your own [figures] use, inside containers too.
/// Detached uses count for nothing.
Set<String> userFigureIdsUsedBy(Iterable<Figure> figures) {
  final ids = <String>{};
  void visit(Figure figure) {
    if (figure.isContainer) {
      figure.subFigures.forEach(visit);
      return;
    }
    final use = userFigureUseOf(figure);
    if (use != null && use.attached) ids.add(use.id);
  }

  figures.forEach(visit);
  return ids;
}

/// One figure of your own, as the renderer and pickers see it.
final class UserFigureView {
  const UserFigureView({
    required this.id,
    required this.name,
    required this.definition,
  });

  final String id;

  /// The entry's name, role words as canonical tokens.
  final String name;

  /// The definition, or null when the payload no longer decodes: the
  /// figure's uses then show their stored line.
  final UserFigureDefinition? definition;
}

/// The user's own figures by id (#1023): what renders a use live.
///
/// Built from glossary entries the caller has already filtered to live ones
/// ([fromEntries] does not filter deleted entries); a figure absent from it
/// renders its uses' stored lines.
final class UserFigureCatalog {
  const UserFigureCatalog._(this._byId);

  /// No figures: every use shows its stored line.
  static const UserFigureCatalog empty = UserFigureCatalog._({});

  /// The `customFigure` entries among [entries]; any other kind is skipped.
  factory UserFigureCatalog.fromEntries(Iterable<UserGlossaryEntry> entries) {
    final byId = <String, UserFigureView>{};
    for (final entry in entries) {
      if (entry.kind != UserGlossaryEntryKind.customFigure) continue;
      byId[entry.id] = UserFigureView(
        id: entry.id,
        name: entry.name,
        definition: decodeUserFigureDefinition(entry.payload),
      );
    }
    return UserFigureCatalog._(Map.unmodifiable(byId));
  }

  final Map<String, UserFigureView> _byId;

  UserFigureView? operator [](String id) => _byId[id];

  Iterable<UserFigureView> get figures => _byId.values;

  bool get isEmpty => _byId.isEmpty;
}
