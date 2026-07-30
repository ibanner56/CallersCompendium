import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../model/partial_date.dart';
import '../util/text_sanitizer.dart';
import '../util/uuid.dart';
import 'figure_front_end_fan_out.dart';
import 'figure_parser.dart';
import 'structured_draft.dart';

/// The reusable Caller's Companion (CC) → Compendium mapping layer.
///
/// This file is deliberately **source-agnostic**: it knows nothing about *how*
/// a CC dance was obtained. [CallersCompanionTextAdapter] builds a
/// [CcDanceRecord] by parsing CC's "copy formatted dance" clipboard/text
/// export; the FileMaker-12 `.USR` binary reader (`callers_companion_usr_*`)
/// builds the *same* [CcDanceRecord] — its figure body joined from the CC
/// `Phrase` table — and reuses [mapCallersCompanionDance] verbatim. Keep this
/// unit free of text-parsing (or binary-parsing) specifics so both callers can
/// share it.
///
/// The mapping mirrors the CC schema surveyed in
/// `docs/research/callers-companion.md` (§"Schema-level addendum": `Dance`
/// fields `Name`, `Author*`, `Type`, `Formation`, `Level`, `Progression`,
/// `Music`, `DateComposed`/`DateRevised`, and the free-text body — from the
/// `Phrase` table in a real `.USR`, or the `A1`/`A2`/`B1`/`B2`/`C1`/`C2`
/// sections as a fallback), and follows the import design in
/// `docs/design/imports.md` §2 (Caller's Companion migration): **each body line
/// is routed through the shared free-text fan-out** ([parseFigureLinesFanOut])
/// — recognised moves structure into taxonomy figures, and anything the fan-out
/// cannot canonicalize degrades to an honest [CustomOrigin.importGap] `custom`
/// (parse-never-fails, never invents structure).

/// The Caller's Companion figure-text front-end. CC's `(beats) text` body lines
/// are the user's personal free text and never carry TCB paren/annotation
/// notation, so its front-end is the neutral [canonicalFigureFrontEnd]. It is
/// the lowest-precedence tier of the free-text fan-out
/// ([figureFanOutFrontEnds]: ContraDB > TCB > CC); exposed as its own named,
/// independently-callable [FigureFrontEnd] so the fan-out can select it by name.
const FigureFrontEnd callersCompanionFigureFrontEnd = canonicalFigureFrontEnd;

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
}) {
  final issues = <ImportIssue>[];
  final now = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  // Title — placeholder + warning when absent (never throw). Sanitized
  // single-line so control/bidi/format spoofing chars never reach storage
  // (issue #444).
  final rawName = _sanitizeLine(record.name) ?? '';
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
    for (final author in record.authors) ?_sanitizeLine(author),
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

  // Body → figures (design §2). Each `(beats) text` line has its leading beats
  // prefix peeled off ([splitCcBeatPrefix], which accepts a lone `(16)` or a
  // compound `(4,12)`) and is then routed through the shared free-text FAN-OUT
  // ([parseFigureLinesFanOut]): the line is attempted against each source
  // front-end in precedence order (ContraDB > TCB > CC) and the best structuring
  // wins. A compound prefix's total is applied per [_allocateCompoundBeats] —
  // kept whole on a single figure, distributed across a clean split. Every line
  // with content after scrubbing is retained — recognised moves structure into
  // taxonomy figures, the rest as [CustomOrigin.importGap] customs
  // (parse-never-fails); a line that is empty after scrubbing yields nothing
  // (nothing to store). The fan-out applies the core `scrubFigureText`
  // chokepoint internally, and the TCB attempt `;`-splits a compound line into
  // multiple figures. Section labels are NOT embedded in the figure text (they
  // derive from cumulative beats), so the section label is not prefixed.
  final figures = <Figure>[];
  for (final section in record.body) {
    for (final rawLine in section.lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final prefix = splitCcBeatPrefix(line);
      final produced = parseFigureLinesFanOut(prefix.text, beats: prefix.beats);
      figures.addAll(_allocateCompoundBeats(produced, prefix.parts));
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

/// The parsed result of peeling a body line's leading beats prefix: the [beats]
/// total, the ordered per-move [parts] the prefix stated, and the residual
/// [text].
///
/// [parts] is empty for a bare/absent or malformed prefix and single-element for
/// a lone `(16)`; it holds one entry per comma-separated group for a compound
/// `(4,12)`. The allocation step ([_allocateCompoundBeats]) uses it to decide
/// whether the total rides on one figure or is distributed across a clean split.
typedef CcBeatPrefix = ({int beats, List<int> parts, String text});

/// Longest digit run we will read for a single beat group. Mirrors the 4-digit
/// inline-beat cap in `free_text_entry.dart` (`_maxInlineBeatDigits`): anything
/// longer is not treated as a beat count, so a hostile/absurd value can never
/// overflow an int or drive downstream duration math off the rails. Full OWASP
/// limits for the CC tables are #561's job; this mirrors the existing spirit.
const int _maxCcBeatDigits = 4;

/// A leading beats prefix: a lone `(16)` or a compound `(4,12)` / `(4, 12)`
/// (whitespace-tolerant), each group a bounded digit run. A prefix that is
/// absent or malformed (`()`, `(x)`, `(4,)`, `(,12)`) simply does not match and
/// is left as ordinary text.
final RegExp _ccBeatPrefix = RegExp(
  '^\\(\\s*(\\d{1,$_maxCcBeatDigits}(?:\\s*,\\s*\\d{1,$_maxCcBeatDigits})*)\\s*\\)'
  '\\s*(.*)\$',
);

/// Splits a body line's leading beats prefix from its text.
///
/// Accepts a lone `(16)`, a **compound** `(4,12)` / `(4, 12)` (whitespace-
/// tolerant, each group ≤ 4 digits), and a bare/absent prefix (beats `0`). A
/// **malformed** prefix (`()`, `(x)`, `(4,)`, `(,12)`) does not match and is
/// treated as ordinary text — the whole line is returned with beats `0` and no
/// parts. Never throws (`parse-never-fails`).
///
/// The returned [CcBeatPrefix.beats] is the **sum** of a compound prefix's
/// [CcBeatPrefix.parts] (`(4,12)` → `16`, parts `[4, 12]`); how that total is
/// applied to the resulting figure(s) — kept whole for a single move or
/// distributed across a clean split — is decided by [_allocateCompoundBeats].
@visibleForTesting
CcBeatPrefix splitCcBeatPrefix(String line) {
  final match = _ccBeatPrefix.firstMatch(line);
  if (match == null) return (beats: 0, parts: const <int>[], text: line);
  final parts = [
    for (final g in match.group(1)!.split(',')) int.parse(g.trim()),
  ];
  final total = parts.fold<int>(0, (sum, p) => sum + p);
  final text = match.group(2)!.trim();
  // An empty text after a lone "(16)" keeps the beats but stores the original
  // line so nothing is silently dropped.
  return (
    beats: total,
    parts: parts,
    text: text.isEmpty ? line : text,
  );
}

/// Applies a compound prefix's per-move [parts] to the [figures] the fan-out
/// produced for one body line.
///
/// **Compound-beat semantics (#560).** A compound prefix `(a,b,…)` states the
/// per-move beats of a single source line whose **sum** is the line's total:
/// - a line that structures as a **single** figure (the common case — e.g.
///   `(4,12) neighbors balance and swing` is one swing with a balance prefix)
///   carries the **total** (the sum is already on that lone figure, so it is
///   left untouched);
/// - a line that the fan-out cleanly **splits** into exactly as many non-custom
///   figures as there are parts has each part **distributed** to the
///   corresponding figure, in order;
/// - **any other case** (part-count ≠ figure-count, or a custom fallback) keeps
///   the fan-out's own allocation, which rides the total on the first figure
///   (the shared splitter's Option A). That is always lossless w.r.t. the
///   cumulative total — it never invents an allocation the source did not state.
List<Figure> _allocateCompoundBeats(List<Figure> figures, List<int> parts) {
  if (parts.length < 2 ||
      figures.length != parts.length ||
      figures.any((f) => f.isCustom)) {
    return figures;
  }
  return [
    for (var i = 0; i < figures.length; i++)
      _withBeats(figures[i], parts[i]),
  ];
}

/// Returns [figure] with its beats set to [beats], preserving the convention
/// that a `0` (absent) count is not stored in `params`.
Figure _withBeats(Figure figure, int beats) {
  final params = {...figure.params};
  if (beats > 0) {
    params['beats'] = beats;
  } else {
    params.remove('beats');
  }
  return figure.copyWith(params: params);
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
  final trimmed = _sanitizeLine(raw) ?? '';
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

/// Upper bound on a date string we will attempt to parse. Real composed/revised
/// values are short (`"2004"`, `"15 March 2004"`); anything longer is treated as
/// unparseable rather than fed to the regexes. Defense-in-depth against
/// pathological imported input (the anchored patterns below are already
/// linear-time / ReDoS-safe, but bounding the length keeps work trivial).
const int _kMaxDateLength = 64;

/// English month names and common abbreviations → month number (1–12).
/// Lower-cased keys; lookups lower-case their input. Includes the `sept`
/// abbreviation in addition to the canonical `sep`.
const Map<String, int> _ccMonthNames = {
  'january': 1,
  'jan': 1,
  'february': 2,
  'feb': 2,
  'march': 3,
  'mar': 3,
  'april': 4,
  'apr': 4,
  'may': 5,
  'june': 6,
  'jun': 6,
  'july': 7,
  'jul': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sep': 9,
  'sept': 9,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};

/// Builds a [PartialDate] via the validating constructor, returning `null`
/// (rather than throwing) for any calendar-invalid combination (e.g. `Feb 30`,
/// month 13). Callers treat `null` as "unparseable" and fall through.
PartialDate? _tryPartialDate(int year, [int? month, int? day]) {
  try {
    return PartialDate(year, month, day);
  } on ArgumentError {
    return null;
  }
}

/// Maps a CC composed/revised date string onto a [PartialDate], accepting the
/// common human/locale shapes observed in Caller's Companion exports and
/// degrading to year-only precision when only the year is safely recoverable.
///
/// Input is untrusted (imported `.USR`/CC data): the string is length-bounded,
/// every pattern is anchored and non-backtracking (ReDoS-safe), and every
/// candidate is validated through the [PartialDate] constructor. Any
/// interpretation that relied on an assumption (US month/day ordering, or a
/// year-only reduction) is surfaced as an [ImportIssue] rather than applied
/// silently. Anything still unparseable emits a warning and returns `null`.
PartialDate? _mapDate(String? raw, String which, List<ImportIssue> issues) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  if (value.length <= _kMaxDateLength) {
    // 1. Canonical ISO: YYYY / YYYY-MM / YYYY-MM-DD. A shape match that fails
    // validation (e.g. 2004-13) falls through to the warning rather than being
    // reduced to a year — a malformed but date-shaped value is surfaced loudly.
    if (RegExp(r'^\d{4}(-\d{2}(-\d{2})?)?$').hasMatch(value)) {
      try {
        return PartialDate.parse(value);
      } on FormatException {
        // fall through
      } on ArgumentError {
        // well-shaped but invalid (e.g. 2004-13) — fall through
      }
    }

    // 2. Month-name formats (unambiguous → full precision).
    final named = _parseMonthNameDate(value);
    if (named.matched) {
      if (named.date != null) return named.date;
      // Recognized shape but calendar-invalid (e.g. Feb 30) — warn, do not
      // silently reduce a malformed date to its year.
      return _unparsedDate(value, which, issues);
    }

    // 3. Numeric slash/dot/hyphen dates with a clear 4-digit year.
    final numeric = _parseNumericDate(value, which, issues);
    if (numeric.matched) {
      if (numeric.date != null) return numeric.date;
      return _unparsedDate(value, which, issues);
    }

    // 4. Year-only degrade: only reached when the value did not look like a
    // fuller date shape. A single standalone 4-digit year is recoverable.
    final yearOnly = _parseYearOnly(value, which, issues);
    if (yearOnly != null) return yearOnly;
  }

  return _unparsedDate(value, which, issues);
}

/// Emits the standard `cc_unparsed_date` warning and returns `null`.
PartialDate? _unparsedDate(
  String value,
  String which,
  List<ImportIssue> issues,
) {
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.warning,
      code: 'cc_unparsed_date',
      message:
          'Could not parse the $which date "$value" (expected e.g. YYYY, '
          'YYYY-MM, YYYY-MM-DD, "March 2004", "15 March 2004", or a numeric '
          'date with a 4-digit year); left unset.',
      data: {'field': which},
    ),
  );
  return null;
}

/// Result of a shape-specific date parse: [matched] is whether the value looked
/// like this shape at all (so the caller knows whether to try the next, looser
/// layer), and [date] is the validated result (null when the shape matched but
/// was calendar-invalid — the caller then warns rather than degrading).
typedef _DateParse = ({bool matched, PartialDate? date});

const _DateParse _noMatch = (matched: false, date: null);

/// Parses month-name shapes. Case-insensitive. Accepts:
/// `March 2004` / `Mar 2004` / `March, 2004` (month precision), and
/// `March 15, 2004` / `Mar 15 2004` / `15 March 2004` / `15 Mar 2004`
/// (day precision). Returns [matched] false when no known month name leads the
/// shape (so an unknown word like `Smarch 2004` can still degrade to its year);
/// returns matched with a null date for a recognized-but-invalid date.
_DateParse _parseMonthNameDate(String value) {
  // "<name> [day,] year"  e.g. "March 2004", "March 15, 2004", "Mar 15,2004".
  // The separator between the name/day/year tokens is either whitespace or a
  // comma (with optional surrounding whitespace), so a comma without a space
  // (`March 15,2004`) is accepted; a missing separator (`March 152004`) is not.
  final nameFirst = RegExp(
    r'^([A-Za-z]{3,9})\.?(?:\s*,\s*|\s+)(?:(\d{1,2})(?:\s*,\s*|\s+))?(\d{4})$',
  ).firstMatch(value);
  if (nameFirst != null) {
    final month = _ccMonthNames[nameFirst.group(1)!.toLowerCase()];
    if (month == null) return _noMatch;
    final year = int.parse(nameFirst.group(3)!);
    final dayStr = nameFirst.group(2);
    final day = dayStr == null ? null : int.parse(dayStr);
    return (matched: true, date: _tryPartialDate(year, month, day));
  }

  // "<day> <name> <year>"  e.g. "15 March 2004", "15 Mar 2004".
  final dayFirst = RegExp(
    r'^(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{4})$',
  ).firstMatch(value);
  if (dayFirst != null) {
    final month = _ccMonthNames[dayFirst.group(2)!.toLowerCase()];
    if (month == null) return _noMatch;
    final year = int.parse(dayFirst.group(3)!);
    final day = int.parse(dayFirst.group(1)!);
    return (matched: true, date: _tryPartialDate(year, month, day));
  }
  return _noMatch;
}

/// Parses purely-numeric slash/dot/hyphen dates that carry a single clear
/// 4-digit year. Returns [matched] false when the value is not a numeric date
/// shape at all; matched with a null date when it is but cannot resolve to a
/// valid date (e.g. a `2004-2005` range, `13/14/2004`, `2/31/2004`).
///
/// Ordering rules (year is always the 4-digit component):
/// - `YYYY[sep]M[sep]D` (year first) → Y/M/D by position.
/// - `M[sep]YYYY` → month precision; `YYYY[sep]M` → month precision.
/// - `A[sep]B[sep]YYYY` (year last): if exactly one of A,B is >12 it must be the
///   day (deterministic); the other is the month. If both ≤12 the ordering is
///   genuinely ambiguous → assume US MM/DD and emit an info `cc_date_assumed_mdy`
///   issue so the assumption is auditable, never silent.
_DateParse _parseNumericDate(
  String value,
  String which,
  List<ImportIssue> issues,
) {
  final parts = RegExp(
    r'^(\d{1,4})[/.\-](\d{1,4})(?:[/.\-](\d{1,4}))?$',
  ).firstMatch(value);
  if (parts == null) return _noMatch;

  final a = parts.group(1)!;
  final b = parts.group(2)!;
  final c = parts.group(3);

  bool isYear(String s) => s.length == 4;

  if (c == null) {
    // Two components: month + 4-digit year, in either order.
    if (isYear(a) && !isYear(b)) {
      return (matched: true, date: _tryPartialDate(int.parse(a), int.parse(b)));
    }
    if (isYear(b) && !isYear(a)) {
      return (matched: true, date: _tryPartialDate(int.parse(b), int.parse(a)));
    }
    return (matched: true, date: null);
  }

  // Three components. Require exactly one 4-digit year, first or last.
  final yearFirst = isYear(a) && !isYear(b) && !isYear(c);
  final yearLast = isYear(c) && !isYear(a) && !isYear(b);

  if (yearFirst) {
    // Y/M/D by position.
    return (
      matched: true,
      date: _tryPartialDate(int.parse(a), int.parse(b), int.parse(c)),
    );
  }
  if (yearLast) {
    final year = int.parse(c);
    final first = int.parse(a);
    final second = int.parse(b);
    if (first > 12 && second <= 12) {
      // first is the day.
      return (matched: true, date: _tryPartialDate(year, second, first));
    }
    if (second > 12 && first <= 12) {
      // second is the day.
      return (matched: true, date: _tryPartialDate(year, first, second));
    }
    if (first <= 12 && second <= 12) {
      // Genuinely ambiguous — assume US MM/DD ordering and flag it.
      final date = _tryPartialDate(year, first, second);
      if (date != null) {
        issues.add(
          ImportIssue(
            severity: ImportIssueSeverity.info,
            code: 'cc_date_assumed_mdy',
            message:
                'Ambiguous $which date "$value" was interpreted as MM/DD '
                '(US ordering): ${date.serialize()}. Verify if the source '
                'used day-first ordering.',
            data: {'field': which},
          ),
        );
      }
      return (matched: true, date: date);
    }
    // Both >12: cannot be a valid month/day pair.
    return (matched: true, date: null);
  }
  return (matched: true, date: null);
}

/// Recovers a year-only [PartialDate] when the year is the *only* number in the
/// value (e.g. `Spring 2004`, `c. 2004`, `2004?`), emitting an info
/// `cc_date_reduced_precision` issue to record that no finer precision was
/// available. Requires exactly one run of digits and that it is a 4-digit year,
/// so a value that still carries other numeric components (a partially-parseable
/// or malformed fuller date, or a `2004-2005` range) is *not* silently reduced —
/// the caller warns instead. Uses only simple digit-run matching (no lookbehind).
PartialDate? _parseYearOnly(
  String value,
  String which,
  List<ImportIssue> issues,
) {
  final runs = RegExp(r'\d+').allMatches(value).toList();
  if (runs.length != 1) return null;
  final token = runs.single.group(0)!;
  if (token.length != 4) return null;
  final year = int.parse(token);
  final date = _tryPartialDate(year);
  if (date == null) return null;
  issues.add(
    ImportIssue(
      severity: ImportIssueSeverity.info,
      code: 'cc_date_reduced_precision',
      message:
          'Recovered only the year $year from the $which date "$value"; '
          'no month or day was present to parse.',
      data: {'field': which, 'year': year},
    ),
  );
  return date;
}

String _joinNotes(List<String> parts) =>
    // Multi-line sanitize (issue #444): strip control/bidi/format spoofing
    // characters from the assembled notes while preserving legitimate newlines.
    sanitizeImportedText(parts.where((p) => p.isNotEmpty).join('\n')).trim();

/// Sanitizes a single-line imported string (title, author, formation detail),
/// stripping control, bidi-override and invisible/format characters plus any
/// embedded tab/newline/CR (issue #444). Returns null for null/blank/all-
/// stripped input.
String? _sanitizeLine(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final clean = sanitizeImportedText(trimmed, allowLineBreaks: false).trim();
  return clean.isEmpty ? null : clean;
}

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
