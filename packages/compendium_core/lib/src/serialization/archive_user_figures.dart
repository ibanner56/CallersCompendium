import '../model/user_glossary.dart';
import '../storage/repositories/user_glossary_repository.dart';
import '../taxonomy/user_figure_definition.dart';
import '../util/text_sanitizer.dart';
import 'archive_entity_codec.dart';

/// Most of the user's own new figures (#1023) a shared archive carries. A
/// bundle carries only the figures its dances use, so this is far above any
/// real one; it bounds what a hostile file can make the reader hold.
const int kMaxArchiveUserFigures = 500;

/// [entry], one of the user's own new figures, as a shared archive carries it
/// (#1023, plan C12): its definition, without its notes, which stay on the
/// sender's device. Its kind is not written: the section holds figures only.
Map<String, Object?> archiveUserFigureToJson(UserGlossaryEntry entry) => {
  'id': entry.id,
  'name': entry.name,
  'definition': entry.definition,
  'description': entry.description,
  if (entry.keywords.isNotEmpty) 'keywords': entry.keywords,
  'payload': entry.payload,
  'createdAt': archiveIso(entry.createdAt),
};

/// The figures in a shared archive's `userFigures` section ([raw]), as
/// `customFigure` entries without notes. Never throws: the archive is
/// untrusted, so an entry that is not a whole, usable figure is left out and
/// noted in [warnings], as is anything past [kMaxArchiveUserFigures]. A figure
/// is never an error: the dances that use it still read, each as the line it
/// carries.
///
/// An entry is kept when its id is non-empty, its text fits the glossary's own
/// bounds, and its payload decodes as a figure's definition
/// ([decodeUserFigureDefinition]). Its text is scrubbed as every imported
/// string is ([sanitizeImportedText]). The first entry for an id wins.
List<UserGlossaryEntry> decodeArchiveUserFigures(
  Object? raw,
  List<String> warnings,
) {
  if (raw == null) return const [];
  if (raw is! List) {
    warnings.add('userFigures is not a JSON array; ignored');
    return const [];
  }
  final figures = <UserGlossaryEntry>[];
  final seen = <String>{};
  var skipped = 0;
  for (final item in raw) {
    if (figures.length == kMaxArchiveUserFigures) {
      warnings.add(
        'userFigures holds more than $kMaxArchiveUserFigures figures; '
        'the rest are ignored',
      );
      break;
    }
    final figure = _userFigureFromJson(item);
    if (figure == null || !seen.add(figure.id)) {
      skipped++;
      continue;
    }
    figures.add(figure);
  }
  if (skipped > 0) {
    warnings.add('$skipped userFigures entries could not be read; ignored');
  }
  return figures;
}

UserGlossaryEntry? _userFigureFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final createdAt = raw['createdAt'] is String
      ? DateTime.tryParse(raw['createdAt'] as String)
      : null;
  final payload = raw['payload'];
  if (id is! String ||
      id.trim().isEmpty ||
      id.length > maxUserGlossaryNameLength ||
      createdAt == null ||
      userGlossaryPayloadDeeperThan(payload, maxUserGlossaryPayloadDepth) ||
      decodeUserFigureDefinition(payload) == null) {
    return null;
  }
  final name = _text(raw['name'], maxUserGlossaryNameLength);
  final definition = _text(raw['definition'], maxUserGlossaryTextLength);
  final description = _text(raw['description'], maxUserGlossaryTextLength);
  final rawKeywords = raw['keywords'] ?? const <Object?>[];
  if (name == null ||
      definition == null ||
      description == null ||
      rawKeywords is! List ||
      rawKeywords.length > maxUserGlossaryKeywords) {
    return null;
  }
  final keywords = <String>[];
  for (final keyword in rawKeywords) {
    final text = _text(keyword, maxUserGlossaryNameLength);
    if (text == null) return null;
    keywords.add(text);
  }
  return UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: definition,
    description: description,
    keywords: keywords,
    payload: payload,
    createdAt: createdAt.toUtc(),
  );
}

/// [raw] scrubbed, when it is non-blank text of at most [max] code units.
String? _text(Object? raw, int max) {
  if (raw is! String) return null;
  final text = sanitizeImportedText(raw).trim();
  return text.isEmpty || text.length > max ? null : text;
}
