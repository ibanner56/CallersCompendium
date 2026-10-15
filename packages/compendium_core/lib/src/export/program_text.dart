import '../model/program.dart';
import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import 'export_labels.dart';

/// Renders a [Program] as a clean, human-readable plain-text set list — the
/// "emailable set list" of ROADMAP §4.3 (CC parity: "email set list").
///
/// This lives in `compendium_core` and is intentionally **pure Dart**: it takes
/// no Flutter/intl dependency so it can be unit-tested and reused by the app's
/// share/copy path. The PDF layout builds on the same [programHeaderLines] and
/// [programSlotLine] output, so the two cannot drift.
///
/// The set list is titles + metadata + slot notes only — **not** full per-dance
/// figure breakdowns. The app layer optionally appends per-dance figure cards
/// from `danceToPlainText` when the user opts in to "Set list and figures"
/// (issue #853, ask 2). Dance titles are not dialect terms; purge captions
/// remain lossless while free-text slots and notes may receive display-only
/// discouraged-term conversion.
///
/// - [titleFor] resolves a slot's [ProgramSlot.danceId] to a dance title;
///   return `null` for an unknown/unavailable dance and the renderer falls back
///   to [ProgramExportLabels.unknownDance] (`labels.unknownDance`).
/// - [venueNameFor] resolves a linked venue entity's id ([Program.venueId]) to
///   its already-formatted display label; return `null` when the id doesn't
///   resolve. This keeps the renderer pure Dart (it never imports the `Venue`
///   model): the app passes a closure backed by its loaded venue records. A
///   resolvable linked venue wins over the free-text [Program.venue]; when the
///   callback is `null` (or returns `null`), the free-text label is used —
///   preserving the pre-venue-entity behavior.
/// - [formatDate] formats [Program.eventDate]; defaults to an ISO `yyyy-MM-dd`
///   date. The app passes a locale-aware formatter
///   (`MaterialLocalizations.formatMediumDate`).
/// - [authorNamesFor] resolves a slot's `danceId` to its already-resolved
///   choreographer *names* (issue #1434) — same privacy contract as
///   `danceToPlainText`'s `authorNames`: never a `Choreographer` record, so
///   private contact fields have no path in. `null` (the default) omits the
///   author suffix entirely, preserving the pre-#1434 slot-line format for
///   every existing caller. When supplied, a slot whose resolver call returns
///   an empty list (or all-blank names) also omits the suffix — this is
///   independent of the figures-appendix opt-in, so it appears on every
///   numbered dance, whether or not that dance has any figures.
///
/// Layout:
/// ```
/// <TITLE>
/// <date> · <venue>
/// Band: <band>
/// Caller: <caller>
/// Level: <dancerLevel>
///
/// 1. <dance title | free text>[ — <author suffix>][ — <slot note>][ (guest: <x>; <n> min)][ [performed]]
///    ALT: <alt line, same format, no number>
/// 2. ...
///
/// Notes:
/// <program notes>
/// ```
/// Primaries are numbered `1..n`; alternates (via [Program.grouped]) are
/// indented under their primary with an `ALT:` prefix. A leading/orphaned alt
/// still renders (grouping keeps it as a degenerate primary). Absent metadata
/// parts are omitted. An empty program renders the header only.
String programToPlainText(
  Program program, {
  required String? Function(String danceId) titleFor,
  String? Function(String venueId)? venueNameFor,
  String Function(DateTime date)? formatDate,
  ProgramExportLabels labels = const ProgramExportLabels(),
  FigureRenderer? renderer,
  Dialect? dialect,
  bool canonicalizeDiscouragedTerms = false,
  List<String> Function(String danceId)? authorNamesFor,
}) {
  _requireCanonicalizationDeps(canonicalizeDiscouragedTerms, renderer, dialect);
  final lines = <String>[
    program.title.trim(),
    ...programHeaderLines(
      program,
      venueNameFor: venueNameFor,
      formatDate: formatDate,
      labels: labels,
      renderer: renderer,
      dialect: dialect,
      canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
    ),
  ];

  final groups = program.outputGrouped;
  if (groups.isNotEmpty) {
    lines.add('');
    var n = 1;
    for (final group in groups) {
      final primary = programSlotLine(
        group.primary,
        titleFor,
        labels,
        renderer: renderer,
        dialect: dialect,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
        authorNamesFor: authorNamesFor,
      );
      lines.add('$n. $primary');
      for (final alt in group.alternates) {
        final alternate = programSlotLine(
          alt,
          titleFor,
          labels,
          renderer: renderer,
          dialect: dialect,
          canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
          authorNamesFor: authorNamesFor,
        );
        lines.add('   ${labels.alt}: $alternate');
      }
      n++;
    }
  }

  if (_has(program.notes)) {
    lines.add('');
    lines.add('${labels.notes}:');
    lines.add(
      !canonicalizeDiscouragedTerms || renderer == null || dialect == null
          ? program.notes.trim()
          : renderer.renderFreeTextWithCanonicalDiscouragedTerms(
              program.notes.trim(),
              dialect,
            ),
    );
  }

  return lines.join('\n');
}

void _requireCanonicalizationDeps(
  bool canonicalizeDiscouragedTerms,
  FigureRenderer? renderer,
  Dialect? dialect,
) {
  if (canonicalizeDiscouragedTerms && (renderer == null || dialect == null)) {
    throw ArgumentError(
      'renderer and dialect are required when canonicalizeDiscouragedTerms '
      'is enabled',
    );
  }
}

/// The program header lines under the title: `date · venue`, band, caller and
/// level, each only when present (so an empty program yields an empty list).
/// Throws [ArgumentError] when [canonicalizeDiscouragedTerms] is set without
/// both [renderer] and [dialect], like [programToPlainText].
///
/// Shared by [programToPlainText] and the program PDF. [venueNameFor],
/// [formatDate], [labels] and the discouraged-term parameters have the same
/// contract as on [programToPlainText]; as there, the dancer level is only
/// converted when [canonicalizeDiscouragedTerms] is set and both [renderer]
/// and [dialect] are supplied.
List<String> programHeaderLines(
  Program program, {
  String? Function(String venueId)? venueNameFor,
  String Function(DateTime date)? formatDate,
  ProgramExportLabels labels = const ProgramExportLabels(),
  FigureRenderer? renderer,
  Dialect? dialect,
  bool canonicalizeDiscouragedTerms = false,
}) {
  _requireCanonicalizationDeps(canonicalizeDiscouragedTerms, renderer, dialect);
  final fmtDate = formatDate ?? isoDate;
  final lines = <String>[];

  // date · venue on one line (only the present parts). A resolvable linked
  // venue's display label wins over the free-text label; either falls back to
  // the other, and both to nothing (the venue part is then omitted).
  final linkedVenue = program.venueId != null
      ? venueNameFor?.call(program.venueId!)
      : null;
  final venueLabel = _has(linkedVenue)
      ? linkedVenue!.trim()
      : (_has(program.venue) ? program.venue!.trim() : null);
  final dateVenue = <String>[
    if (program.eventDate != null) fmtDate(program.eventDate!),
    ?venueLabel,
  ];
  if (dateVenue.isNotEmpty) lines.add(dateVenue.join(' · '));

  if (_has(program.band)) lines.add('${labels.band}: ${program.band!.trim()}');
  if (_has(program.caller)) {
    lines.add('${labels.caller}: ${program.caller!.trim()}');
  }
  if (_has(program.dancerLevel)) {
    final level =
        !canonicalizeDiscouragedTerms || renderer == null || dialect == null
        ? program.dancerLevel!.trim()
        : renderer.renderFreeTextWithCanonicalDiscouragedTerms(
            program.dancerLevel!.trim(),
            dialect,
          );
    lines.add('${labels.level}: $level');
  }
  return lines;
}

/// Builds the content of a single slot line (without the number or `ALT:`
/// prefix): the dance title or free text, an optional author suffix, an
/// optional per-slot note, an optional `(guest: …; N min)` suffix, and a
/// trailing `[performed]` marker. Throws [ArgumentError] when
/// [canonicalizeDiscouragedTerms] is set without both [renderer] and [dialect].
String programSlotLine(
  ProgramSlot slot,
  String? Function(String danceId) titleFor,
  ProgramExportLabels labels, {
  FigureRenderer? renderer,
  Dialect? dialect,
  bool canonicalizeDiscouragedTerms = false,
  List<String> Function(String danceId)? authorNamesFor,
}) {
  _requireCanonicalizationDeps(canonicalizeDiscouragedTerms, renderer, dialect);
  final buffer = StringBuffer();

  if (slot.danceId != null) {
    final title = titleFor(slot.danceId!);
    buffer.write(_has(title) ? title!.trim() : labels.unknownDance);
    // Author suffix (issue #1434): resolved independently of whether this
    // dance has any figures, so it appears on every numbered dance rather
    // than only the ones reachable via the figures-appendix opt-in.
    final authorNames = authorNamesFor
        ?.call(slot.danceId!)
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (authorNames != null && authorNames.isNotEmpty) {
      buffer.write(' — ${labels.by(authorNames.join(', '))}');
    }
    // On a dance slot, `text` is a per-slot caller note.
    if (_has(slot.text)) {
      final note =
          !canonicalizeDiscouragedTerms || renderer == null || dialect == null
          ? slot.text!.trim()
          : renderer.renderFreeTextWithCanonicalDiscouragedTerms(
              slot.text!.trim(),
              dialect,
            );
      buffer.write(' — $note');
    }
  } else {
    // Purge captions are lossless; ordinary text-only slots are display prose.
    final text = slot.text!.trim();
    buffer.write(
      slot.isPurgedDance != false ||
              !canonicalizeDiscouragedTerms ||
              renderer == null ||
              dialect == null
          ? text
          : renderer.renderFreeTextWithCanonicalDiscouragedTerms(text, dialect),
    );
  }

  final meta = <String>[
    if (_has(slot.guestCaller)) '${labels.guest}: ${slot.guestCaller!.trim()}',
    if (slot.plannedTotalMinutes != null)
      labels.minutes(slot.plannedTotalMinutes!),
  ];
  if (meta.isNotEmpty) buffer.write(' (${meta.join('; ')})');

  if (slot.performedAt != null) buffer.write(' [${labels.performed}]');

  return buffer.toString();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

/// Formats [date] as ISO `yyyy-MM-dd` — the default date format of the program
/// exports.
String isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
