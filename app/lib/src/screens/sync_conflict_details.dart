import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../data/user_figures_scope.dart';
import '../data/active_dialect_scope.dart';
import '../data/app_theme_labels_l10n.dart';
import '../data/custom_theme.dart';
import '../glossary/figure_titles.dart';
import '../search/facet_labels.dart';
import '../sync/sync_setting_labels.dart';
import '../theme/app_spacing.dart';
import '../widgets/compound_argument_editor.dart';
import '../widgets/program_status_labels.dart';
import '../widgets/provenance_labels.dart';

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

/// A program's event date as the calendar day it names. The editor stores
/// the chosen day as midnight UTC, so the day is read in UTC: converting to
/// local time would show the day before anywhere west of Greenwich.
DateTime syncConflictCalendarDate(String stored) {
  final utc = DateTime.parse(stored).toUtc();
  return DateTime(utc.year, utc.month, utc.day);
}

/// A colour as a hex code, with its opacity only when it is not opaque.
String syncConflictColourText(int argb) {
  String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  final alpha = (argb >> 24) & 0xff;
  final rgb =
      '#${hex((argb >> 16) & 0xff)}${hex((argb >> 8) & 0xff)}${hex(argb & 0xff)}';
  return alpha == 0xff ? rgb : '$rgb${hex(alpha)}';
}

typedef _FigureLine = ({
  String section,
  String text,
  String data,
  Figure figure,
});

/// [text] stored in canonical role words, as the active dialect reads it: how
/// the user's own figures and notes (#709) are shown everywhere else.
String syncConflictFreeText(BuildContext context, String text) =>
    SyncConflictComparison._renderer.renderFreeText(
      text,
      ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins,
    );

/// The built-in figure [figureId] names — a figure note's record id (#709) —
/// exactly as the Glossary heads it in the active dialect, a colliding alias
/// qualified by the values it pins ([glossaryFigureTitle]); or null when the
/// Glossary no longer lists it (such a note is kept and not shown).
String? syncConflictFigureName(BuildContext context, String figureId) {
  if (!shippedFigureGlossaryEntries.any((e) => e.id == figureId)) return null;
  return glossaryFigureTitle(
    AppLocalizations.of(context),
    figureId,
    shippedFigureGlossaryEntries,
    ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins,
  );
}

/// When a version was last changed, for telling versions apart.
String syncConflictWhen(BuildContext context, DateTime when) =>
    DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_jm().format(when.toLocal());

/// The fields of [kind] a comparison shows, in reading order, with their
/// labels: exactly core's [syncUserVisibleFields], which the merge also uses
/// to decide whether a tie needs the user at all. Fields not listed —
/// provenance details, internal flags — are left out: they are never what a
/// user is choosing between.
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
        'provenance': l10n.syncConflictFieldProvenance,
      },
      SyncRecordKind.program => {
        'title': l10n.programsTitleLabel,
        'eventDate': l10n.programsEventDateLabel,
        // The linked venue and the free-text venue are shown together, as
        // one row: the program display prefers the linked one.
        'venue': l10n.programsVenueLabel,
        'band': l10n.programsBandLabel,
        'caller': l10n.programsCallerLabel,
        'dancerLevel': l10n.programsDancerLevelLabel,
        'status': l10n.programsStatusFieldLabel,
        'notes': l10n.programsNotesLabel,
        'slots': l10n.programsSlotsLabel,
        'hideAlternates': l10n.programsHideAlternatesTitle,
        'dialectName': l10n.programsDialectFieldLabel,
        'payMinorUnits': l10n.programsPayLabel,
        'payCurrency': l10n.programsPayCurrencyLabel,
      },
      SyncRecordKind.choreographer => {
        'name': l10n.syncConflictFieldName,
        'website': l10n.danceEditorWebsiteLabel,
        'notes': l10n.danceEditorNotesLabel,
      },
      SyncRecordKind.tag => {
        'name': l10n.syncConflictFieldName,
        'color': l10n.syncConflictFieldColour,
      },
      // One of the user's own figures and the notes on a shipped one (#709),
      // labelled as the figure editor and the Glossary label them.
      SyncRecordKind.glossaryEntry => {
        'name': l10n.compoundEditorName,
        'definition': l10n.compoundEditorDefinition,
        'description': l10n.compoundEditorDescription,
        'keywords': l10n.compoundEditorKeywords,
        'notes': l10n.compoundEditorNotes,
        'payload': l10n.glossaryEntryKindHeading,
      },
      SyncRecordKind.figureNote => {'notes': l10n.glossaryNotes},
      SyncRecordKind.venue => {
        'name': l10n.syncConflictFieldName,
        'eventName': l10n.venueEditorEventNameLabel,
        'sponsor': l10n.venueEditorSponsorLabel,
        'time': l10n.venueEditorTimeLabel,
        'genericSchedule': l10n.venueEditorScheduleLabel,
        'price': l10n.venueEditorPriceLabel,
        'website': l10n.venueEditorWebsiteLabel,
        'notes': l10n.danceEditorNotesLabel,
      },
      _ => const {},
    };

/// The labelled fields that differ between [local] and [other], or every
/// differing field when the kind has no labels (shown by their own names).
/// Both are compared as [syncUserVisibleBody] reads them, with [aliases], so
/// a reference to a merged-away record is not a difference.
List<({String key, String label})> syncConflictDifferingFields(
  AppLocalizations l10n,
  SyncRecordKind kind,
  Map<String, Object?>? local,
  Map<String, Object?>? other, {
  Map<SyncRecordKind, Map<String, String>> aliases = const {},
}) {
  final labels = _fieldLabels(l10n, kind);
  final differing = syncDifferingFields(
    local == null ? null : syncUserVisibleBody(kind, local, aliases: aliases),
    other == null ? null : syncUserVisibleBody(kind, other, aliases: aliases),
  ).toSet();
  if (labels.isEmpty) {
    return [for (final key in differing) (key: key, label: key)];
  }
  if (kind == SyncRecordKind.program && differing.contains('venueId')) {
    differing.add('venue');
  }
  return [
    for (final entry in labels.entries)
      if (differing.contains(entry.key)) (key: entry.key, label: entry.value),
  ];
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
    aliases: group.aliases,
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

  /// A version as the comparison reads it: citing the records that
  /// merged-away ones became, so each is named rather than shown as unknown.
  Map<String, Object?>? _resolved(Map<String, Object?>? body) =>
      body == null ? null : syncResolveComparedReferences(body, group.aliases);

  Map<String, Object?>? get _local => _resolved(group.localBody);

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
          ..._compare(context, l10n, _resolved(item.candidate?.body)),
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
        _local?['value'],
        other?['value'],
      );
      if (diff != null) return _collection(context, l10n, diff);
      return [
        _versions(
          context,
          l10n,
          label: null,
          local: syncSettingValueText(l10n, _local?['value']),
          other: syncSettingValueText(l10n, other?['value']),
        ),
      ];
    }
    final fields = syncConflictDifferingFields(
      l10n,
      group.kind,
      _local,
      other,
      aliases: group.aliases,
    );
    if (fields.isEmpty) {
      return [_note(context, l10n.syncConflictNothingToShow)];
    }
    return [
      for (final field in fields)
        if (field.key == 'payload' &&
            group.kind == SyncRecordKind.glossaryEntry)
          _compound(context, l10n, field.label, other)
        else if (field.key == 'figures')
          ..._figures(context, l10n, field.label, other)
        else if (field.key == 'slots')
          ..._slots(context, l10n, field.label, other)
        else
          _versions(
            context,
            l10n,
            label: field.label,
            local: _value(context, l10n, field.key, _local),
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
          ..._changedEntry(context, l10n, pair.local, pair.other),
      ],
      if (diff.same > 0) _note(context, l10n.syncConflictSameCount(diff.same)),
    ];
  }

  /// Rows for one collection entry both versions have, but differently. A
  /// dialect or theme is compared part by part: its name alone would read
  /// the same on both sides.
  List<Widget> _changedEntry(
    BuildContext context,
    AppLocalizations l10n,
    SyncCollectionEntry local,
    SyncCollectionEntry other,
  ) {
    final parts = switch (group.recordId) {
      'custom_dialects' => _dialectParts(
        l10n,
        local.value,
        other.value,
        keyName: (key) => _dialectKeyName(context, l10n, key),
        wording: (key, stored, dialect) =>
            _dialectWording(context, key, stored, dialect),
      ),
      'custom_themes' => _themeParts(l10n, local.value, other.value),
      _ => null,
    };
    if (parts == null || parts.isEmpty) {
      return [
        _versions(
          context,
          l10n,
          label: local.label,
          local: _entryText(context, l10n, local),
          other: _entryText(context, l10n, other),
        ),
      ];
    }
    return [
      for (final part in parts)
        _versions(
          context,
          l10n,
          label: local.label == null
              ? part.label
              : l10n.syncConflictFieldValue(local.label!, part.label),
          local: part.local,
          other: part.other,
        ),
    ];
  }

  /// How a dialect's key reads: a figure of your own's `userFigure:<id>` by
  /// the figure's name, or a note that it isn't on this device (#1023); any
  /// other key as it is.
  String _dialectKeyName(
    BuildContext context,
    AppLocalizations l10n,
    String key,
  ) {
    if (!isUserFigureKey(key)) return key;
    final view = UserFiguresScope.catalogOf(
      context,
    )[key.substring(userFigureRefPrefix.length)];
    if (view == null) return l10n.dialectEditorUserFigureGone;
    return _renderer.renderFreeText(
      view.name,
      ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins,
    );
  }

  /// The stored wording [stored] for the move or figure [key], as the dialect
  /// editor shows it: its conditions in [dialect]'s words.
  String _dialectWording(
    BuildContext context,
    String key,
    String stored,
    Dialect dialect,
  ) {
    if (!isUserFigureKey(key)) {
      return wordingForEditing(
        stored,
        _renderer.moveWordingVocabulary(key, dialect),
      );
    }
    final definition = UserFiguresScope.catalogOf(
      context,
    )[key.substring(userFigureRefPrefix.length)]?.definition;
    return wordingForEditing(
      stored,
      definition == null
          ? WordingVocabulary(const [])
          : _renderer.userFigureWordingVocabulary(definition, dialect),
    );
  }

  /// The parts of a dialect that differ: each section, showing only the
  /// terms that differ within it, each named by [keyName], and each wording
  /// shown by [wording] in its own side's words.
  List<({String label, String local, String other})>? _dialectParts(
    AppLocalizations l10n,
    Object? local,
    Object? other, {
    required String Function(String key) keyName,
    required String Function(String key, String stored, Dialect dialect)
    wording,
  }) {
    if (local is! Map || other is! Map) return null;
    Dialect words(Map<Object?, Object?> json) {
      try {
        return Dialect.fromJson(json.cast<String, Object?>());
      } on Object {
        return Dialect.canonical;
      }
    }

    final localWords = words(local);
    final otherWords = words(other);
    final parts = <({String label, String local, String other})>[];
    if (local['name'] != other['name']) {
      parts.add((
        label: l10n.syncConflictFieldName,
        local: syncSettingValueText(l10n, local['name']),
        other: syncSettingValueText(l10n, other['name']),
      ));
    }
    String term(Object? value) => switch (value) {
      final Map<Object?, Object?> forms => [
        for (final form in [forms['singular'], forms['plural']])
          if (form is String && form.isNotEmpty) form,
      ].join(' / '),
      final String text => text,
      _ => canonicalJson(value),
    };
    void section(
      String label,
      List<String> keys, {
      String? Function(String key, Object? value, Dialect dialect)? show,
    }) {
      final mine = <String, Object?>{};
      final theirs = <String, Object?>{};
      for (final key in keys) {
        if (local[key] case final Map<Object?, Object?> terms) {
          mine.addAll({for (final e in terms.entries) '${e.key}': e.value});
        }
        if (other[key] case final Map<Object?, Object?> terms) {
          theirs.addAll({for (final e in terms.entries) '${e.key}': e.value});
        }
      }
      final names = {...mine.keys, ...theirs.keys}.toList()..sort();
      final differing = [
        for (final name in names)
          if (canonicalJson(mine[name]) != canonicalJson(theirs[name])) name,
      ];
      if (differing.isEmpty) return;
      String side(Map<String, Object?> terms, Dialect dialect) {
        final text = [
          for (final name in differing)
            if (terms.containsKey(name))
              '${keyName(name)} → '
                  '${show?.call(name, terms[name], dialect) ?? term(terms[name])}',
        ].join(', ');
        return text.isEmpty ? l10n.syncConflictValueNotSet : text;
      }

      parts.add((
        label: label,
        local: side(mine, localWords),
        other: side(theirs, otherWords),
      ));
    }

    section(l10n.dialectEditorSectionRoleTerms, ['roles']);
    section(l10n.dialectEditorSectionMoveSubs, ['moves']);
    section(l10n.dialectEditorSectionDancerSubs, ['dancers']);
    section(
      l10n.dialectEditorSectionMoveWordings,
      ['moveWordings', 'moveWordingBranches'],
      // Conditions in words, as the editor shows them; a move's branches
      // each by name.
      show: (key, value, dialect) => switch (value) {
        final String stored => wording(key, stored, dialect),
        final Map<Object?, Object?> branches => [
          for (final MapEntry(key: branch, value: stored) in branches.entries)
            if (stored is String) '$branch: ${wording(key, stored, dialect)}',
        ].join('; '),
        _ => null,
      },
    );
    if (canonicalJson(local['discouragedTerms']) !=
        canonicalJson(other['discouragedTerms'])) {
      parts.add((
        label: l10n.dialectEditorSectionDiscouraged,
        local: syncSettingValueText(l10n, local['discouragedTerms']),
        other: syncSettingValueText(l10n, other['discouragedTerms']),
      ));
    }
    return parts;
  }

  /// The parts of a theme that differ: its name, light or dark, and each
  /// colour that differs, as a hex code.
  List<({String label, String local, String other})>? _themeParts(
    AppLocalizations l10n,
    Object? local,
    Object? other,
  ) {
    if (local is! Map || other is! Map) return null;
    String brightness(Object? value) => switch (value) {
      'dark' => l10n.appThemeGroupDark,
      'light' => l10n.appThemeGroupLight,
      _ => syncSettingValueText(l10n, value),
    };
    String colour(Object? value) => value is int
        ? syncConflictColourText(value)
        : l10n.syncConflictValueNotSet;
    final mine = local['roles'] is Map
        ? local['roles'] as Map
        : const <Object?, Object?>{};
    final theirs = other['roles'] is Map
        ? other['roles'] as Map
        : const <Object?, Object?>{};
    final known = [for (final role in CustomThemeRoles.all) role.key];
    final keys = [
      ...known,
      for (final key in {...mine.keys, ...theirs.keys})
        if (!known.contains(key)) '$key',
    ];
    return [
      if (local['name'] != other['name'])
        (
          label: l10n.syncConflictFieldName,
          local: syncSettingValueText(l10n, local['name']),
          other: syncSettingValueText(l10n, other['name']),
        ),
      if (local['brightness'] != other['brightness'])
        (
          label: l10n.syncConflictThemeBrightness,
          local: brightness(local['brightness']),
          other: brightness(other['brightness']),
        ),
      for (final key in keys)
        if (mine[key] != theirs[key])
          (
            label: themeEditorRoleLabel(l10n, ColorRole(key, key)),
            local: colour(mine[key]),
            other: colour(theirs[key]),
          ),
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
      case compoundShorthandsSettingKey:
        // One of the user's own figures, by the name the shorthand stored,
        // with the values it gives.
        return compoundShorthandValueText(l10n, value, dialect) ??
            l10n.syncConflictValueNotSet;
      case userFigureShorthandsSettingKey:
        // A use of one of the user's new figures (#1023): the line it would
        // insert, in the figure's current wording, or, when this device can't
        // render it, the figure's stored name and values, as a compound
        // shorthand reads; then its beats, when it sets them.
        final shorthand = UserFigureShorthands.decode([
          value,
        ]).shorthands.firstOrNull;
        if (shorthand == null) return l10n.syncConflictValueNotSet;
        final use = userFigureUseFigure(
          id: shorthand.figureId,
          args: shorthand.args,
          text: shorthand.figureName,
          beats: shorthand.beats,
        );
        final renderer = UserFiguresScope.rendererOf(context);
        final line = renderer.renderUserFigureCanonical(use) != null
            ? renderer.render(use, dialect)
            : compoundShorthandValueText(l10n, value, dialect) ??
                  renderer.render(use, dialect);
        final beats = shorthand.beats;
        return beats == null ? line : '$line · ${l10n.danceFigureBeats(beats)}';
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
    final renderer = UserFiguresScope.rendererOf(context);
    final mine = _sectionedLines(_local, dialect, renderer);
    final theirs = _sectionedLines(other, dialect, renderer);
    if (mine == null || theirs == null) {
      return [_note(context, l10n.syncConflictFiguresUnreadable)];
    }
    final rows = <Widget>[_header(context, label)];
    final count = mine.length > theirs.length ? mine.length : theirs.length;
    for (var i = 0; i < count; i++) {
      final left = i < mine.length ? mine[i] : null;
      final right = i < theirs.length ? theirs[i] : null;
      if (left?.data == right?.data && left?.section == right?.section) {
        continue;
      }
      var localText = left?.text, otherText = right?.text;
      if (left != null && right != null && left.text == right.text) {
        // The same figure in words; what differs is a detail the summary
        // leaves out: a note, its own walkthrough or wording, its beats.
        localText = _figureDetails(l10n, left);
        otherText = _figureDetails(l10n, right);
        if (localText == otherText) {
          localText = left.text;
          otherText = l10n.syncConflictFigureDetailsDiffer(right.text);
        }
      }
      rows.add(
        _versions(
          context,
          l10n,
          label: left?.section ?? right?.section,
          local: localText ?? l10n.syncConflictValueNotSet,
          other: otherText ?? l10n.syncConflictValueNotSet,
        ),
      );
    }
    return rows;
  }

  /// One of the user's own glossary entries, compared by what its payload
  /// says (#709, #1023): a combination's figures in words, then its
  /// parameters; a new figure's wording, then its parameters; a term's dance
  /// form. Its stored payload is text; one this build cannot read is named as
  /// from a newer version, or as needing repair, as the Glossary names it.
  Widget _compound(
    BuildContext context,
    AppLocalizations l10n,
    String label,
    Map<String, Object?>? other,
  ) {
    final dialect = ActiveDialectScope.maybeOf(context) ?? Dialect.larksRobins;
    String describe(Map<String, Object?>? body) {
      if (body == null) return l10n.syncConflictValueNotSet;
      final kind = body['kind'];
      final payload = body['payload'];
      Object? decoded;
      if (payload is String) {
        try {
          decoded = jsonDecode(payload);
        } on FormatException {
          // diagnostics: silent — shown as needing repair, as the Glossary
          // shows it.
          decoded = null;
        }
      }
      if (kind == UserGlossaryEntryKind.term.name) {
        return [
          l10n.glossaryEntryKindTerm,
          l10n.syncConflictFieldValue(
            l10n.glossaryEntryFormLabel,
            glossaryEntryFormLabel(l10n, glossaryEntryForm(decoded)),
          ),
        ].join(' · ');
      }
      if (kind == UserGlossaryEntryKind.customFigure.name) {
        final figure = decodeUserFigureDefinition(decoded);
        if (figure == null) return l10n.glossaryCustomNeedsRepair;
        return [
          l10n.glossaryEntryKindNewFigure,
          // Slots kept as written: a role word never reaches inside a {…}.
          // Its conditions in words, as its editor shows them.
          wordingForEditing(
            mapUserFigureTemplateText(
              figure.template,
              (text) => _renderer.renderFreeText(text, dialect),
            ),
            _renderer.userFigureWordingVocabulary(figure, dialect),
          ),
          if (figure.params.isNotEmpty)
            l10n.syncConflictFieldValue(
              l10n.compoundEditorParams,
              figure.params.map((p) => p.key).join(', '),
            ),
        ].join(' · ');
      }
      if (kind != UserGlossaryEntryKind.compound.name) {
        return l10n.glossaryCustomUnsupported;
      }
      final definition = decodeCompoundDefinition(decoded, contraTaxonomy);
      if (definition == null) return l10n.glossaryCustomNeedsRepair;
      return [
        l10n.glossaryEntryKindCombination,
        definition.figures
            .map((f) => _renderer.renderSummary(f, dialect))
            .join('; '),
        if (definition.params.isNotEmpty)
          l10n.syncConflictFieldValue(
            l10n.compoundEditorParams,
            definition.params.map((p) => p.key).join(', '),
          ),
      ].join(' · ');
    }

    var local = describe(_local), theirs = describe(other);
    if (local == theirs) {
      // The same figures in words; what differs is a detail the summary
      // leaves out, such as which settings a parameter fills.
      theirs = l10n.syncConflictFigureDetailsDiffer(theirs);
    }
    return _versions(context, l10n, label: label, local: local, other: theirs);
  }

  /// A figure in words with the details its summary leaves out.
  String _figureDetails(AppLocalizations l10n, _FigureLine line) {
    final figure = line.figure;
    final beats = figure.params['beats'];
    return [
      line.text,
      if (beats is int) l10n.danceFigureBeats(beats),
      if (figure.note case final note? when note.trim().isNotEmpty)
        l10n.danceFigureNote(note),
      if (figure.walkthroughOverride case final text?
          when text.trim().isNotEmpty)
        l10n.syncConflictFigureWalkthrough(text),
      if (figure.wordingOverride case final text? when text.trim().isNotEmpty)
        l10n.syncConflictFigureWording(text),
    ].join(' · ');
  }

  /// The dance's figures as section-labelled lines, or null when they cannot
  /// be read.
  List<_FigureLine>? _sectionedLines(
    Map<String, Object?>? body,
    Dialect dialect,
    FigureRenderer renderer,
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
        (
          section: s.label,
          text: renderer.renderSummary(s.figure, dialect),
          data: canonicalJson(figureToJson(s.figure)),
          figure: s.figure,
        ),
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
    List<Map<String, Object?>> ordered(Map<String, Object?>? body) {
      final slots = body?['slots'];
      if (slots is! List) return const [];
      return [
        for (final slot in slots)
          if (slot is Map) Map<String, Object?>.from(slot),
      ]..sort(
        (a, b) => ((a['position'] as num?) ?? 0).compareTo(
          (b['position'] as num?) ?? 0,
        ),
      );
    }

    // A slot is the dance it holds, or its text: two dances with the same
    // title are still different dances.
    String identity(Map<String, Object?> slot) => switch (slot['danceId']) {
      final String id => 'd:$id',
      _ => 't:${slot['text'] ?? ''}',
    };
    String title(Map<String, Object?> slot) => switch (slot['danceId']) {
      final String id =>
        lookups.dances[id] ?? l10n.programsDeletedDanceFallback,
      _ => (slot['text'] as String?) ?? l10n.programsUntitledDanceFallback,
    };
    // Each slot keyed by what it holds and which repeat of it it is, so the
    // second of two identical slots is compared with the other's second.
    Map<String, Map<String, Object?>> byOccurrence(
      List<Map<String, Object?>> slots,
    ) {
      final seen = <String, int>{};
      final keyed = <String, Map<String, Object?>>{};
      for (final slot in slots) {
        final id = identity(slot);
        final n = seen.update(id, (n) => n + 1, ifAbsent: () => 0);
        keyed['$id#$n'] = slot;
      }
      return keyed;
    }

    final mine = byOccurrence(ordered(_local));
    final theirs = byOccurrence(ordered(other));
    final onlyMine = [
      for (final e in mine.entries)
        if (!theirs.containsKey(e.key)) title(e.value),
    ];
    final onlyTheirs = [
      for (final e in theirs.entries)
        if (!mine.containsKey(e.key)) title(e.value),
    ];
    final sharedMine = [
      for (final key in mine.keys)
        if (theirs.containsKey(key)) key,
    ];
    final sharedTheirs = [
      for (final key in theirs.keys)
        if (mine.containsKey(key)) key,
    ];
    var reordered = false;
    for (var i = 0; i < sharedMine.length; i++) {
      if (sharedMine[i] != sharedTheirs[i]) reordered = true;
    }
    final detailsDiffer = sharedMine.any(
      (key) => syncDifferingFields(
        mine[key],
        theirs[key],
        ignore: const {'id', 'position'},
      ).isNotEmpty,
    );
    return [
      _header(context, label),
      if (onlyMine.isNotEmpty)
        _list(context, l10n.syncConflictOnlyHereHeader, onlyMine),
      if (onlyTheirs.isNotEmpty)
        _list(context, l10n.syncConflictOnlyThereHeader, onlyTheirs),
      if (reordered) _note(context, l10n.syncConflictSlotsReordered),
      if (detailsDiffer) _note(context, l10n.syncConflictSlotsDetailsDiffer),
    ];
  }

  /// One field's value, in words, for the version [body].
  String _value(
    BuildContext context,
    AppLocalizations l10n,
    String key,
    Map<String, Object?>? body,
  ) {
    if (key == 'venue' && group.kind == SyncRecordKind.program) {
      final linked = body?['venueId'];
      final text = body?['venue'];
      final parts = [
        if (linked is String)
          lookups.venues[linked] ?? l10n.syncConflictUnknownItem,
        if (text is String && text.trim().isNotEmpty) text,
      ];
      return parts.isEmpty ? l10n.syncConflictValueNotSet : parts.join(' · ');
    }
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
                [
                  lookups.sources[c['sourceId']] ??
                      l10n.syncConflictUnknownItem,
                  if (c['page'] case final String page when page.isNotEmpty)
                    l10n.danceSourcePage(page),
                  if (c['number'] case final String number
                      when number.isNotEmpty)
                    l10n.danceSourceNumber(number),
                ].join(', '),
          ].join('; ');
        case 'links':
          return [
            for (final link in value as List)
              if (link is Map) _linkText(l10n, link),
          ].join('; ');
        case 'eventDate':
          return DateFormat.yMMMd(
            Localizations.localeOf(context).toString(),
          ).format(syncConflictCalendarDate(value as String));
        case 'payMinorUnits':
          // The amount alone is ambiguous: show it with that version's own
          // currency, formatted by the currency's exponent.
          final currency = body?['payCurrency'];
          final code = currency is String && currency.isNotEmpty
              ? currency
              : null;
          final amount = formatPayMinorUnits(value as int, code ?? 'USD');
          return code == null ? amount : '$amount $code';
        case 'color':
          return syncConflictColourText(value as int);
        case 'keywords':
          // Another name for one of the user's own figures, each in canonical
          // role words (#709).
          return [
            for (final keyword in value as List)
              syncConflictFreeText(context, keyword as String),
          ].join(', ');
        case 'provenance':
          final map = value as Map;
          final license = map['license'];
          return [
            l10n.danceProvenanceVia(
              provenanceSourceLabel(
                l10n,
                ProvenanceSource.values.byName(map['source'] as String),
              ),
            ),
            if (license is String && license.isNotEmpty) license,
          ].join(' · ');
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

  /// A link in full: what kind it is, its label, where it goes, and whether
  /// it joins the related-dance group; everything the chosen version saves.
  String _linkText(AppLocalizations l10n, Map<Object?, Object?> link) {
    final kind = switch (link['kind']) {
      'video' => l10n.danceLinkKindVideo,
      'source' => l10n.danceLinkKindSource,
      _ => l10n.danceLinkKindLink,
    };
    final label = link['label'];
    final destination = switch (link['targetDanceId']) {
      final String id => lookups.dances[id] ?? l10n.syncConflictUnknownItem,
      _ => (link['url'] as String?) ?? l10n.syncConflictUnknownItem,
    };
    return [
      kind,
      if (label is String && label.trim().isNotEmpty) label,
      destination,
      if (link['transitive'] == true) l10n.syncConflictLinkInGroup,
    ].join(' · ');
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
