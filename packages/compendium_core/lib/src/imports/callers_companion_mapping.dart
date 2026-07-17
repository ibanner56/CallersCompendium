import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/partial_date.dart';
import '../util/uuid.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';
import 'structured_draft.dart';

/// The reusable Caller's Companion (CC) → Compendium mapping layer.
///
/// This file is deliberately **source-agnostic**: it knows nothing about *how*
/// a CC dance was obtained. [CallersCompanionTextAdapter] builds a
/// [CcDanceRecord] by parsing CC's "copy formatted dance" clipboard/text
/// export; a future FileMaker-12 `.USR` binary reader (the headline Phase 6.5
/// deliverable, a separate PR) will build the *same* [CcDanceRecord] from the
/// `Dance` table's columns and reuse [mapCallersCompanionDance] verbatim. Keep
/// this unit free of text-parsing (or binary-parsing) specifics so both callers
/// can share it.
///
/// The mapping mirrors the CC schema surveyed in
/// `docs/research/callers-companion.md` (§"Schema-level addendum": `Dance`
/// fields `Name`, `Author*`, `Type`, `Formation`, `Level`, `Progression`,
/// `Music`, `DateComposed`/`DateRevised`, and the free-text body sections
/// `A1`/`A2`/`B1`/`B2`/`C1`/`C2`), and follows the import design in
/// `docs/design/imports.md` §2 (Caller's Companion migration): **figures are
/// the user's personal free text → import as `custom` figures**. Opportunistic
/// structuring through a grammar parser is deferred — no such parser exists in
/// core yet (that lands with the CallersBox TCB grammar, roadmap 6.2), so this
/// mapping keeps every figure custom and never invents structure.

/// One free-text body section of a CC dance (e.g. `A1`, `B2`).
///
/// [label] is the section name when known (`A1`/`A2`/`B1`/`B2`/`C1`/`C2`), or
/// `null` for lines that appeared before/without any section header. [lines]
/// are the raw body lines exactly as authored (typically `(16) Partner balance
/// and swing`, but any free text is accepted — the mapping never requires a
/// beats prefix).
@immutable
class CcBodySection {
  CcBodySection({this.label, List<String> lines = const []})
    : lines = List.unmodifiable(lines);

  /// Section label (`A1`/`A2`/`B1`/`B2`/`C1`/`C2`), or `null` when ungrouped.
  final String? label;

  /// Raw body lines, in order, verbatim.
  final List<String> lines;
}

/// A source-agnostic parsed Caller's Companion dance: the substantive user data
/// from one CC `Dance` record, independent of whether it came from the
/// clipboard text export or the binary `.USR`.
///
/// All scalar fields are the raw source strings (or `null`/absent) — the
/// mapping owns interpreting them into the typed model. [body] preserves the
/// free-text transcription grouped by section.
@immutable
class CcDanceRecord {
  CcDanceRecord({
    this.name,
    List<String> authors = const [],
    this.type,
    this.formation,
    this.level,
    this.progression,
    this.music,
    this.notes,
    this.composed,
    this.revised,
    this.rating,
    List<CcUserField> userFields = const [],
    List<CcBodySection> body = const [],
  }) : authors = List.unmodifiable(authors),
       userFields = List.unmodifiable(userFields),
       body = List.unmodifiable(body);

  /// CC `Name` — the dance title. `null`/blank means "no title supplied".
  final String? name;

  /// CC `Author1`/`Author2` display names, in order. Names only — CC exports no
  /// stable author id, and this mapping never creates Choreographer records
  /// (see [mapCallersCompanionDance]).
  final List<String> authors;

  /// CC `Type` (e.g. "Contra", "Square").
  final String? type;

  /// CC `Formation`/`ContraForm` (e.g. "Improper", "Becket", "Proper").
  final String? formation;

  /// CC `Level` (e.g. "Beginner", "Intermediate", "Advanced", "Mixed").
  final String? level;

  /// CC `Progression` (e.g. "Single", "Double").
  final String? progression;

  /// CC `Music` — free-text tune/music note.
  final String? music;

  /// Any additional free-text notes (e.g. CC `Credits`), if the source has
  /// them. Folded into the dance's calling notes.
  final String? notes;

  /// CC `DateComposed`, as a raw string (`YYYY`, `YYYY-MM`, or `YYYY-MM-DD`).
  final String? composed;

  /// CC `DateRevised`, as a raw string (same shapes as [composed]).
  final String? revised;

  /// CC `Rating`, as a raw source string (typically `"1".."5"`, sometimes a
  /// star glyph run or blank). Interpreted best-effort onto the model's closed
  /// `1..5` scale by [mapCallersCompanionDance]; out-of-range values are
  /// dropped with a warning rather than clamped.
  final String? rating;

  /// CC `UserDefined_1..3` user-defined fields, each a (label, value) pair.
  /// CC lets a caller define up to three custom columns (with `*_Name`
  /// labels). The model's typed `customFields` need a custom-field *definition*
  /// the import pipeline cannot create yet, so these are folded into the
  /// dance's calling notes as labelled lines by [mapCallersCompanionDance].
  final List<CcUserField> userFields;

  /// The free-text transcription body, grouped by CC section.
  final List<CcBodySection> body;
}

/// A Caller's Companion user-defined field: the caller's own label (from CC's
/// `UserDefined_N_Name`, or a synthesised fallback) and the value stored in
/// `UserDefined_N`.
@immutable
class CcUserField {
  const CcUserField({required this.label, required this.value});
  final String label;
  final String value;
}

/// The result of [mapCallersCompanionDance]: a [Dance] draft plus the non-fatal
/// [ImportIssue]s raised while mapping (unresolved author, unmapped level,
/// etc.). The dance carries no provenance — the [ImportPipeline] attaches that
/// at commit — and its id/timestamps are placeholders the pipeline reassigns.
@immutable
class CcDanceMapping {
  CcDanceMapping({
    required this.dance,
    List<ImportIssue> issues = const [],
    List<String> authorNames = const [],
  }) : issues = List.unmodifiable(issues),
       authorNames = List.unmodifiable(authorNames);

  final Dance dance;
  final List<ImportIssue> issues;

  /// CC author display names (trimmed, blanks dropped), in order. The
  /// [ImportPipeline] resolves these to [Choreographer] associations at commit;
  /// this mapping never fabricates ids.
  final List<String> authorNames;
}

/// Placeholder title used when a CC record supplies no name. Parsing never
/// fails on a missing title (`docs/design/imports.md`, parse-never-fails); a
/// [ImportIssue] is raised instead so the review queue can prompt for a real
/// one.
const String ccUntitledDanceTitle = "Untitled Caller's Companion dance";

/// Maps a source-agnostic [CcDanceRecord] into a [Dance] draft and the issues
/// raised while doing so. **Never throws on content** — a missing title, an
/// unmapped level/formation, or an unparseable date all surface as
/// [ImportIssue]s, and every body line becomes a structured or [customMove]
/// figure via [parseFigureLine] (the parse-never-fails invariant). This is the
/// single unit both the text adapter and the `.USR` reader call.
///
/// The draft's identity is disposable: [newId] (default [uuidV4]) and
/// [timestamp] (default the Unix epoch) exist only so a valid [Dance] can be
/// constructed — the pipeline reassigns id/`createdAt`/`updatedAt` at commit.
CcDanceMapping mapCallersCompanionDance(
  CcDanceRecord record, {
  String Function()? newId,
  DateTime? timestamp,
  String Function(String)? scrub,
}) {
  final issues = <ImportIssue>[];
  final now = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final scrubFn = scrub ?? scrubFigureText;

  // Title — placeholder + warning when absent (never throw).
  final rawName = record.name?.trim() ?? '';
  final String title;
  if (rawName.isEmpty) {
    title = ccUntitledDanceTitle;
    issues.add(
      const ImportIssue(
        severity: ImportIssueSeverity.warning,
        code: 'cc_missing_title',
        message:
            'The pasted dance had no title; imported as '
            '"$ccUntitledDanceTitle". Edit it before committing.',
      ),
    );
  } else {
    title = rawName;
  }

  // Authors — collected as display names for the pipeline to resolve to
  // Choreographer associations (match-or-create) at commit. This mapping never
  // fabricates ids; blank names are dropped.
  final authorNames = [
    for (final author in record.authors)
      if (author.trim().isNotEmpty) author.trim(),
  ];

  // Level → DanceLevel (+ mixedLevel), best-effort.
  final (level, mixedLevel) = _mapLevel(record.level, issues);

  // Type → DanceForm, best-effort; unknown types are preserved as a note.
  final (form, typeNote) = _mapForm(record.type, issues);

  // Formation → FormationShape, preserving unmapped text as detail.
  final formation = _mapFormation(record.formation, issues);

  // Progression → Progression enum, best-effort.
  final progression = _mapProgression(record.progression, issues);

  // Dates → PartialDate, warning (and skipping) unparseable values.
  final composedOn = _mapDate(record.composed, 'composed', issues);
  final revisedOn = _mapDate(record.revised, 'revised', issues);

  // Rating → 1..5 star scale, best-effort; out-of-range → warning + unset.
  final rating = _mapRating(record.rating, issues);

  // Notes: Music + an unmapped-type note + any extra source notes + the CC
  // user-defined fields (folded here because true customFields need a
  // custom-field-definition import path the pipeline lacks — see the mapping
  // doc / PR notes).
  final notes = _joinNotes([
    if ((record.music ?? '').trim().isNotEmpty)
      'Music: ${record.music!.trim()}',
    ?typeNote,
    if ((record.notes ?? '').trim().isNotEmpty) record.notes!.trim(),
    for (final field in record.userFields)
      if (field.value.trim().isNotEmpty)
        '${field.label.trim().isEmpty ? 'Note' : field.label.trim()}: '
            '${field.value.trim()}',
  ]);

  // Body → figures (design §2). Each `(beats) text` line is routed through the
  // shared [parseFigureLines]: recognised moves become structured figures, the
  // rest fall back to custom (parse-never-fails). A top-level `;` compound
  // splits into one figure per clause (all-or-nothing + Option A beats);
  // single-clause lines are unchanged. Figure text is dialect-scrubbed via
  // [scrubFn]. Section labels are NOT embedded in the figure text (they derive
  // from cumulative beats), so the section label is not prefixed.
  final figures = <Figure>[];
  for (final section in record.body) {
    for (final rawLine in section.lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final (beats, text) = _splitBeats(line);
      figures.addAll(parseFigureLines(text, beats: beats, scrub: scrubFn));
    }
  }

  final dance = Dance(
    id: (newId ?? uuidV4)(),
    title: title,
    form: form,
    formation: formation,
    progression: progression,
    figures: figures,
    callingNotes: notes,
    level: level,
    mixedLevel: mixedLevel,
    rating: rating,
    composedOn: composedOn,
    revisedOn: revisedOn,
    createdAt: now,
    updatedAt: now,
  );

  return CcDanceMapping(dance: dance, issues: issues, authorNames: authorNames);
}

/// Splits a body line's leading `(N)` beats prefix from its text. A missing or
/// malformed prefix yields `(0, wholeLine)` — never throws (parse-never-fails).
(int, String) _splitBeats(String line) {
  final match = RegExp(r'^\(\s*(\d+)\s*\)\s*(.*)$').firstMatch(line);
  if (match == null) return (0, line);
  final beats = int.tryParse(match.group(1)!) ?? 0;
  final text = match.group(2)!.trim();
  // An empty text after a lone "(16)" keeps the beats but stores the original
  // line so nothing is silently dropped.
  return (beats, text.isEmpty ? line : text);
}

(DanceLevel?, bool) _mapLevel(String? raw, List<ImportIssue> issues) {
  final value = raw?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return (null, false);
  if (value.contains('mix')) return (null, true);
  const beginner = {'beginner', 'easy', 'novice', 'basic'};
  const intermediate = {'intermediate', 'medium', 'moderate'};
  const advanced = {'advanced', 'hard', 'challenging', 'difficult', 'expert'};
  if (beginner.contains(value)) return (DanceLevel.beginner, false);
  if (intermediate.contains(value)) return (DanceLevel.intermediate, false);
  if (advanced.contains(value)) return (DanceLevel.advanced, false);
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.warning,
      code: 'cc_unmapped_level',
      message: 'Level "${raw!.trim()}" is unrecognized; left unspecified.',
    ),
  );
  return (null, false);
}

(DanceForm, String?) _mapForm(String? raw, List<ImportIssue> issues) {
  final value = raw?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return (DanceForm.contra, null);
  if (value.contains('contra')) return (DanceForm.contra, null);
  if (value.contains('square')) return (DanceForm.square, null);
  if (value.contains('english') || value == 'ecd') {
    return (DanceForm.ecd, null);
  }
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.info,
      code: 'cc_unmapped_type',
      message:
          'Type "${raw!.trim()}" is unrecognized; imported as a contra and '
          'preserved in the notes.',
    ),
  );
  return (DanceForm.contra, 'Type: ${raw.trim()}');
}

Formation _mapFormation(String? raw, List<ImportIssue> issues) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return const Formation(FormationShape.dupleImproper);
  final value = trimmed.toLowerCase();
  // Order matters: check the more specific tokens first.
  if (value.contains('becket')) {
    return const Formation(FormationShape.becketCw);
  }
  if (value.contains('indecent')) {
    return const Formation(FormationShape.dupleIndecent);
  }
  if (value.contains('improper')) {
    return const Formation(FormationShape.dupleImproper);
  }
  if (value.contains('proper') && value.contains('triple')) {
    return const Formation(FormationShape.tripleMinor);
  }
  if (value.contains('proper')) {
    return const Formation(FormationShape.dupleProper);
  }
  if (value.contains('triple')) {
    return const Formation(FormationShape.tripleMinor);
  }
  if (value.contains('sicilian')) {
    return const Formation(FormationShape.sicilianCircle);
  }
  if (value.contains('circle')) {
    return const Formation(FormationShape.circleMixer);
  }
  if (value.contains('longways')) {
    return const Formation(FormationShape.longways);
  }
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.warning,
      code: 'cc_unmapped_formation',
      message:
          'Formation "$trimmed" is unrecognized; preserved as free-text '
          'detail.',
    ),
  );
  return Formation(FormationShape.other, detail: trimmed);
}

Progression _mapProgression(String? raw, List<ImportIssue> issues) {
  final value = raw?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return Progression.single;
  if (value.contains('none') || value == 'no') return Progression.none;
  if (value.contains('single') || value == '1' || value == '1x') {
    return Progression.single;
  }
  if (value.contains('double') || value == '2' || value == '2x') {
    return Progression.double;
  }
  if (value.contains('triple') || value == '3' || value == '3x') {
    return Progression.triple;
  }
  if (value.contains('quad') || value == '4' || value == '4x') {
    return Progression.quadruple;
  }
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.info,
      code: 'cc_unmapped_progression',
      message:
          'Progression "${raw!.trim()}" is unrecognized; defaulted to single.',
    ),
  );
  return Progression.single;
}

PartialDate? _mapDate(String? raw, String which, List<ImportIssue> issues) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  // Accept the canonical YYYY / YYYY-MM / YYYY-MM-DD shapes; a bare 4-digit
  // year is the common CC case.
  final canonical = RegExp(r'^\d{4}(-\d{2}(-\d{2})?)?$');
  if (canonical.hasMatch(value)) {
    try {
      return PartialDate.parse(value);
    } on FormatException {
      // fall through to the warning
    } on ArgumentError {
      // well-shaped but invalid (e.g. 2004-13) — fall through
    }
  }
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.warning,
      code: 'cc_unparsed_date',
      message:
          'Could not parse the $which date "$value" (expected YYYY, YYYY-MM, '
          'or YYYY-MM-DD); left unset.',
    ),
  );
  return null;
}

String _joinNotes(List<String> parts) =>
    parts.where((p) => p.isNotEmpty).join('\n');

/// Maps CC `Rating` onto the model's closed `1..5` star scale, best-effort.
///
/// Accepts a leading integer (`"4"`, `"4 stars"`) or a run of star glyphs
/// (`"★★★"`). Blank/absent → `null` (unrated, no issue). A value that parses to
/// a number outside `1..5` is dropped with a warning rather than clamped, so an
/// invalid rating never silently becomes a misleading one.
int? _mapRating(String? raw, List<ImportIssue> issues) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  int? parsed;
  final leadingInt = RegExp(r'^-?\d+').firstMatch(value);
  if (leadingInt != null) {
    parsed = int.tryParse(leadingInt.group(0)!);
  } else {
    final stars = RegExp('[★*]').allMatches(value).length;
    if (stars > 0) parsed = stars;
  }

  if (parsed == null) {
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.warning,
        code: 'cc_unparsed_rating',
        message: 'Could not read the rating "$value"; left unrated.',
      ),
    );
    return null;
  }
  if (parsed < 1 || parsed > 5) {
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.warning,
        code: 'cc_rating_out_of_range',
        message: 'Rating "$value" is outside the 1–5 scale; left unrated.',
      ),
    );
    return null;
  }
  return parsed;
}
