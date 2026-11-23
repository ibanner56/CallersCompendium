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
///   date. The app passes `formatEventDate` under the
///   user's Date format setting (System follows the device region's numeric
///   date).
/// - [formatTime] formats a time of day, given as minutes after midnight
///   ([Program.startMinute] and the others); defaults to a 24-hour `HH:mm`
///   ([isoTimeOfDay]). The app passes the active locale's 12- or 24-hour form.
///   The caller's [Program.arrivalMinute] is never written: the set list is
///   made for other people (#2350).
/// - [authorNamesFor] resolves a slot's `danceId` to its already-resolved
///   choreographer *names* (issue #1434) — same privacy contract as
///   `danceToPlainText`'s `authorNames`: never a `Choreographer` record, so
///   private contact fields have no path in. `null` (the default) omits the
///   author suffix entirely, preserving the pre-#1434 slot-line format for
///   every existing caller. When supplied, a slot whose resolver call returns
///   an empty list (or all-blank names) also omits the suffix — this is
///   independent of the figures-appendix opt-in, so it appears on every
///   numbered dance, whether or not that dance has any figures.
/// - [formLabelFor] resolves a slot's `danceId` to the display name of its
///   dance form ("English"), already localized, or `null` to name none. The
///   app names the form only when the program mixes forms (ADR-006 S5), as
///   its program screens do; `null` (the default) never names it. The name
///   leads the slot's parenthesised details.
/// - [tuneDetailsFor] resolves a slot's `danceId` to its tune's meter and key
///   as one already-labelled, already-rendered line, such as
///   `Meter: 6/8 · Key: G minor`, or `null` for none. It follows the form in
///   the parenthesised details; `null` (the default) prints none.
///
/// Layout:
/// ```
/// <TITLE>
/// <date> · <start>–<end> · <venue>
/// Lesson: <lesson>
/// Band: <band>
/// Caller: <caller>
/// Level: <dancerLevel>
///
/// 1. <dance title | free text>[ — <author suffix>][ — <slot note>][ (<form>; <meter and key>; guest: <x>; <n> min)]
///    ALT: <alt line, same format, no number>
/// 2. ...
///
/// Notes:
/// <program notes>
/// ```
/// Planned dances ([ProgramSlot.isPlannedDance]) are numbered `1..n`, so the
/// last number is [Program.plannedDanceCount]; the break is printed without a
/// number. Alternates (via [Program.grouped]) are indented under their primary
/// with an `ALT:` prefix. A leading/orphaned alt still renders, unnumbered with
/// an `ALT:` prefix (grouping keeps it as a degenerate primary). Absent metadata
/// parts are omitted. An empty program renders the header only.
String programToPlainText(
  Program program, {
  required String? Function(String danceId) titleFor,
  String? Function(String venueId)? venueNameFor,
  String Function(DateTime date)? formatDate,
  String Function(int minuteOfDay)? formatTime,
  ProgramExportLabels labels = const ProgramExportLabels(),
  FigureRenderer? renderer,
  Dialect? dialect,
  bool canonicalizeDiscouragedTerms = false,
  List<String> Function(String danceId)? authorNamesFor,
  String? Function(String danceId)? formLabelFor,
  String? Function(String danceId)? tuneDetailsFor,
  bool includeTitle = true,
  bool includeCallerBand = true,
  bool includeDateVenue = true,
}) {
  _requireCanonicalizationDeps(canonicalizeDiscouragedTerms, renderer, dialect);
  final lines = <String>[
    if (includeTitle) program.title.trim(),
    ...programHeaderLines(
      program,
      venueNameFor: venueNameFor,
      formatDate: formatDate,
      formatTime: formatTime,
      labels: labels,
      renderer: renderer,
      dialect: dialect,
      canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      includeCallerBand: includeCallerBand,
      includeDateVenue: includeDateVenue,
    ),
  ];

  final groups = program.outputGrouped;
  if (groups.isNotEmpty) {
    // The blank line separates the slots from a header; with every header
    // line switched off there is none to separate from.
    if (lines.isNotEmpty) lines.add('');
    var n = 0;
    for (final group in groups) {
      final primary = programSlotLine(
        group.primary,
        titleFor,
        labels,
        renderer: renderer,
        dialect: dialect,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
        authorNamesFor: authorNamesFor,
        formLabelFor: formLabelFor,
        tuneDetailsFor: tuneDetailsFor,
      );
      lines.add(setListPrimaryLine(group.primary, primary, labels, () => ++n));
      for (final alt in group.alternates) {
        final alternate = programSlotLine(
          alt,
          titleFor,
          labels,
          renderer: renderer,
          dialect: dialect,
          canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
          authorNamesFor: authorNamesFor,
          formLabelFor: formLabelFor,
          tuneDetailsFor: tuneDetailsFor,
        );
        lines.add('   ${labels.labelled(labels.alt)}$alternate');
      }
    }
  }

  if (_has(program.notes)) {
    if (lines.isNotEmpty) lines.add('');
    lines.add(labels.heading(labels.notes));
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

/// The set-list line for a group's [primary] slot, whose rendered content is
/// [line]: numbered with [nextNumber] when it is a planned dance
/// ([ProgramSlot.isPlannedDance]), so the numbers count dances only (GIG-10).
/// The break is printed unnumbered, and a leading alternate with no primary
/// before it keeps its `ALT:` prefix rather than taking a dance number.
///
/// Shared by [programToPlainText] and the program PDF; [nextNumber] is called
/// only for a numbered line.
String setListPrimaryLine(
  ProgramSlot primary,
  String line,
  ProgramExportLabels labels,
  int Function() nextNumber,
) {
  if (primary.isPlannedDance) return '${nextNumber()}. $line';
  if (primary.isAlt) return '${labels.labelled(labels.alt)}$line';
  return line;
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

/// The program header lines under the title: `date · times · venue`, the
/// lesson time, band, caller and level, each only when present (so an empty
/// program yields an empty list). The times are the dance's start and end
/// ([programDanceTimes]); the caller's [Program.arrivalMinute] is never
/// included, because the set-list text and PDF are made for other people
/// (#2350).
/// Throws [ArgumentError] when [canonicalizeDiscouragedTerms] is set without
/// both [renderer] and [dialect], like [programToPlainText].
///
/// Shared by [programToPlainText] and the program PDF. [venueNameFor],
/// [formatDate], [labels] and the discouraged-term parameters have the same
/// contract as on [programToPlainText]; as there, the dancer level is only
/// converted when [canonicalizeDiscouragedTerms] is set and both [renderer]
/// and [dialect] are supplied. [includeDateVenue] and [includeCallerBand]
/// (default `true`) omit the `date · times · venue` and lesson lines, and the
/// band and caller lines. [formatTime] is as on [programToPlainText].
List<String> programHeaderLines(
  Program program, {
  String? Function(String venueId)? venueNameFor,
  String Function(DateTime date)? formatDate,
  String Function(int minuteOfDay)? formatTime,
  ProgramExportLabels labels = const ProgramExportLabels(),
  FigureRenderer? renderer,
  Dialect? dialect,
  bool canonicalizeDiscouragedTerms = false,
  bool includeCallerBand = true,
  bool includeDateVenue = true,
}) {
  _requireCanonicalizationDeps(canonicalizeDiscouragedTerms, renderer, dialect);
  final fmtDate = formatDate ?? isoDate;
  final fmtTime = formatTime ?? isoTimeOfDay;
  final lines = <String>[];

  // date · times · venue on one line (only the present parts). A resolvable linked
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
    ?programDanceTimes(program, formatTime: fmtTime, labels: labels),
    ?venueLabel,
  ];
  if (includeDateVenue && dateVenue.isNotEmpty) {
    lines.add(dateVenue.join(' · '));
  }
  // The lesson is part of when the event happens, so the same switch hides
  // it. Arrive by is deliberately absent: it is the caller's own logistics.
  final lesson = program.lessonMinute;
  if (includeDateVenue && lesson != null) {
    lines.add('${labels.labelled(labels.lesson)}${fmtTime(lesson)}');
  }

  if (includeCallerBand && _has(program.band)) {
    lines.add('${labels.labelled(labels.band)}${program.band!.trim()}');
  }
  if (includeCallerBand && _has(program.caller)) {
    lines.add('${labels.labelled(labels.caller)}${program.caller!.trim()}');
  }
  if (_has(program.dancerLevel)) {
    final level =
        !canonicalizeDiscouragedTerms || renderer == null || dialect == null
        ? program.dancerLevel!.trim()
        : renderer.renderFreeTextWithCanonicalDiscouragedTerms(
            program.dancerLevel!.trim(),
            dialect,
          );
    lines.add('${labels.labelled(labels.level)}$level');
  }
  return lines;
}

/// Builds the content of a single slot line (without the number or `ALT:`
/// prefix): the dance title or free text, an optional author suffix, an
/// optional per-slot note, an optional `(<form>; <meter and key>; guest: …;
/// N min)` suffix, each part only when present ([formLabelFor] and
/// [tuneDetailsFor] as on [programToPlainText]).
/// The
/// slot's performed status is never rendered. Throws [ArgumentError] when
/// [canonicalizeDiscouragedTerms] is set without both [renderer] and [dialect].
String programSlotLine(
  ProgramSlot slot,
  String? Function(String danceId) titleFor,
  ProgramExportLabels labels, {
  FigureRenderer? renderer,
  Dialect? dialect,
  bool canonicalizeDiscouragedTerms = false,
  List<String> Function(String danceId)? authorNamesFor,
  String? Function(String danceId)? formLabelFor,
  String? Function(String danceId)? tuneDetailsFor,
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

  final formLabel = slot.danceId == null
      ? null
      : formLabelFor?.call(slot.danceId!);
  final tuneDetails = slot.danceId == null
      ? null
      : tuneDetailsFor?.call(slot.danceId!);
  final meta = <String>[
    if (_has(formLabel)) formLabel!.trim(),
    if (_has(tuneDetails)) tuneDetails!.trim(),
    if (_has(slot.guestCaller))
      '${labels.labelled(labels.guest)}${slot.guestCaller!.trim()}',
    if (slot.plannedTotalMinutes != null)
      labels.minutes(slot.plannedTotalMinutes!),
  ];
  if (meta.isNotEmpty) buffer.write(' (${meta.join('; ')})');

  return buffer.toString();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

/// The dance's own times as one phrase, or `null` when neither
/// [Program.startMinute] nor [Program.endMinute] is set: `start–end` (with
/// [ProgramExportLabels.nextDay] when [Program.endsNextDay]), the start
/// alone, or [ProgramExportLabels.endsAt] the end alone. [formatTime] formats
/// minutes after midnight. Shared by the set-list text, the PDF and the
/// app's program summary, so they say the same thing.
String? programDanceTimes(
  Program program, {
  required String Function(int minuteOfDay) formatTime,
  ProgramExportLabels labels = const ProgramExportLabels(),
}) => danceTimesText(
  startMinute: program.startMinute,
  endMinute: program.endMinute,
  formatTime: formatTime,
  labels: labels,
);

/// [programDanceTimes] for a start and end that are not on a [Program] yet,
/// such as the program editor's unsaved edits. An end earlier than the start
/// is the next day, as [Program.endsNextDay] has it.
String? danceTimesText({
  required int? startMinute,
  required int? endMinute,
  required String Function(int minuteOfDay) formatTime,
  ProgramExportLabels labels = const ProgramExportLabels(),
}) {
  final start = startMinute;
  final end = endMinute;
  if (start != null && end != null) {
    final range = labels.timeRange(formatTime(start), formatTime(end));
    return end < start ? labels.nextDay(range) : range;
  }
  if (start != null) return formatTime(start);
  if (end != null) return labels.endsAt(formatTime(end));
  return null;
}

/// Formats [minuteOfDay] (minutes after midnight) as a 24-hour `HH:mm` time —
/// the default time format of the program exports.
String isoTimeOfDay(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
  final m = (minuteOfDay % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Formats [date] as ISO `yyyy-MM-dd` — the default date format of the program
/// exports.
String isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
