import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

/// Localized presentation of core [ValidationIssue]s (and the phrase-structure
/// [FormatException]) rendered in the editors.
///
/// The core layer keeps a stable `code` discriminator plus typed [data] on each
/// issue; its `message` is an internal English diagnostic that is **not**
/// displayed in a localized UI. This mapper turns `code` (+ `data`) into a
/// localized string at the presentation boundary, mirroring
/// `import_error_labels.dart`.
///
/// Security: user-entered dialect/program text carried in [data] is rendered as
/// plain text through gen-l10n placeholders (safe in Flutter). Any raw
/// lower-layer/parser detail is surfaced only under [kDebugMode] — never in a
/// release build (CWE-209).

/// The [ValidationIssue] codes this mapper localizes explicitly. Any other code
/// falls back to [AppLocalizations.validationGeneric]. Exposed for the coverage
/// test that guards against a silent English leak.
const Set<String> mappedValidationCodes = {
  'phrase_overflow',
  'phrase_underflow',
  'sequence_exceeds_phrase',
  'sequence_span_mismatch',
  incompleteFigureValidationCode,
  otherFormFiguresValidationCode,
  figureCrossesPhraseCode,
  'orphaned_alt',
  'empty_substitution',
  'dialect_collision',
  'gendered_role_term',
};

/// The [ValidationIssue.code] of a figure row that Save would leave out
/// because it is not complete (AUTH-2), with its 1-based `position`. Only the
/// dance editor raises it, from its drafts: no saved dance can hold such a row.
const String incompleteFigureValidationCode = 'incomplete_figure';

/// The [ValidationIssue.code] of a dance that holds `count` figures of
/// another form (`figureForm`) than its own (`danceForm`), as
/// [DanceForm.name]s. Only the dance editor raises it.
const String otherFormFiguresValidationCode = 'other_form_figures';

/// Localized message for a [ValidationIssue] surfaced in an editor.
///
/// [keyLabel], when given, names a dialect entry's source key, the move a
/// substitution is for: the dialect editor names a figure of your own by its
/// name rather than its `userFigure:<id>` key (#1023).
///
/// [timing], when given, is how a dance timed in bars counts them
/// ([barTimingFor]): its counts then read in bars, as its figures do, where
/// every count in the message is a whole number of half bars. Each count reads
/// from where it starts: a total from the start of the dance, a sequence's
/// from the sequence's `startBeat`, and a phrase's length from the start of
/// that phrase (`limitStart`), so that where the phrases differ in beats per
/// bar each reads in the bars of its own part of the tune.
String validationIssueMessage(
  AppLocalizations l10n,
  ValidationIssue issue, {
  String Function(String key)? keyLabel,
  BarTiming? timing,
}) {
  final localized = _localizedValidation(
    l10n,
    issue,
    keyLabel ?? (k) => k,
    timing,
  );
  if (localized != null) return localized;
  // No specific localization (unknown code, or expected structured data
  // missing/ill-typed): generic, non-leaking fallback. The diagnostic English
  // is appended only in debug builds — never in a release UI (CWE-209).
  return kDebugMode
      ? '${l10n.validationGeneric} [${issue.code}: ${issue.message}]'
      : l10n.validationGeneric;
}

/// Returns the specific localized message for [issue], or `null` when the code
/// is unmapped or its required safe structured data is absent/ill-typed (so the
/// caller can fall back to the generic message rather than render a misleading
/// value such as "0 beats").
String? _localizedValidation(
  AppLocalizations l10n,
  ValidationIssue issue,
  String Function(String key) keyLabel,
  BarTiming? timing,
) {
  final data = issue.data;
  // The counts as bars ("32 bars"), each from where it starts, or null to
  // read them in beats: without a timing, or where any of them is no whole
  // number of half bars, so that one message never mixes the two.
  List<String>? inBars(List<({int? start, int beats})> counts) {
    if (timing == null) return null;
    String? one(int? start, int beats) {
      if (start == null) return null;
      final bars = timing.barsTextAt(start, beats);
      return bars == null
          ? null
          : l10n.danceFigureBars(bars.text, bars.halfBars);
    }

    final texts = [for (final (:start, :beats) in counts) one(start, beats)];
    return texts.contains(null) ? null : [...texts.nonNulls];
  }

  int startOf(Object? start) => start is int && start >= 0 ? start : 0;

  switch (issue.code) {
    case 'phrase_overflow':
    case 'phrase_underflow':
      final actual = data['actual'];
      final expected = data['expected'];
      if (actual is! int || expected is! int) return null;
      if (inBars([(start: 0, beats: actual), (start: 0, beats: expected)])
          case [final a, final e]) {
        return l10n.validationPhraseCountMismatch(a, e);
      }
      return l10n.validationPhraseBeatMismatch(actual, expected);
    case incompleteFigureValidationCode:
      final position = data['position'];
      return position is int ? l10n.validationIncompleteFigure(position) : null;
    case 'sequence_exceeds_phrase':
      final position = data['position'];
      final actual = data['actual'];
      final limit = data['limit'];
      if (position is! int || actual is! int || limit is! int) return null;
      // The limit is the length of the phrase the sequence starts in: it reads
      // from where that phrase starts. Where the data gives none, a tune in
      // one meter reads it anywhere, and any other in beats.
      final limitStart = data['limitStart'] is int
          ? data['limitStart'] as int
          : timing != null && timing.isFixed
          ? 0
          : null;
      if (inBars([
            (start: startOf(data['startBeat']), beats: actual),
            (start: limitStart, beats: limit),
          ])
          case [final a, final l]) {
        return l10n.validationSequenceExceedsPhraseCount(position, a, l);
      }
      return l10n.validationSequenceExceedsPhrase(position, actual, limit);
    case 'sequence_span_mismatch':
      final position = data['position'];
      final actual = data['actual'];
      final expected = data['expected'];
      if (position is! int || actual is! int || expected is! int) return null;
      final noRoom = data['allTimed'] == false;
      final start = startOf(data['startBeat']);
      if (inBars([
            (start: start, beats: actual),
            (start: start, beats: expected),
          ])
          case [final a, final e]) {
        return noRoom
            ? l10n.validationSequenceSpanNoRoomCount(position, a, e)
            : l10n.validationSequenceSpanMismatchCount(position, a, e);
      }
      return noRoom
          ? l10n.validationSequenceSpanNoRoom(position, actual, expected)
          : l10n.validationSequenceSpanMismatch(position, actual, expected);
    case otherFormFiguresValidationCode:
      final count = data['count'];
      final figureForm = _formNamed(data['figureForm']);
      final danceForm = _formNamed(data['danceForm']);
      final pickerForm = _formNamed(data['pickerForm']) ?? danceForm;
      if (count is! int ||
          figureForm == null ||
          danceForm == null ||
          pickerForm == null) {
        return null;
      }
      return l10n.validationOtherFormFigures(
        count,
        danceFormLabel(l10n, danceForm),
        danceFormLabel(l10n, figureForm),
        danceFormLabel(l10n, pickerForm),
      );
    case figureCrossesPhraseCode:
      final position = data['position'];
      final label = data['label'];
      if (position is! int || label is! String) return null;
      return l10n.validationFigureCrossesPhrase(position, label);
    case 'orphaned_alt':
      final position = data['position'];
      if (position is! int) return null;
      final text = data['text'] as String?;
      return text == null
          ? l10n.validationOrphanedAlt(position)
          : l10n.validationOrphanedAltNamed(position, text);
    case 'empty_substitution':
      final source = data['source'];
      return source is String
          ? l10n.validationEmptySubstitution(keyLabel(source))
          : null;
    case 'dialect_collision':
      final source = data['source'];
      final existing = data['existing'];
      final substitution = data['substitution'];
      return (source is String && existing is String && substitution is String)
          ? l10n.validationDialectCollision(
              keyLabel(source),
              keyLabel(existing),
              substitution,
            )
          : null;
    case 'gendered_role_term':
      final word = data['word'];
      return word is String ? l10n.validationGenderedRoleTerm(word) : null;
    default:
      return null;
  }
}

/// Localized field error for an invalid phrase-structure string. The raw
/// [FormatException] message is opaque parser text, so it is shown only under
/// [kDebugMode]; release builds get the generic localized message (CWE-209).
String phraseStructureErrorMessage(
  AppLocalizations l10n,
  FormatException error,
) => kDebugMode
    ? '${l10n.validationPhraseInvalid} [${error.message}]'
    : l10n.validationPhraseInvalid;

DanceForm? _formNamed(Object? name) {
  for (final form in DanceForm.values) {
    if (form.name == name) return form;
  }
  return null;
}
