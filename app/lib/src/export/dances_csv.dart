import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';
import '../data/csv_import_mapping.dart';
import '../search/dance_detail_data.dart' show formatCustomFieldValue;
import '../search/facet_labels.dart';
import '../utils/safe_name.dart';
import 'dance_source_lines.dart';
import 'export_labels_l10n.dart';
import 'share_sanitization.dart';

/// Everything [buildDancesCsv] looks up besides the dances themselves.
class DancesCsvLookups {
  const DancesCsvLookups({
    this.choreographersById = const {},
    this.tagsById = const {},
    this.sourcesById = const {},
    this.customFields = const [],
    this.difficultyLevelsById = const {},
  });

  /// Reads every record the dances may refer to. Deleted people are left
  /// out, as the dance screen and its text export leave them out, so the
  /// authors (and the dialect chosen from them) match the text export.
  static Future<DancesCsvLookups> load(CompendiumRepositories repos) async {
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final sources = await repos.publishedSources.listAll();
    final customFields = await repos.customFieldDefs.listAll();
    final levels = await repos.difficultyLevels.listAll();
    return DancesCsvLookups(
      choreographersById: {for (final c in choreographers) c.id: c},
      tagsById: {for (final t in tags) t.id: t},
      sourcesById: {for (final s in sources) s.id: s},
      customFields: customFields,
      difficultyLevelsById: {for (final l in levels) l.id: l},
    );
  }

  final Map<String, Choreographer> choreographersById;
  final Map<String, Tag> tagsById;
  final Map<String, PublishedSource> sourcesById;

  /// Every custom field, in the order their columns appear. Fields with
  /// **Include in sharing** off are left out by [buildDancesCsv].
  final List<CustomFieldDef> customFields;
  final Map<String, DifficultyLevel> difficultyLevelsById;
}

/// The dances as a CSV spreadsheet (#2332): a header row, then one row per
/// dance, sorted by title.
///
/// The file is one the user can send anywhere, so it follows the share rules
/// (`docs/user/sharing.md`, "What stays private") with one exception, the star
/// rating (maintainer decision on #2332):
///
/// * People are reduced to their names through
///   [sanitizeChoreographerForShare]: no email, location or deceased mark.
/// * Custom fields leave only when [customFieldLeavesIn] says they would in a
///   share file, so a field with **Include in sharing** off has no column.
/// * The user's own figures appear only as the words of the figures that use
///   them; their notes are never read.
/// * The rating is read from the dance as stored. [sanitizeDanceForShare]
///   strips it, and is left as it is so share files still drop it.
///
/// Figures are worded in each dance's form's dialect from [dialects] exactly as
/// the dance's text export words them ([danceCardFigureLines]), one line per
/// figure. The hook, calling notes and walkthrough are rendered in the same
/// dialect, as on the text card.
///
/// Columns: title, authors, when composed, interpreters, when interpreted,
/// form, formation, progression, level, mixed level, mixer, status, rating,
/// tags, tunes, meter, key, Barnes reference, a square's kind, repeat order,
/// new partner and singing call (blank for another form), sources, hook,
/// calling notes,
/// walkthrough, figures, then one per shared custom field. The two dates are
/// written as [PartialDate.serialize] writes them (`YYYY`, `YYYY-MM` or
/// `YYYY-MM-DD`), so any spreadsheet reads them the same way. The headers
/// follow the UI language; the separator and encoding never do ([encodeCsv]).
String buildDancesCsv(
  Iterable<Dance> dances, {
  required AppLocalizations l10n,
  required DialectsByForm dialects,
  required FigureRenderer renderer,
  bool canonicalizeDiscouragedTerms = false,
  DancesCsvLookups lookups = const DancesCsvLookups(),
}) => encodeCsv(
  buildDancesCsvRows(
    dances,
    l10n: l10n,
    dialects: dialects,
    renderer: renderer,
    canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    lookups: lookups,
  ),
);

/// The header and one row per dance that [buildDancesCsv] encodes: plain
/// strings, so [encodeCsv] can run on another isolate while everything that
/// needs [l10n] (which cannot cross an isolate) has already been resolved here.
///
/// A custom field's header is its label, made unique and distinct from every
/// built-in column by [customFieldCsvHeaders] (labels are not unique).
List<List<String>> buildDancesCsvRows(
  Iterable<Dance> dances, {
  required AppLocalizations l10n,
  required DialectsByForm dialects,
  required FigureRenderer renderer,
  bool canonicalizeDiscouragedTerms = false,
  DancesCsvLookups lookups = const DancesCsvLookups(),
}) {
  final sharedFields = [
    for (final field in lookups.customFields)
      if (customFieldLeavesIn(field, ArchiveSerializationMode.share)) field,
  ];
  final customHeaders = customFieldCsvHeaders(
    sharedFields,
    csvReservedHeaders([l10n, AppLocalizationsEn()]),
  );
  final labels = danceExportLabels(l10n);
  final sorted = [...dances]
    ..sort((a, b) {
      // Accents folded, as the Collection sorts, so École files with E.
      final byTitle = foldForTitleMatch(
        a.title,
      ).compareTo(foldForTitleMatch(b.title));
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });

  List<String> namesOf(List<String> ids) => [
    for (final id in ids)
      if (lookups.choreographersById[id] case final person?)
        if (sanitizeChoreographerForShare(person).name.trim() case final name
            when name.isNotEmpty)
          name,
  ];

  String yesNo(bool value) => value ? l10n.commonYes : l10n.commonNo;

  String customValue(CustomFieldDef field, Dance dance) {
    final value = dance.customFields
        .where((v) => v.fieldId == field.id)
        .firstOrNull
        ?.value;
    return value == null ? '' : formatCustomFieldValue(l10n, value);
  }

  final header = [
    l10n.csvColumnTitle,
    l10n.csvColumnAuthors,
    l10n.csvColumnComposed,
    l10n.csvColumnInterpreters,
    l10n.csvColumnInterpreted,
    l10n.csvColumnForm,
    l10n.csvColumnFormation,
    l10n.csvColumnProgression,
    l10n.csvColumnLevel,
    l10n.csvColumnMixedLevel,
    l10n.csvColumnMixer,
    l10n.csvColumnStatus,
    l10n.csvColumnRating,
    l10n.csvColumnTags,
    l10n.csvColumnTunes,
    l10n.csvColumnMeter,
    l10n.csvColumnKey,
    l10n.csvColumnBarnes,
    l10n.danceEditorSquareKindLabel,
    l10n.danceEditorRepeatOrderLabel,
    l10n.danceEditorNewPartnerLabel,
    l10n.danceEditorSingingLabel,
    l10n.csvColumnSources,
    l10n.csvColumnHook,
    l10n.csvColumnCallingNotes,
    l10n.csvColumnWalkthrough,
    l10n.csvColumnFigures,
    for (final field in sharedFields) customHeaders[field.id]!,
  ];

  final rows = <List<String>>[header];
  for (final dance in sorted) {
    final authorNames = namesOf(dance.authorIds);
    final dialect = dialects.forDance(dance);
    final cardDialect = dialectForDance(
      dialect,
      title: dance.title,
      authorNames: authorNames,
    );
    final content = DanceCardContent.build(
      dance,
      dialect: dialect,
      authorNames: authorNames,
      formationLabel: '',
      statusLabel: '',
      renderer: renderer,
      labels: labels,
      canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      fields: spreadsheetDanceFields,
    );
    final levelId = dance.difficultyLevelId;
    final level = levelId == null
        ? null
        : lookups.difficultyLevelsById[levelId] ??
              DifficultyLevel.knownForId(levelId);
    String renderSquareText(String text) => canonicalizeDiscouragedTerms
        ? renderer.renderFreeTextWithCanonicalDiscouragedTerms(
            text,
            cardDialect,
          )
        : renderer.renderFreeText(text, cardDialect);
    rows.add([
      dance.title.trim(),
      joinNameList(authorNames),
      dance.composedOn?.serialize() ?? '',
      joinNameList(namesOf(dance.interpreterIds)),
      dance.interpretedOn?.serialize() ?? '',
      danceFormLabel(l10n, dance.form),
      formationDisplayLabel(
        l10n,
        dance.formation,
        renderer,
        cardDialect,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      ),
      progressionLabel(l10n, dance.progression),
      level == null ? '' : danceLevelLabel(l10n, level),
      yesNo(dance.mixedLevel),
      yesNo(dance.mixer),
      danceStatusLabel(l10n, dance.status),
      dance.rating?.toString() ?? '',
      joinNameList([
        for (final id in dance.tagIds)
          if (lookups.tagsById[id] case final tag?) tag.name,
      ]),
      joinNameList(content.tuneNames),
      dance.meter.trim(),
      dance.musicalKey.trim(),
      formHasBarnesReference(dance.form) ? dance.barnesReference.trim() : '',
      // A square's own fields (ADR-007 §8.1): kept for every form, but they
      // mean something only for a square, so another form's cells are blank.
      ...(dance.form == DanceForm.square
          ? [
              squareKindLabel(l10n, dance.squareKind),
              // An `other` text is prose, worded as the dance page words it.
              dance.repeatOrder == SquareRepeatOrder.other &&
                      dance.repeatOrderText.isNotEmpty
                  ? renderSquareText(dance.repeatOrderText)
                  : squareRepeatOrderLabel(l10n, dance.repeatOrder),
              dance.newPartner == SquareNewPartner.other &&
                      dance.newPartnerText.isNotEmpty
                  ? renderSquareText(dance.newPartnerText)
                  : squareNewPartnerLabel(l10n, dance.newPartner, cardDialect),
              // Only a main part is sung; the page and editor agree.
              yesNo(dance.singing && dance.squareKind == SquareKind.main),
            ]
          : const ['', '', '', '']),
      danceSourceLines(l10n, dance, (id) => lookups.sourcesById[id]).join('\n'),
      content.hook ?? '',
      content.callingNotes ?? '',
      content.walkthrough ?? '',
      danceCardFigureLines(
        dance,
        content,
        renderer: renderer,
        labels: labels,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      ).join('\n'),
      for (final field in sharedFields) customValue(field, dance),
    ]);
  }
  return rows;
}

/// The file name for a dances CSV exported on [date]: `<stem>_yyyy-MM-dd.csv`,
/// path-safe. [stem] is the localized word for dances.
String dancesCsvFileName(String stem, DateTime date) =>
    '${shareFileBaseName(stem, fallback: 'dances', eventDate: date)}'
    '.$csvExtension';
