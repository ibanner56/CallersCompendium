import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
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

  /// Reads every record the dances may refer to. Deleted people are included,
  /// so a dance whose author was deleted still shows the name it shows on
  /// screen.
  static Future<DancesCsvLookups> load(CompendiumRepositories repos) async {
    final choreographers = await repos.choreographers.listAll(
      includeDeleted: true,
    );
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
/// Columns: title, authors, interpreters, form, formation, progression, level,
/// mixed level, mixer, status, rating, tags, tunes, meter, key, sources, hook,
/// calling notes, walkthrough, figures, then one per shared custom field. The
/// headers follow the UI language; the separator and encoding never do
/// ([encodeCsv]).
String buildDancesCsv(
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
  final labels = danceExportLabels(l10n);
  final sorted = [...dances]
    ..sort((a, b) {
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
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
    return switch (value) {
      null => '',
      final bool b => yesNo(b),
      final num n => customNumberText(n),
      _ => value.toString(),
    };
  }

  final header = [
    l10n.csvColumnTitle,
    l10n.csvColumnAuthors,
    l10n.csvColumnInterpreters,
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
    l10n.csvColumnSources,
    l10n.csvColumnHook,
    l10n.csvColumnCallingNotes,
    l10n.csvColumnWalkthrough,
    l10n.csvColumnFigures,
    for (final field in sharedFields) field.label,
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
      fields: DanceShareField.all,
    );
    final levelId = dance.difficultyLevelId;
    final level = levelId == null
        ? null
        : lookups.difficultyLevelsById[levelId] ??
              DifficultyLevel.knownForId(levelId);
    rows.add([
      dance.title.trim(),
      authorNames.join(', '),
      namesOf(dance.interpreterIds).join(', '),
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
      [
        for (final id in dance.tagIds)
          if (lookups.tagsById[id] case final tag?) tag.name,
      ].join(', '),
      content.tuneNames.join(', '),
      dance.meter.trim(),
      dance.musicalKey.trim(),
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
  return encodeCsv(rows);
}

/// The file name for a dances CSV exported on [date]: `<stem>_yyyy-MM-dd.csv`,
/// path-safe. [stem] is the localized word for dances.
String dancesCsvFileName(String stem, DateTime date) =>
    '${shareFileBaseName(stem, fallback: 'dances', eventDate: date)}'
    '.$csvExtension';
