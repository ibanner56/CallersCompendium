import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/partial_date.dart';
import '../util/uuid.dart';
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
    List<CcBodySection> body = const [],
  }) : authors = List.unmodifiable(authors),
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

  /// The free-text transcription body, grouped by CC section.
  final List<CcBodySection> body;
}

/// The result of [mapCallersCompanionDance]: a [Dance] draft plus the non-fatal
/// [ImportIssue]s raised while mapping (unresolved author, unmapped level,
/// etc.). The dance carries no provenance — the [ImportPipeline] attaches that
/// at commit — and its id/timestamps are placeholders the pipeline reassigns.
@immutable
class CcDanceMapping {
  CcDanceMapping({required this.dance, List<ImportIssue> issues = const []})
    : issues = List.unmodifiable(issues);

  final Dance dance;
  final List<ImportIssue> issues;
}

/// Placeholder title used when a CC record supplies no name. Parsing never
/// fails on a missing title (`docs/design/imports.md`, parse-never-fails); a
/// [ImportIssue] is raised instead so the review queue can prompt for a real
/// one.
const String ccUntitledDanceTitle = "Untitled Caller's Companion dance";

/// Maps a source-agnostic [CcDanceRecord] into a [Dance] draft and the issues
/// raised while doing so. **Never throws on content** — a missing title, an
/// unmapped level/formation, or an unparseable date all surface as
/// [ImportIssue]s, and every body line becomes a [customFigure] regardless of
/// shape (the parse-never-fails invariant). This is the single unit both the
/// text adapter and the future `.USR` reader call.
///
/// The draft's identity is disposable: [newId] (default [uuidV4]) and
/// [timestamp] (default the Unix epoch) exist only so a valid [Dance] can be
/// constructed — the pipeline reassigns id/`createdAt`/`updatedAt` at commit.
CcDanceMapping mapCallersCompanionDance(
  CcDanceRecord record, {
  String Function()? newId,
  DateTime? timestamp,
}) {
  final issues = <ImportIssue>[];
  final now = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

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

  // Authors — names cannot be turned into authorIds (those are foreign keys to
  // existing Choreographer rows) and this mapping never creates records, so we
  // surface each name for the review step to link/create.
  for (final author in record.authors) {
    final name = author.trim();
    if (name.isEmpty) continue;
    issues.add(
      ImportIssue(
        severity: ImportIssueSeverity.info,
        code: 'cc_unresolved_author',
        message:
            'Author "$name" needs to be linked to or created as a '
            'choreographer during review.',
      ),
    );
  }

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

  // Notes: Music + an unmapped-type note + any extra source notes.
  final notes = _joinNotes([
    if ((record.music ?? '').trim().isNotEmpty)
      'Music: ${record.music!.trim()}',
    ?typeNote,
    if ((record.notes ?? '').trim().isNotEmpty) record.notes!.trim(),
  ]);

  // Body → custom figures (free text; design §2). Section label is prefixed so
  // the caller's grouping survives even though we infer no structured sections.
  final figures = <Figure>[];
  for (final section in record.body) {
    final label = section.label?.trim();
    for (final rawLine in section.lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final (beats, text) = _splitBeats(line);
      final withLabel = (label == null || label.isEmpty)
          ? text
          : '$label: $text';
      figures.add(customFigure(withLabel, beats: beats));
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
    composedOn: composedOn,
    revisedOn: revisedOn,
    createdAt: now,
    updatedAt: now,
  );

  return CcDanceMapping(dance: dance, issues: issues);
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
