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

String _englishBeats(int beats) => '$beats ${beats == 1 ? 'beat' : 'beats'}';

String _englishMinutes(int minutes) => '$minutes min';

String _englishOmittedCaption(int count) =>
    '$count free-text ${count == 1 ? 'slot' : 'slots'} '
    '(breaks, notes) omitted — the matrix shows dances only.';

/// Field-name labels for the single-dance card export ([danceToPlainText] and
/// the dance PDF). [beats] renders a beat count with its (locale-aware,
/// pluralized) unit, e.g. `"16 beats"` / `"1 beat"`.
class DanceExportLabels {
  const DanceExportLabels({
    this.formation = 'Formation',
    this.level = 'Level',
    this.status = 'Status',
    this.phrase = 'Phrase',
    this.figures = 'Figures',
    this.callingNotes = 'Calling notes',
    this.walkthrough = 'Walkthrough',
    this.beats = _englishBeats,
  });

  final String formation;
  final String level;
  final String status;
  final String phrase;
  final String figures;
  final String callingNotes;
  final String walkthrough;
  final String Function(int beats) beats;
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
    this.performed = 'performed',
    this.unknownDance = 'Untitled dance',
    this.minutes = _englishMinutes,
    this.venue = 'Venue',
    this.time = 'Time',
    this.schedule = 'Schedule',
    this.price = 'Price',
    this.sponsor = 'Sponsor',
  });

  final String band;
  final String caller;
  final String level;
  final String notes;
  final String alt;
  final String guest;
  final String performed;
  final String unknownDance;
  final String Function(int minutes) minutes;
  final String venue;
  final String time;
  final String schedule;
  final String price;
  final String sponsor;
}

/// Labels and fixed captions for the Programming Matrix PDF
/// (`export/program_matrix_pdf.dart`). [omittedCaption] renders the
/// "N free-text slots omitted" caption with its (locale-aware, pluralized)
/// count.
class ProgramMatrixExportLabels {
  const ProgramMatrixExportLabels({
    this.defaultTitle = 'Programming matrix',
    this.danceColumn = 'Dance',
    this.emptyState =
        'No structured figures yet — the matrix fills in automatically as '
        'the program’s dances gain structured figures.',
    this.legendDebut = 'Introduced here',
    this.legendFirst = "Dance's first figure",
    this.legendPresent = 'Present',
    this.legendCollision = 'Same phrase as adjacent dance',
    this.omittedCaption = _englishOmittedCaption,
  });

  final String defaultTitle;
  final String danceColumn;
  final String emptyState;
  final String legendDebut;
  final String legendFirst;
  final String legendPresent;
  final String legendCollision;
  final String Function(int count) omittedCaption;
}
