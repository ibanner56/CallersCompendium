import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../search/facet_labels.dart';
import '../sync/sync_setting_labels.dart';
import '../theme/app_spacing.dart';
import '../widgets/program_status_labels.dart';

/// Names for the records a conflicted record refers to by id — its authors,
/// tags, level, custom fields, a program's dances and venue — so a comparison
/// can say "Tags: Easy, Mixer" rather than list identifiers.
///
/// Loaded once when the conflict choice opens, only when a record (not just
/// settings) is in conflict. Everything is read from this device's own
/// library; nothing is fetched.
class SyncConflictLookups {
  const SyncConflictLookups({
    this.choreographers = const {},
    this.tags = const {},
    this.levels = const {},
    this.customFields = const {},
    this.dances = const {},
    this.venues = const {},
    this.sources = const {},
  });

  final Map<String, String> choreographers;
  final Map<String, String> tags;
  final Map<String, String> levels;
  final Map<String, String> customFields;
  final Map<String, String> dances;
  final Map<String, String> venues;
  final Map<String, String> sources;

  static Future<SyncConflictLookups> load(CompendiumRepositories repos) async {
    return SyncConflictLookups(
      choreographers: {
        for (final c in await repos.choreographers.listAll()) c.id: c.name,
      },
      tags: {for (final t in await repos.tags.listAll()) t.id: t.name},
      levels: {
        for (final l in await repos.difficultyLevels.listAll()) l.id: l.label,
      },
      customFields: {
        for (final f in await repos.customFieldDefs.listAll()) f.id: f.label,
      },
      dances: {
        for (final d in await repos.dances.listIdsAndTitles()) d.id: d.title,
      },
      venues: {for (final v in await repos.venues.listAll()) v.id: v.name},
      sources: {
        for (final s in await repos.publishedSources.listAll()) s.id: s.title,
      },
    );
  }
}

/// When a version was last changed, for telling versions apart.
String syncConflictWhen(BuildContext context, DateTime when) =>
    DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm().format(when.toLocal());

/// The fields of [kind] a comparison shows, in reading order, with their
/// labels. Fields not listed — provenance, internal flags — are left out:
/// they are never what a user is choosing between.
Map<String, String> _fieldLabels(AppLocalizations l10n, SyncRecordKind kind) =>
    switch (kind) {
      SyncRecordKind.dance => {
        'title': l10n.programsTitleLabel,
        'authorIds': l10n.danceEditorAuthorsLabel,
        'form': l10n.danceEditorFormLabel,
        'formation': l10n.danceEditorFormationLabel,
        'progression': l10n.commonProgression,
        'phraseStructure': l10n.danceEditorPhraseStructureLabel,
        'figures': l10n.danceSectionFigures,
        'hook': l10n.danceEditorHookLabel,
        'callingNotes': l10n.danceEditorCallingNotesLabel,
        'walkthrough': l10n.danceEditorWalkthroughLabel,
        'difficultyLevelId': l10n.danceEditorLevelLabel,
        'mixedLevel': l10n.commonMixedLevel,
        'mixer': l10n.commonMixer,
        'status': l10n.danceEditorStatusLabel,
        'rating': l10n.danceEditorRatingLabel,
        'tunes': l10n.danceEditorTunesLabel,
        'tagIds': l10n.danceEditorTagsLabel,
        'customFields': l10n.danceEditorCustomFieldsLabel,
        'links': l10n.danceEditorLinksLabel,
        'sourceCitations': l10n.danceEditorPublishedSourcesLabel,
        'composedOn': l10n.danceEditorComposedLabel,
        'revisedOn': l10n.danceEditorRevisedLabel,
      },
      SyncRecordKind.program => {
        'title': l10n.programsTitleLabel,
        'eventDate': l10n.programsEventDateLabel,
        'venue': l10n.programsVenueLabel,
        'venueId': l10n.programsVenueLabel,
        'band': l10n.programsBandLabel,
        'caller': l10n.programsCallerLabel,
        'dancerLevel': l10n.programsDancerLevelLabel,
        'status': l10n.programsStatusFieldLabel,
        'notes': l10n.programsNotesLabel,
        'slots': l10n.programsSlotsLabel,
      },
      SyncRecordKind.choreographer ||
      SyncRecordKind.tag ||
      SyncRecordKind.venue => {
        'name': l10n.syncConflictFieldName,
        'website': l10n.danceEditorWebsiteLabel,
        'notes': l10n.danceEditorNotesLabel,
      },
      _ => const {},
    };

/// The labelled fields that differ between [local] and [other], or every
/// differing field when the kind has no labels (shown by their own names).
List<({String key, String label})> syncConflictDifferingFields(
  AppLocalizations l10n,
  SyncRecordKind kind,
  Map<String, Object?>? local,
  Map<String, Object?>? other,
) {
  final labels = _fieldLabels(l10n, kind);
  final differing = syncDifferingFields(local, other).toSet();
  if (labels.isEmpty) {
    return [for (final key in differing) (key: key, label: key)];
  }
  final shown = <({String key, String label})>[];
  final seenLabels = <String>{};
  for (final entry in labels.entries) {
    if (!differing.contains(entry.key)) continue;
    if (seenLabels.add(entry.value)) {
      shown.add((key: entry.key, label: entry.value));
    }
  }
  return shown;
}

/// One line summarising how a version differs from this device's, for the
/// compact list. Null when there is nothing more useful to say than the
/// versions themselves (a single-valued setting).
String? syncConflictSummary(
  AppLocalizations l10n,
  SyncConflictGroup group,
  SyncReviewQueueItem candidate,
) {
  final other = candidate.candidate?.body;
  if (group.kind == SyncRecordKind.setting) {
    final diff = compareSyncCollection(
      group.recordId,
      group.localBody?['value'],
      other?['value'],
    );
    if (diff == null || diff.isEmpty) return null;
    return [
      if (diff.onlyLocal.isNotEmpty)
        l10n.syncConflictSummaryOnlyHere(diff.onlyLocal.length),
      if (diff.onlyOther.isNotEmpty)
        l10n.syncConflictSummaryOnlyThere(diff.onlyOther.length),
      if (diff.changed.isNotEmpty)
        l10n.syncConflictSummaryChanged(diff.changed.length),
    ].join(' · ');
  }
  final fields = syncConflictDifferingFields(
    l10n,
    group.kind,
    group.localBody,
    other,
  );
  if (fields.isEmpty) return null;
  const shown = 3;
  final names = fields.take(shown).map((f) => f.label).join(', ');
  return l10n.syncConflictDiffersInFields(
    fields.length > shown
        ? l10n.syncConflictValueNamesAndMore(names, fields.length - shown)
        : names,
  );
}

/// The full comparison of one conflicted record: every way each other version
/// differs from this device's, item by item, in the user's words.
class SyncConflictComparison extends StatelessWidget {
  const SyncConflictComparison({
    super.key,
    required this.group,
    required this.lookups,
  });

  final SyncConflictGroup group;
  final SyncConflictLookups lookups;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbered = group.candidates.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in group.candidates.indexed) ...[
          if (numbered)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                l10n.syncConflictComparedWith(
                  l10n.syncConflictOtherDeviceNumbered(index + 1),
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ..._compare(context, l10n, item.candidate?.body),
        ],
      ],
    );
  }

  List<Widget> _compare(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, Object?>? other,
  ) {
    if (group.kind == SyncRecordKind.setting) {
      final diff = compareSyncCollection(
        group.recordId,
        group.localBody?['value'],
        other?['value'],
      );
      if (diff != null) return _collection(context, l10n, diff);
      return [
        _versions(
          context,
          l10n,
          label: null,
          local: syncSettingValueText(l10n, group.localBody?['value']),
          other: syncSettingValueText(l10n, other?['value']),
        ),
      ];
    }
    final fields = syncConflictDifferingFields(
      l10n,
      group.kind,
      group.localBody,
      other,
    );
    if (fields.isEmpty) {
      return [_note(context, l10n.syncConflictNothingToShow)];
    }
    return [
      for (final field in fields)
        if (field.key == 'figures')
          ..._figures(context, l10n, field.label, other)
        else if (field.key == 'slots')
          ..._slots(context, l10n, field.label, other)
        else
          _versions(
            context,
            l10n,
            label: field.label,
            local: _value(context, l10n, field.key, group.localBody),
            other: _value(context, l10n, field.key, other),
          ),
    ];
  }

  List<Widget> _collection(
    BuildContext context,
    AppLocalizations l10n,
    SyncCollectionDiff diff,
  ) {
    String name(SyncCollectionEntry entry) =>
        entry.label ?? _entryText(context, l10n, entry);
    return [
      if (diff.onlyLocal.isNotEmpty)
        _list(context, l10n.syncConflictOnlyHereHeader, [
          for (final e in diff.onlyLocal) name(e),
        ]),
      if (diff.onlyOther.isNotEmpty)
        _list(context, l10n.syncConflictOnlyThereHeader, [
          for (final e in diff.onlyOther) name(e),
        ]),
      if (diff.changed.isNotEmpty) ...[
        _header(context, l10n.syncConflictDifferentHeader),
        for (final pair in diff.changed)
          _versions(
            context,
            l10n,
            label: pair.local.label,
            local: _entryText(context, l10n, pair.local),
            other: _entryText(context, l10n, pair.other),
          ),
      ],
      if (diff.same > 0) _note(context, l10n.syncConflictSameCount(diff.same)),
    ];
  }

  /// What one collection entry says, for comparing two versions of it.
  String _entryText(
    BuildContext context,
    AppLocalizations l10n,
    SyncCollectionEntry entry,
  ) {
    final dialect = ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
    final value = entry.value;
    switch (group.recordId) {
      case 'walkthrough_snippets':
        return value is String
            ? _renderer.renderFreeText(value, dialect)
            : l10n.syncConflictValueNotSet;
      case 'shorthand_mappings':
        final figures = value is Map ? value['figures'] : null;
        return _figureText(figures, dialect) ?? l10n.syncConflictValueNotSet;
      default:
        // A dialect or theme: name what differs inside it is beyond this
        // view; its name and a count of its parts tell the two apart.
        return entry.label ?? syncSettingValueText(l10n, value);
    }
  }

  List<Widget> _figures(
    BuildContext context,
    AppLocalizations l10n,
    String label,
    Map<String, Object?>? other,
  ) {
    final dialect = ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
    final mine = _sectionedLines(group.localBody, dialect);
    final theirs = _sectionedLines(other, dialect);
    if (mine == null || theirs == null) {
      return [_note(context, l10n.syncConflictFiguresUnreadable)];
    }
    final rows = <Widget>[_header(context, label)];
    final count = mine.length > theirs.length ? mine.length : theirs.length;
    for (var i = 0; i < count; i++) {
      final left = i < mine.length ? mine[i] : null;
      final right = i < theirs.length ? theirs[i] : null;
      if (left?.text == right?.text && left?.section == right?.section) {
        continue;
      }
      rows.add(
        _versions(
          context,
          l10n,
          label: left?.section ?? right?.section,
          local: left?.text ?? l10n.syncConflictValueNotSet,
          other: right?.text ?? l10n.syncConflictValueNotSet,
        ),
      );
    }
    return rows;
  }

  /// The dance's figures as section-labelled lines, or null when they cannot
  /// be read.
  List<({String section, String text})>? _sectionedLines(
    Map<String, Object?>? body,
    Dialect dialect,
  ) {
    final raw = body?['figures'];
    if (raw == null) return const [];
    if (raw is! List) return null;
    final figures = <Figure>[];
    try {
      for (final item in raw) {
        figures.add(figureFromJson(Map<String, Object?>.from(item as Map)));
      }
    } on Object {
      // diagnostics: silent — surfaced as "The figures can't be compared here."
      return null;
    }
    final phrase = body?['phraseStructure'];
    final sections = deriveSections(
      figures,
      PhraseStructure.parseOrStandard(phrase is String ? phrase : ''),
    );
    return [
      for (final s in sections)
        (section: s.label, text: _renderer.renderSummary(s.figure, dialect)),
    ];
  }

  String? _figureText(Object? raw, Dialect dialect) {
    if (raw is! List) return null;
    try {
      return [
        for (final item in raw)
          _renderer.renderSummary(
            figureFromJson(Map<String, Object?>.from(item as Map)),
            dialect,
          ),
      ].join('; ');
    } on Object {
      // diagnostics: silent — surfaced as "Not set" for that shorthand entry
      return null;
    }
  }

  List<Widget> _slots(
    BuildContext context,
    AppLocalizations l10n,
    String label,
    Map<String, Object?>? other,
  ) {
    List<String> titles(Map<String, Object?>? body) {
      final slots = body?['slots'];
      if (slots is! List) return const [];
      final ordered =
          [
            for (final slot in slots)
              if (slot is Map) Map<String, Object?>.from(slot),
          ]..sort(
            (a, b) => ((a['position'] as num?) ?? 0).compareTo(
              (b['position'] as num?) ?? 0,
            ),
          );
      return [
        for (final slot in ordered)
          switch (slot['danceId']) {
            final String id =>
              lookups.dances[id] ?? l10n.programsDeletedDanceFallback,
            _ =>
              (slot['text'] as String?) ?? l10n.programsUntitledDanceFallback,
          },
      ];
    }

    final mine = titles(group.localBody);
    final theirs = titles(other);
    final onlyMine = [
      for (final t in mine)
        if (!theirs.contains(t)) t,
    ];
    final onlyTheirs = [
      for (final t in theirs)
        if (!mine.contains(t)) t,
    ];
    return [
      _header(context, label),
      if (onlyMine.isNotEmpty)
        _list(context, l10n.syncConflictOnlyHereHeader, onlyMine),
      if (onlyTheirs.isNotEmpty)
        _list(context, l10n.syncConflictOnlyThereHeader, onlyTheirs),
      if (onlyMine.isEmpty && onlyTheirs.isEmpty)
        _note(
          context,
          mine.length == theirs.length
              ? l10n.syncConflictSlotsReordered
              : l10n.syncConflictSlotsDetailsDiffer,
        ),
    ];
  }

  /// One field's value, in words, for the version [body].
  String _value(
    BuildContext context,
    AppLocalizations l10n,
    String key,
    Map<String, Object?>? body,
  ) {
    final value = body?[key];
    if (value == null || value == '' || (value is List && value.isEmpty)) {
      return l10n.syncConflictValueNotSet;
    }
    String names(Map<String, String> lookup) => [
      for (final id in value as List)
        lookup[id] ?? l10n.syncConflictUnknownItem,
    ].join(', ');
    try {
      switch (key) {
        case 'authorIds':
          return names(lookups.choreographers);
        case 'tagIds':
          return names(lookups.tags);
        case 'difficultyLevelId':
          return lookups.levels[value] ?? l10n.syncConflictUnknownItem;
        case 'venueId':
          return lookups.venues[value] ?? l10n.syncConflictUnknownItem;
        case 'form':
          return danceFormLabel(l10n, DanceForm.values.byName(value as String));
        case 'progression':
          return progressionLabel(
            l10n,
            Progression.values.byName(value as String),
          );
        case 'status':
          return group.kind == SyncRecordKind.program
              ? programStatusLabel(
                  l10n,
                  ProgramStatus.values.byName(value as String),
                )
              : danceStatusLabel(
                  l10n,
                  DanceStatus.values.byName(value as String),
                );
        case 'formation':
          final map = value as Map;
          return formationLabel(
            l10n,
            Formation(
              FormationShape.values.byName(map['shape'] as String),
              detail: map['detail'] as String?,
            ),
          );
        case 'customFields':
          return [
            for (final field in value as List)
              if (field is Map)
                l10n.syncConflictFieldValue(
                  lookups.customFields[field['fieldId']] ??
                      l10n.syncConflictUnknownItem,
                  '${field['value']}',
                ),
          ].join('; ');
        case 'sourceCitations':
          return [
            for (final c in value as List)
              if (c is Map)
                lookups.sources[c['sourceId']] ?? l10n.syncConflictUnknownItem,
          ].join(', ');
        case 'links':
          return [
            for (final link in value as List)
              if (link is Map)
                (link['label'] as String?) ??
                    (link['url'] as String?) ??
                    lookups.dances[link['targetDanceId']] ??
                    l10n.syncConflictUnknownItem,
          ].join(', ');
        case 'eventDate':
          return DateFormat.yMMMd(
            Localizations.localeOf(context).toString(),
          ).format(DateTime.parse(value as String).toLocal());
      }
    } on Object {
      // diagnostics: silent — a value this view cannot name falls through to
      // the plain rendering below; the merge already admitted it.
    }
    if (value is String) {
      final dialect =
          ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
      return _renderer.renderFreeText(value, dialect);
    }
    return syncSettingValueText(l10n, value);
  }

  Widget _versions(
    BuildContext context,
    AppLocalizations l10n, {
    required String? label,
    required String local,
    required String other,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) Text(label, style: theme.textTheme.labelLarge),
          Text(
            l10n.syncConflictVersionLine(l10n.syncConflictThisDevice, local),
          ),
          Text(
            l10n.syncConflictVersionLine(l10n.syncConflictOtherDevice, other),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

  Widget _list(BuildContext context, String header, List<String> items) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(header, style: Theme.of(context).textTheme.labelLarge),
            for (final item in items)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: AppSpacing.xs),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  Expanded(child: Text(item)),
                ],
              ),
          ],
        ),
      );

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);
}
