/// Injectable, localizable field-name labels for the export renderers.
///
/// The plain-text renderers ([danceToPlainText], [programToPlainText]) and the
/// app-side PDF builders (`export/dance_pdf.dart`, `export/program_pdf.dart`,
/// `export/program_matrix_pdf.dart`) share the same document "furniture" — the
/// field-name labels ("Formation", "Level", …), unit words ("beats", "min"),
/// and fixed captions that frame the user's content. Per localization decision
/// #529 (exports follow the UI language), that furniture must be localizable.
///
/// These renderers live in (or below) the Flutter-free `compendium_core`
/// package (ADR-001), so they cannot call `AppLocalizations` directly. Instead
/// the **app** resolves an `AppLocalizations` into one of these plain-Dart value
/// objects (see `app/lib/src/export/export_labels_l10n.dart`) and passes it in —
/// the same "caller resolves the display strings" contract the renderers
/// already use for facet values (formation/level/status).
///
/// Each field defaults to its **English source string**, so a pure-Dart caller
/// (and the package's own unit tests) can use the renderers without wiring up a
/// localization layer, while the app always injects the user's locale. The
/// English defaults are the single source of truth mirrored into `app_en.arb`.
library;

import '../model/bar_count.dart';

String _englishBeats(int beats) => '$beats ${beats == 1 ? 'beat' : 'beats'}';

String _englishNamedPhrases(String order, String bars) => '$order ($bars)';

String _englishBars(String bars, int halfBars) =>
    '$bars ${halfBars == 1 || halfBars == 2 ? 'bar' : 'bars'}';

String _englishMinutes(int minutes) => '$minutes min';

String _englishBy(String names) => 'by $names';

String _englishPageOf(int page, int pages) => 'Page $page of $pages';

String _englishTimeRange(String start, String end) => '$start–$end';

String _englishEndsAt(String end) => 'until $end';

String _englishNextDay(String times) => '$times (next day)';

String _englishOmittedCaption(int count) =>
    '$count free-text ${count == 1 ? 'slot' : 'slots'} '
    '(breaks, notes) omitted — the matrix shows dances only.';

/// Field-name labels for the single-dance card export ([danceToPlainText] and
/// the dance PDF). [beats] renders a beat count with its (locale-aware,
/// pluralized) unit, e.g. `"16 beats"` / `"1 beat"`; [bars] renders a count of
/// bars, for a dance timed in bars ([count]).
class DanceExportLabels {
  const DanceExportLabels({
    this.formation = 'Formation',
    this.level = 'Level',
    this.mixer = 'Mixer',
    this.status = 'Status',
    this.phrase = 'Phrase',
    this.figures = 'Figures',
    this.callingNotes = 'Calling notes',
    this.walkthrough = 'Walkthrough',
    this.tunes = 'Tunes',
    this.hook = 'Hook',
    this.sources = 'Sources',
    this.beats = _englishBeats,
    this.bars = _englishBars,
    this.namedPhrases = _englishNamedPhrases,
    this.namedPhraseSeparator = ', ',
    this.labelSeparator = ': ',
    this.pageOf = _englishPageOf,
  });

  final String formation;
  final String level;

  /// Label for the mixer flag line on the exported dance card.
  final String mixer;
  final String status;
  final String phrase;
  final String figures;
  final String callingNotes;
  final String walkthrough;

  /// Header label for the suggested-tune-list section (issue #1434). Rendered
  /// only when `DanceShareField.tunes` is selected — no renderer emitted this
  /// section before that field existed.
  final String tunes;

  /// Label for the hook line (OUT-6). Rendered only when
  /// `DanceShareField.hook` is selected.
  final String hook;

  /// Header label for the published-sources section (OUT-6). Rendered only when
  /// `DanceShareField.sources` is selected.
  final String sources;
  final String Function(int beats) beats;

  /// A count of bars with its unit, e.g. `"4 bars"` / `"1½ bars"`: [bars] is
  /// the count as written ([barsText]) and `halfBars` the same count in half
  /// bars, which picks the plural (1 is half a bar, 2 is one bar).
  final String Function(String bars, int halfBars) bars;

  /// Named phrases as a card prints them: [order] is the phrases in playing
  /// order, such as `AAB`, and `bars` each phrase's bars, joined by
  /// [namedPhraseSeparator], such as `A 4 bars, B 8 bars`. English writes
  /// `AAB (A 4 bars, B 8 bars)`; Japanese uses full-width parentheses.
  final String Function(String order, String bars) namedPhrases;

  /// Between two phrases' bars in [namedPhrases]: `", "` in English, `"、"`
  /// in Japanese.
  final String namedPhraseSeparator;

  /// Between a field's label and its value, such as `Phrase: AAB`: `": "` in
  /// English, the full-width `"："` in Japanese.
  final String labelSeparator;

  /// [label] followed by [labelSeparator], to put before a field's value.
  String labelled(String label) => '$label$labelSeparator';

  /// [label] as a section heading with the field's value on the lines below,
  /// such as `Figures:`: [labelSeparator] without a trailing space.
  String heading(String label) => '$label${labelSeparator.trimRight()}';

  /// A figure's count of [beats] as an export shows it: in bars of
  /// [beatsPerBar] beats for a dance timed in bars ([danceBeatsPerBar]), or in
  /// beats where [beatsPerBar] is null or the count is not a whole number of
  /// half bars, as the editor shows it.
  String count(int beats, int? beatsPerBar) {
    final text = beatsPerBar == null ? null : barsText(beats, beatsPerBar);
    return text == null
        ? this.beats(beats)
        : bars(text, beats * 2 ~/ beatsPerBar!);
  }

  /// Page footer of the dance PDF, e.g. `"Page 2 of 3"`.
  final String Function(int page, int pages) pageOf;
}

/// Field-name labels for the set-list export ([programToPlainText] and the
/// program PDF). The venue-block fields ([venue]/[time]/[schedule]/[price]/
/// [sponsor]) are used only by the PDF's richer venue block; the plain-text
/// renderer ignores them. [minutes] renders a planned-minutes value with its
/// unit, e.g. `"5 min"`.
class ProgramExportLabels {
  const ProgramExportLabels({
    this.band = 'Band',
    this.caller = 'Caller',
    this.level = 'Level',
    this.notes = 'Notes',
    this.alt = 'ALT',
    this.guest = 'guest',
    this.unknownDance = 'Untitled dance',
    this.minutes = _englishMinutes,
    this.venue = 'Venue',
    this.time = 'Time',
    this.schedule = 'Schedule',
    this.price = 'Price',
    this.sponsor = 'Sponsor',
    this.figures = 'Figures',
    this.alternate = 'Alternate',
    this.by = _englishBy,
    this.labelSeparator = ': ',
    this.pageOf = _englishPageOf,
    this.lesson = 'Lesson',
    this.timeRange = _englishTimeRange,
    this.endsAt = _englishEndsAt,
    this.nextDay = _englishNextDay,
  });

  final String band;
  final String caller;
  final String level;
  final String notes;
  final String alt;
  final String guest;
  final String unknownDance;
  final String Function(int minutes) minutes;
  final String venue;
  final String time;
  final String schedule;
  final String price;
  final String sponsor;

  /// Header label for the figures appendix section in a set-list-and-figures
  /// export (issue #853).
  final String figures;

  /// Prefix for a dance card in the figures appendix when the dance is an
  /// alternate slot rather than a primary (issue #853).
  final String alternate;

  /// Formats a slot line's author-names suffix, e.g. `"by Jane Smith"`
  /// (issue #1434). Rendered after the dance title/free text, before the
  /// guest/minutes suffixes, only when the caller resolves at
  /// least one non-blank author name for that slot's dance.
  final String Function(String names) by;

  /// Between a field's label and its value, such as `Band: Reel Time`: `": "`
  /// in English, the full-width `"："` in Japanese.
  final String labelSeparator;

  /// [label] followed by [labelSeparator], to put before a field's value.
  String labelled(String label) => '$label$labelSeparator';

  /// [label] as a section heading with the field's value on the lines below,
  /// such as `Figures:`: [labelSeparator] without a trailing space.
  String heading(String label) => '$label${labelSeparator.trimRight()}';

  /// Page footer of the set-list PDF, e.g. `"Page 2 of 3"`.
  final String Function(int page, int pages) pageOf;

  /// Label of the beginner lesson's time, as in `Lesson: 7:00 PM` (#2350).
  final String lesson;

  /// A dance's start and end time as one phrase, e.g. `"7:30 PM–10:30 PM"`;
  /// both arguments are already formatted.
  final String Function(String start, String end) timeRange;

  /// A dance's end time when no start is recorded, e.g. `"until 10:30 PM"`.
  final String Function(String end) endsAt;

  /// [timeRange]'s result marked as ending the next day, e.g.
  /// `"7:30 PM–1:00 AM (next day)"`.
  final String Function(String times) nextDay;
}

/// Labels and fixed captions for the Programming Matrix PDF
/// (`export/program_matrix_pdf.dart`). [omittedCaption] renders the
/// "N free-text slots omitted" caption with its (locale-aware, pluralized)
/// count.
///
/// Two collision legend captions are needed (issue #962): the printed legend
/// must always match [ProgramMatrix.collisionMode], since the on-screen matrix
/// and its PDF export share the same underlying [ProgramMatrix] and must never
/// disagree about what the alert marker means.
class ProgramMatrixExportLabels {
  const ProgramMatrixExportLabels({
    this.defaultTitle = 'Programming matrix',
    this.danceColumn = 'Dance',
    this.formationColumn = 'Formation',
    this.emptyState =
        'No structured figures yet — the matrix fills in automatically as '
        'the program’s dances gain structured figures.',
    this.legendDebut = 'Introduced here',
    this.legendFirst = "Dance's first figure",
    this.legendPresent = 'Present',
    this.legendCollisionBeats = 'Shares beats with an adjacent dance',
    this.legendCollisionPhrase = 'Same phrase as adjacent dance',
    this.omittedCaption = _englishOmittedCaption,
    this.pageOf = _englishPageOf,
  });

  final String defaultTitle;
  final String danceColumn;
  final String formationColumn;
  final String emptyState;
  final String legendDebut;
  final String legendFirst;
  final String legendPresent;

  /// Legend caption for [MatrixCollisionMode.exactBeats] (issue #962, the
  /// default).
  final String legendCollisionBeats;

  /// Legend caption for [MatrixCollisionMode.phrase] (issue #582's original
  /// behaviour, now opt-in).
  final String legendCollisionPhrase;
  final String Function(int count) omittedCaption;

  /// Page footer of the matrix PDF, e.g. `"Page 2 of 3"`.
  final String Function(int page, int pages) pageOf;
}
