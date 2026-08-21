import '../model/program.dart';
import 'export_labels.dart';

/// Renders a [Program] as a clean, human-readable plain-text set list — the
/// "emailable set list" of ROADMAP §4.3 (CC parity: "email set list").
///
/// This lives in `compendium_core` and is intentionally **pure Dart**: it takes
/// no Flutter/intl dependency so it can be unit-tested and reused by the app's
/// share/copy path and by the PDF layout (which reuses the same field ordering).
///
/// The set list is titles + metadata + slot notes only — **not** full per-dance
/// figure breakdowns. The app layer optionally appends per-dance figure cards
/// from `danceToPlainText` when the user opts in to "Set list and figures"
/// (issue #853, ask 2). Dance titles are not dialect
/// terms, so no canonicalize is applied here.
///
/// - [titleFor] resolves a slot's [ProgramSlot.danceId] to a dance title;
///   return `null` for an unknown/unavailable dance and the renderer falls back
///   to [unknownDanceLabel].
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
///
/// Layout:
/// ```
/// <TITLE>
/// <date> · <venue>
/// Band: <band>
/// Caller: <caller>
/// Level: <dancerLevel>
///
/// 1. <dance title | free text>[ — <slot note>][ (guest: <x>; <n> min)][ [performed]]
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
}) {
  final fmtDate = formatDate ?? _isoDate;
  final lines = <String>[];

  lines.add(program.title.trim());

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
    lines.add('${labels.level}: ${program.dancerLevel!.trim()}');
  }

  final groups = program.outputGrouped;
  if (groups.isNotEmpty) {
    lines.add('');
    var n = 1;
    for (final group in groups) {
      lines.add('$n. ${_slotLine(group.primary, titleFor, labels)}');
      for (final alt in group.alternates) {
        lines.add('   ${labels.alt}: ${_slotLine(alt, titleFor, labels)}');
      }
      n++;
    }
  }

  if (_has(program.notes)) {
    lines.add('');
    lines.add('${labels.notes}:');
    lines.add(program.notes.trim());
  }

  return lines.join('\n');
}

/// Builds the content of a single slot line (without the number or `ALT:`
/// prefix): the dance title or free text, an optional per-slot note, an optional
/// `(guest: …; N min)` suffix, and a trailing `[performed]` marker.
String _slotLine(
  ProgramSlot slot,
  String? Function(String danceId) titleFor,
  ProgramExportLabels labels,
) {
  final buffer = StringBuffer();

  if (slot.danceId != null) {
    final title = titleFor(slot.danceId!);
    buffer.write(_has(title) ? title!.trim() : labels.unknownDance);
    // On a dance slot, `text` is a per-slot caller note.
    if (_has(slot.text)) buffer.write(' — ${slot.text!.trim()}');
  } else {
    // Text-only slot (break, waltz, announcement): text is the whole content.
    buffer.write(slot.text!.trim());
  }

  final meta = <String>[
    if (_has(slot.guestCaller)) '${labels.guest}: ${slot.guestCaller!.trim()}',
    if (slot.plannedMinutes != null) labels.minutes(slot.plannedMinutes!),
  ];
  if (meta.isNotEmpty) buffer.write(' (${meta.join('; ')})');

  if (slot.performedAt != null) buffer.write(' [${labels.performed}]');

  return buffer.toString();
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;

String _isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
