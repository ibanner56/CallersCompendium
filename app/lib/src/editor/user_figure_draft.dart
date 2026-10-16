import 'package:compendium_core/compendium_core.dart';

import 'figure_draft.dart';

/// A dance editor row that uses one of the user's own figures (#1023): a
/// free-text figure carrying the reference, attached. A detached one, whose
/// line was edited by a build that knows no reference, is plain text.
///
/// The same test the renderer and a save apply ([userFigureUseOf]), so the
/// editor never treats a row as a use that the dance would store as text.
bool isUserFigureDraft(FigureDraft draft) =>
    draft.move == customMove &&
    userFigureUseOf(Figure(move: customMove, params: draft.params))?.attached ==
        true;

/// The id of the figure a row uses, or null.
String? userFigureIdOf(FigureDraft draft) =>
    isUserFigureDraft(draft) ? draft.params[userFigureRefKey] as String : null;

/// The arguments a row gives its figure.
Map<String, Object?> userFigureArgsOf(FigureDraft draft) {
  final args = draft.params[userFigureArgsKey];
  return args is Map ? {...args.cast<String, Object?>()} : {};
}

/// A row's params for a use of [entry], whose definition is [definition]:
/// its defaults, or [args], its default beats, or [beats], and the line it
/// renders to now, with the check written beside it.
Map<String, Object?> userFigureDraftParams(
  UserGlossaryEntry entry,
  UserFigureDefinition definition, {
  Map<String, Object?>? args,
  int? beats,
}) => refreshedUserFigureParams(
  {
    'text': '',
    'beats': beats ?? definition.defaultBeats,
    userFigureRefKey: entry.id,
    userFigureArgsKey: {
      ...args ??
          {
            for (final p in definition.params)
              if (p.defaultValue != null) p.key: p.defaultValue,
          },
    },
    userFigureCheckKey: '',
  },
  UserFigureCatalog.fromEntries([entry]),
  fallbackName: entry.name,
);

/// [params] with their line re-rendered from [userFigures], and the check
/// written beside it, after an argument or the beats changed. When the
/// figure can't render (it is gone, or an argument no longer fits), the
/// stored line is kept, or [fallbackName] for a row that has none yet.
/// Always a new map, and a new arguments map, so an undo snapshot sharing the
/// old ones is never changed.
Map<String, Object?> refreshedUserFigureParams(
  Map<String, Object?> params,
  UserFigureCatalog userFigures, {
  String? fallbackName,
}) {
  final args = params[userFigureArgsKey];
  final next = <String, Object?>{
    ...params,
    userFigureArgsKey: {
      ...?(args is Map ? args.cast<String, Object?>() : null),
    },
  };
  final id = next[userFigureRefKey];
  final beats = next['beats'];
  final line = id is String
      ? FigureRenderer(
          contraTaxonomy,
          userFigures: userFigures,
        ).renderUserFigureCanonical(
          userFigureUseFigure(
            id: id,
            args: next[userFigureArgsKey]! as Map<String, Object?>,
            text: '',
            beats: beats is int ? beats : null,
          ),
        )
      : null;
  final stored = next['text'];
  final text =
      line ??
      (stored is String && stored.isNotEmpty ? stored : fallbackName ?? '');
  next['text'] = text;
  next[userFigureCheckKey] = userFigureTextCheck(text);
  return next;
}

/// [figures] with each use of one of the user's figures re-rendered from
/// [userFigures]: what a dance stores when it is saved, so its line, the
/// fallback every build shows, is the figure's current wording (the stored
/// line refreshes only on such a stamped write, #1023). A use of a figure in
/// [deleted] becomes plain text with its line, as deleting the figure made
/// every stored use (it was open here meanwhile); one whose figure this
/// device does not have, or that can't render, keeps its line; a detached one
/// is left as plain text.
List<Figure> refreshUserFigureUses(
  List<Figure> figures,
  UserFigureCatalog userFigures, {
  Set<String> deleted = const {},
}) {
  if (userFigures.isEmpty && deleted.isEmpty) return figures;
  final renderer = FigureRenderer(contraTaxonomy, userFigures: userFigures);
  return mapFigureLeaves(figures, (figure) {
    final use = userFigureUseOf(figure);
    if (use == null || !use.attached) return figure;
    if (deleted.contains(use.id)) return detachUserFigureUse(figure);
    final line = renderer.renderUserFigureCanonical(figure);
    if (line == null || line == use.text) return figure;
    return figure.copyWith(
      params: {
        ...figure.params,
        'text': line,
        userFigureCheckKey: userFigureTextCheck(line),
      },
    );
  });
}

/// Makes [draft] a use of the user's figure [entryId] (#1023), one of
/// [options], with its defaults and its default beats: whatever the row held
/// before is replaced, as picking a move replaces it. False, and [draft]
/// untouched, when the entry is not offered or its definition doesn't decode.
bool selectUserFigure(
  FigureDraft draft,
  String entryId,
  List<UserGlossaryEntry>? options,
) {
  final entry = options?.where((e) => e.id == entryId).firstOrNull;
  final definition = entry == null
      ? null
      : decodeUserFigureDefinition(entry.payload);
  if (entry == null || definition == null) return false;
  draft
    ..move = customMove
    ..compound = null
    ..beatsTouched = false
    ..assumedSubject = false
    ..customOrigin = CustomOrigin.userEntered
    ..walkthroughOverride = null
    ..wordingOverride = null;
  draft.params
    ..clear()
    ..addAll(userFigureDraftParams(entry, definition));
  return true;
}
