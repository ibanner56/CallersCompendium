import '../dialect/canonicalize.dart';
import '../dialect/dialect.dart';
import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'callersbox_figure_dialect.dart' show hasTopLevelSeparator;
import 'figure_front_end_fan_out.dart';
import 'figure_text_scrub.dart';
import 'shorthand_mappings.dart';
import 'structured_draft.dart';
import 'typed_figure_names.dart';

/// Longest inline beat count we will parse from a free-text line. Bounds the
/// digits turned into an int so a hostile/absurd value (`(999999999999)`) can
/// never overflow one or drive downstream duration math off the rails — a count
/// past four digits is never parsed: it is not a beat count. Free-text entry
/// keeps it in the figure's note when the line states no readable count, and in
/// a custom's typed text otherwise ([_BeatSplit.unread], #1863). Four digits
/// (≤ 9999) comfortably covers any real contra figure while staying safe.
const int _maxInlineBeatDigits = 4;

/// Upper bound on the length of a single free-text entry line we will feed
/// through the parser. A real figure line — even a `;`-compound — is at most a
/// few dozen characters; anything beyond this is treated as malformed/hostile
/// input and yields nothing rather than driving unbounded recognition work.
/// This mirrors the OWASP "bounded input" posture of the rest of the import
/// path (see `maxReparseTextLength`): even though the text is typed locally we
/// treat it as untrusted, and the guard is enforced in core (defense in depth)
/// rather than relying on any UI-side field limit.
const int maxFreeTextEntryLength = 2000;

/// The optional unit after a count's digits: `16 beats`, `(8 beat)` (#1826).
const String _beatsUnit = '(?:\\s*beats?)';

/// A leading beat count: a bare `16 balance and swing`, or a bracketed
/// `(16) balance and swing` / `[16] balance and swing`, each optionally with a
/// `beats` unit (`16 beats …`, `(16 beats) …`). A bare count must be
/// followed by whitespace AND a non-empty remainder, so a fraction/positional
/// token glued to the digits (`1/2 hey`, `1s cross`) is NOT mistaken for a
/// count (there is no space after the leading digits in those). A bracketed
/// count needs no space (`(16)swing`), as the trailing form needs none.
final RegExp _leadingBeats = RegExp(
  '^(?:(\\d+)(?:\\s+beats?)?\\s+'
  '|[(\\[](\\d+)$_beatsUnit?[)\\]]\\s*)(\\S.*)\$',
  caseSensitive: false,
);

/// A trailing beat count: a bracketed `balance and swing (16)` or `… [16]`, or
/// one with a `beats` unit, bracketed or not (`… (16 beats)`, `… 16 beats`).
/// Only digits (and the unit) at the very end count — a trailing prose
/// annotation (`allemande (once)`) is left untouched, and so is a bare
/// trailing number with no unit (`neighbors swing 16`), which free text keeps
/// custom (see `demoteNoteTails`).
final RegExp _trailingBeats = RegExp(
  '^(.*\\S)(?:\\s*[(\\[](\\d+)$_beatsUnit?[)\\]]'
  '|\\s+(\\d+)\\s*beats?)\$',
  caseSensitive: false,
);

/// A positive `(N)`/`[N]` group of ANY length at the start or end of a line,
/// or a count with a `beats` unit there (`(8 beats)`, `16 beats`). The
/// recogniser tolerates a digits-only group as an annotation and drops it, and
/// keeps a unit count as a note, so one that [_splitInlineBeats] did not turn
/// into the beat count (a second count) must keep the line out of the parser
/// or the number would vanish or be misread. A count too long to be beats is
/// peeled instead ([_BeatSplit.unread]). A zero count is not matched: 0 is
/// "unspecified", see [_splitInlineBeats].
final RegExp _strayLeadingCount = RegExp(
  r'^(?:[(\[]\s*0*[1-9]\d*(?:\s*beats?)?\s*[)\]]|0*[1-9]\d*\s*beats?\b)',
  caseSensitive: false,
);
final RegExp _strayTrailingCount = RegExp(
  r'(?:[(\[]\s*0*[1-9]\d*(?:\s*beats?)?\s*[)\]]|\b0*[1-9]\d*\s*beats?)$',
  caseSensitive: false,
);

/// The count forms of one reader: where a count may sit, and what a stated
/// count that was not read looks like.
typedef _CountForms = ({
  RegExp leading,
  RegExp trailing,
  RegExp strayLeading,
  RegExp strayTrailing,
  bool keepsUnread,
});

/// Free-text entry's forms, `beats` unit included.
final _CountForms _typedCounts = (
  leading: _leadingBeats,
  trailing: _trailingBeats,
  strayLeading: _strayLeadingCount,
  strayTrailing: _strayTrailingCount,
  keepsUnread: true,
);

/// The re-parse upgrade's forms ([splitForReparse]): the unit-less ones, as
/// before the `beats` unit (#1826). That upgrade also runs over customs that
/// came from imports, whose behaviour stays unchanged.
final _CountForms _reparseCounts = (
  leading: RegExp(
    '^(?:(\\d{1,$_maxInlineBeatDigits})\\s+'
    '|[(\\[](\\d{1,$_maxInlineBeatDigits})[)\\]]\\s*)(\\S.*)\$',
  ),
  trailing: RegExp('^(.*\\S)\\s*[(\\[](\\d{1,$_maxInlineBeatDigits})[)\\]]\$'),
  strayLeading: RegExp(r'^[(\[]\s*0*[1-9]\d*\s*[)\]]'),
  strayTrailing: RegExp(r'[(\[]\s*0*[1-9]\d*\s*[)\]]$'),
  keepsUnread: false,
);

/// Result of splitting an optional inline beat count off a free-text line.
class _BeatSplit {
  const _BeatSplit(this.text, this.beats, this.forms, {this.unread});

  /// The line with any recognised inline beat token removed.
  final String text;

  /// The extracted beat count, or 0 when the line stated none (0 is treated as
  /// "unspecified" everywhere downstream — see [parseFigureLine]).
  final int beats;

  /// The count forms [text] was split with.
  final _CountForms forms;

  /// The count that was peeled off but is not a beat count: five or more
  /// digits (`10000 beats`). Free text keeps it as a note on the figure it was
  /// typed with (#1863); [beats] is 0, so the figure takes its default.
  final String? unread;

  /// Whether [text] still starts or ends with a stated count that was not read
  /// as [beats].
  bool get hasStrayCount =>
      forms.strayLeading.hasMatch(text) || forms.strayTrailing.hasMatch(text);
}

/// Extracts an optional inline beat count from a trimmed free-text [line]. A
/// trailing `(N)`/`[N]` or `N beats` is checked first (it is unambiguous —
/// digits inside brackets, or with their unit, at the end), then a leading
/// `N `, `(N)` or `[N]`, any of them with a `beats` unit. Returns the
/// line unchanged with 0 beats when neither form is present — or when the
/// stated count parses to 0. Because 0 is "unspecified" downstream, stripping a
/// `(0)`/`0 ` token would silently mutate the user's text for no gain, so a
/// zero count leaves the whole line intact (it flows into the parser verbatim
/// — e.g. as an honest custom). [forms] defaults to free-text entry's.
///
/// A count of more than [_maxInlineBeatDigits] digits is not a beat count. It is
/// only peeled when the line states no count that is: it becomes
/// [_BeatSplit.unread] with 0 beats, so the figure takes its default (#1863).
/// The reparse forms never read one. A count of four digits or fewer is the
/// beats here, whatever its size: the parser and [_parseCountedClauses] hold it
/// to the taxonomy's 0..64 range.
_BeatSplit _splitInlineBeats(String line, [_CountForms? forms]) {
  final f = forms ?? _typedCounts;
  bool isZero(String digits) => digits.replaceAll('0', '').isEmpty;
  int? readable(String digits) {
    if (digits.length > _maxInlineBeatDigits) return null;
    final beats = int.parse(digits);
    return beats > 0 ? beats : null;
  }

  final trailing = f.trailing.firstMatch(line);
  final trailingDigits = trailing == null
      ? null
      : trailing.group(2) ?? trailing.group(3)!;
  final leading = f.leading.firstMatch(line);
  final leadingDigits = leading == null
      ? null
      : leading.group(1) ?? leading.group(2)!;
  final trailingBeats = trailingDigits == null
      ? null
      : readable(trailingDigits);
  if (trailingBeats != null) {
    return _BeatSplit(trailing!.group(1)!.trim(), trailingBeats, f);
  }
  final leadingBeats = leadingDigits == null ? null : readable(leadingDigits);
  if (leadingBeats != null) {
    return _BeatSplit(leading!.group(3)!.trim(), leadingBeats, f);
  }
  if (f.keepsUnread) {
    if (trailingDigits != null && !isZero(trailingDigits)) {
      final token = line.substring(trailing!.group(1)!.length);
      return _BeatSplit(
        trailing.group(1)!.trim(),
        0,
        f,
        unread: _countToken(token),
      );
    }
    if (leadingDigits != null && !isZero(leadingDigits)) {
      final token = line.substring(0, line.length - leading!.group(3)!.length);
      return _BeatSplit(
        leading.group(3)!.trim(),
        0,
        f,
        unread: _countToken(token),
      );
    }
  }
  return _BeatSplit(line, 0, f);
}

/// A count as typed, without its brackets: `(10000 beats)` is `10000 beats`.
String _countToken(String typed) => typed
    .replaceAll(RegExp(r'[()\[\]]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// [figure] with the unread count [token] added to its note.
Figure _withUnreadCount(Figure figure, String token) => figure.copyWith(
  note: figure.note == null ? token : '${figure.note}; $token',
);

/// Parses one free-text figure line typed in the editor's opt-in "Free-text
/// entry" mode (issue #419) into structured/custom [Figure]s.
///
/// When a [shorthands] store is supplied it is consulted FIRST (issue #420):
/// the whole trimmed line is matched against the user's shorthand tokens as an
/// EXACT, whole-line token (case-insensitive + trim-insensitive; no mid-line or
/// substring substitution, keeping expansion deterministic). On a hit the line
/// expands to the mapped figure(s) and those are returned verbatim.
///
/// On a whole-line miss the shorthands are tried again, still token-exact, in
/// two further ways (issue #1827), so a shorthand does not stop working the
/// moment it is given a count or a neighbour:
/// - a **leading** `16 pbs` or **trailing** `pbs (16)` count (the same two forms
///   as below) is peeled off and the rest matched. A shorthand that expands to
///   exactly ONE figure (a single meanwhile or modifier container included, whose
///   own beats it sets) takes the count as that figure's beats; one that
///   expands to several figures is inserted as saved and the count is
///   dropped, because there is no single figure it could belong to.
///   A token that itself contains a count (`3 swings`) still matches in
///   full, first.
/// - a `;` line is split into clauses at bracket depth 0, and each clause is
///   matched on its own (with its own count). The clauses that are not
///   shorthands are parsed one at a time. Like the parser's own `;` compound
///   the line is all-or-nothing: if any non-shorthand clause cannot be
///   structured, the whole line falls through to the ordinary path below
///   (usually one custom). A `;` line with no shorthand clause is untouched.
///
/// On a miss everywhere (or when no store is given) the line falls through to
/// the normal #419 parser path below.
///
/// This is the local-typed counterpart to the import adapters: it reuses the
/// SAME hardened, bounded, never-throw core parser (fanning out across the
/// source front-ends via [parseFigureLinesFanOut]) rather than any
/// "trusted-local" fast-path, so a typed line behaves identically to the same
/// line arriving from an import — `;`-compounds split all-or-nothing (in the
/// CallersBox/TCB attempt) and a top-level `||` builds a meanwhile container
/// when it is well-formed (a malformed one stays whole-custom).
///
/// On top of that grammar, which follows how source sites write calls, free
/// text reads what a caller types (#1826, `typed_figure_names.dart`): spoken
/// turn amounts (`once and a half`) are rewritten to numerals before the
/// parse, and a line no parse reads is looked up as a move's name
/// (`hey`, `mad robin.`, `give & take`, an alias, the [dialect]'s own name),
/// alone or after a dancer (`neighbor pass by`, `ones arch and dive`; #1857).
/// That lookup is not a fast path: it runs after the parser, under the same
/// length bound, and its figure is validated against the taxonomy. Imports
/// and the re-parse upgrade use neither.
///
/// When a [dialect] is supplied, the line is parsed RAW first and the
/// dialect-canonicalised line is tried only if the raw parse is all-custom: the
/// user's role words (`Follows chain` under [Dialect.leadsFollows]) are not in
/// the always-on legacy synonym set the parser's scrub applies, so they miss
/// raw but parse once [canonicalizeText] maps them back to `role1`/`role2`.
/// Raw goes first because a dialect term can also be a MOVE word — `lead` in
/// `ones lead down the hall`. The canonicaliser keeps such a verb when its
/// neighbours show it is one (`RoleCanonicalizer`), but a line that parses as
/// typed should never depend on that judgement. When the retry
/// also misses, the built-in discouraged role terms are read by their meaning
/// (`ravens chain` → a `role2s` chain), as user-glossary text is read
/// ([canonicalizeGlossaryText]), so a role word the [dialect] claims keeps the
/// dialect's meaning; this retry runs with no [dialect] too. When every retry
/// misses, the raw result is returned, so the custom is not
/// dialect-canonicalised here. It is not verbatim either: the parser's import
/// scrub (`scrubFigureText`) has already run over it, and the editor
/// canonicalises custom text against the active dialect when the dance is
/// saved. With no [dialect], the dialect retry is skipped; the other steps
/// still run.
///
/// Before parsing, an optional inline beat count is peeled off the line and
/// passed as the `beats` argument:
/// - a **leading** `16 …`, `(16) …` or `[16] …` (a bare integer + space, or a
///   bracketed one, with or without a space), or
/// - a **trailing** `… (16)` or `… [16]` (a bracketed integer at the end),
///
/// any of them with a `beats` unit (`16 beats …`, `… (16 beats)`), which also
/// makes a bare trailing count a count (`… 16 beats`). A count in `bars` is
/// not read: beats per bar is the dance's phrase structure, which a line does
/// not see, so it stays in the text.
///
/// Only ONE inline form is honoured per line (per `;` clause, see below): a
/// trailing count is checked first and wins. A count that is not the one
/// honoured (the leading digits of `16 … (8)`, a second bracketed group) is
/// never dropped: it stays in the text, which then no longer parses and is kept
/// as a custom. A zero count is not a count (0 is "unspecified"); it is left
/// where it is.
///
/// A count of five or more digits (`circle left 10000 beats`, `(10000) circle
/// left`) cannot be beats, and is not an error either (#1863). When the line
/// states no count that can be, it is taken off the line, the rest is read as
/// usual, and the figure keeps its default beats, as one entered through the
/// figure picker does. The number is kept as a note on the figure it was typed
/// with (`10000 beats`), so it is not dropped. If the rest is not read in full,
/// the whole line is kept as a custom with its text as typed. A count of up to
/// four digits is left to the beats range (0..64) as before.
///
/// In a `;` line each clause may state its own count, and keeps it
/// ([_parseCountedClauses], #1870): `circle left (8); turn alone` and
/// `circle left; turn alone (4)`. A count that cannot be placed on a figure
/// keeps the line whole as a custom.
///
/// A line that ends up custom keeps its typed text, counts included, rather
/// than the remainder after a count was peeled; the peeled count still rides
/// on the custom as its beats.
///
/// When the line states no inline count the beats argument is left at 0, which
/// [parseFigureLine] treats as "unspecified": a matched structured figure then
/// derives its move/param default beats on read via [Taxonomy.effectiveParams]
/// (never forced to a literal 0), and an unrecognised line stays a beats-absent
/// custom. The app's editors read a draft's beats straight from its params, so
/// they fill that derived count in when they insert the figures
/// (`FigureDraft.fromFreeTextFigure`).
///
/// Returns an empty list when the line is empty after trimming/scrubbing
/// (nothing to insert) or when it exceeds [maxFreeTextEntryLength] (treated as
/// malformed/hostile input). Matched lines yield structured taxonomy figures;
/// unrecognised lines yield [customMove] figures tagged
/// [CustomOrigin.importGap] so they surface the #398 parser-gap marker. They
/// remain eligible for the reparse-customs upgrade, except a line kept whole
/// for a stray count, which [splitForReparse] keeps custom.
List<Figure> parseFreeTextFigureEntry(
  String input, {
  Taxonomy? taxonomy,
  ShorthandMappings? shorthands,
  Dialect? dialect,
}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.length > maxFreeTextEntryLength) {
    return const [];
  }
  // Shorthand resolution runs FIRST (issue #420): a whole-line exact-token hit
  // expands to the mapped figure(s) and short-circuits the parser. Failing
  // that, a counted or `;`-separated shorthand expands (#1827). Otherwise (or
  // with no store) the line goes to the normal #419 recognition below.
  if (shorthands != null) {
    final expanded = shorthands.resolve(trimmed);
    if (expanded != null) return expanded;
    final withShorthands = _expandShorthandClauses(
      trimmed,
      shorthands,
      taxonomy,
      dialect,
    );
    if (withShorthands != null) return withShorthands;
  }
  return _parseLine(trimmed, taxonomy, dialect);
}

/// Whether typing [token] as a free-text line already inserts a figure: the
/// parser structures it to one or more non-custom figures (issue #1827). A
/// shorthand with such a token would replace that reading, because shorthands
/// are matched before the parser, so the editors warn before it is saved.
/// [dialect] is the active one, so a token written in the user's own role words
/// is judged as it would be typed.
bool shorthandTokenShadowsFigure(
  String token, {
  Taxonomy? taxonomy,
  Dialect? dialect,
}) {
  final figures = parseFreeTextFigureEntry(
    token,
    taxonomy: taxonomy,
    dialect: dialect,
  );
  return figures.isNotEmpty && figures.every((f) => !f.isCustom);
}

/// Most `;` clauses a line is split into to look for shorthands. Matches
/// [maxShorthandTargetFigures], the most figures one shorthand may insert, so a
/// hostile line of a thousand `;` cannot drive a thousand parses.
const int _maxShorthandClauses = maxShorthandTargetFigures;

/// Resolves [line] against [shorthands] after the whole-line match missed: a
/// counted shorthand (`16 pbs`, `pbs (16)`) and/or a `;` line some of whose
/// clauses are shorthands. Returns `null` when no clause is a shorthand, or the
/// line cannot be expanded all-or-nothing, so the caller parses it as before.
List<Figure>? _expandShorthandClauses(
  String line,
  ShorthandMappings shorthands,
  Taxonomy? taxonomy,
  Dialect? dialect,
) {
  final clauses = splitShorthandClauses(line);
  if (clauses == null) return null;
  final expansions = <List<Figure>?>[];
  var anyShorthand = false;
  for (final clause in clauses) {
    final expansion = _resolveClause(clause, shorthands);
    anyShorthand = anyShorthand || expansion != null;
    expansions.add(expansion);
  }
  if (!anyShorthand) return null;
  final result = <Figure>[];
  for (var i = 0; i < clauses.length; i++) {
    final expansion = expansions[i];
    if (expansion != null) {
      result.addAll(expansion);
      continue;
    }
    final parsed = _parseLine(clauses[i], taxonomy, dialect);
    if (parsed.isEmpty || parsed.any((f) => f.isCustom)) return null;
    result.addAll(parsed);
  }
  return result;
}

/// The figures a single [clause] expands to as a shorthand, with an inline
/// count applied when the shorthand is one figure, or `null` if it is not one.
List<Figure>? _resolveClause(String clause, ShorthandMappings shorthands) {
  final whole = shorthands.resolve(clause);
  if (whole != null) return whole;
  final split = _splitInlineBeats(clause);
  if (split.beats == 0) return null;
  final expanded = shorthands.resolve(split.text);
  if (expanded == null) return null;
  if (expanded.length != 1) return expanded;
  final only = expanded.single;
  return [
    only.copyWith(params: {...only.params, 'beats': split.beats}),
  ];
}

/// [line] split into its `;` clauses, trimmed, for a caller that matches a
/// shorthand of its own kind per clause (a compound, or one of the user's own
/// figures, #1866). The same split a plain shorthand gets
/// ([_expandShorthandClauses]), so the kinds agree on where a clause ends.
/// `null` when the line cannot be expanded clause by clause: it has an empty
/// clause (`pbs;;swing`) or more than [maxShorthandTargetFigures] clauses. A
/// line with no `;` is one clause.
List<String>? splitShorthandClauses(String line) {
  final clauses = _splitClauses(line);
  if (clauses.length > _maxShorthandClauses || clauses.any((c) => c.isEmpty)) {
    return null;
  }
  return clauses;
}

/// [line] with a leading `16 pbs` or trailing `pbs (16)` beat count peeled
/// off, or `null` when it states none (issue #1861). The same split a plain
/// shorthand gets above, for the callers that match a shorthand of their own
/// kind (a compound, or one of the user's own figures) and so cannot go
/// through [parseFreeTextFigureEntry]: the caller matches `text` against its
/// tokens and decides what `beats` means for what it inserts.
({String text, int beats})? splitShorthandCount(String line) {
  final split = _splitInlineBeats(line.trim());
  if (split.beats == 0) return null;
  return (text: split.text, beats: split.beats);
}

/// Splits [line] at bracket-depth-0 `;`, trimming each clause and keeping empty
/// ones so the caller can decline a degenerate run (`pbs;;swing`). Brackets are
/// opaque, as in the parser's own `;` split, so a `(PR;WL)` pass list is not
/// cut.
List<String> _splitClauses(String line) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == 0x28 || c == 0x5B) {
      depth++;
    } else if (c == 0x29 || c == 0x5D) {
      if (depth > 0) depth--;
    } else if (depth == 0 && c == 0x3B) {
      out.add(line.substring(start, i).trim());
      start = i + 1;
    }
  }
  out.add(line.substring(start).trim());
  return out;
}

/// The ordinary (non-shorthand) path for one trimmed [trimmed] line: peel an
/// inline count, fan out across the front-ends, and retry dialect-canonicalised.
List<Figure> _parseLine(String trimmed, Taxonomy? taxonomy, Dialect? dialect) {
  final split = _splitInlineBeats(trimmed);
  final counted = _parseCountedClauses(trimmed, taxonomy, dialect);
  if (counted != null) {
    // A clause that does not structure keeps the line whole, as for any other
    // `;` line, with its text as typed and the line's own edge count (if any)
    // as its beats.
    return counted.isEmpty ? [_typedCustom(trimmed, split.beats)] : counted;
  }
  // A stray count keeps the line out of the parser, which would drop the
  // number: it is kept whole as a custom.
  final result = split.hasStrayCount
      ? [_typedCustom(trimmed, split.beats)]
      : _parseSplit(split, taxonomy: taxonomy, dialect: dialect);
  // A count that cannot be beats leaves the figure its default beats and rides
  // on it as a note; a line the parser did not read in full keeps the number in
  // its typed text instead (#1863).
  final unread = split.unread;
  if (unread != null) {
    final read =
        !split.hasStrayCount &&
        result.isNotEmpty &&
        !result.any((f) => f.isCustom);
    return read
        ? [_withUnreadCount(result.first, unread), ...result.skip(1)]
        : [_typedCustom(trimmed, 0)];
  }
  // A line that stayed custom keeps the text as typed: the count peeled above
  // would have left the custom with only its remainder.
  if (split.beats > 0 && result.length == 1 && result.single.isCustom) {
    return [_typedCustom(trimmed, split.beats)];
  }
  return result;
}

/// A `;` line in which some clause states a count, read so each count stays on
/// the clause it was typed with (#1870). Peeled off the whole line, a count at
/// the far end would ride on the FIRST clause (the parser puts a line's total
/// on its first figure), and one inside the line would be dropped.
///
/// The clauses are read together, count-free, because the parser reads a clause
/// in the context of its neighbours (`face up` after a move is that move's
/// note, not a figure). The first clause's count is the line's, as ever; a
/// count on a later clause is put on that clause's figure, which is only known
/// when every clause made exactly one figure, in order. Anything else (a clause
/// that became a note or was folded into a neighbour) cannot say which figure
/// the count belongs to, so the line is kept whole rather than guess.
///
/// Returns `null` when the line is not such a line (no `;`, a `||`, an empty
/// clause, or no clause with a count), so it is read whole as before; the
/// empty list when the counts cannot be kept, so the caller keeps the line as
/// one custom with its text as typed.
List<Figure>? _parseCountedClauses(
  String line,
  Taxonomy? taxonomy,
  Dialect? dialect,
) {
  if (hasTopLevelSeparator(line, '||')) return null;
  final clauses = splitShorthandClauses(line);
  if (clauses == null || clauses.length < 2) return null;
  final splits = [for (final c in clauses) _splitInlineBeats(c)];
  if (!splits.any((s) => s.beats > 0 || s.unread != null || s.hasStrayCount)) {
    return null;
  }
  if (splits.any((s) => s.hasStrayCount)) return const [];
  final first = splits.first;
  final figures = _parseSplit(
    _BeatSplit(splits.map((s) => s.text).join('; '), first.beats, first.forms),
    taxonomy: taxonomy,
    dialect: dialect,
  );
  if (figures.isEmpty || figures.any((f) => f.isCustom)) return const [];
  final later = splits.skip(1);
  if (later.every((s) => s.beats == 0 && s.unread == null)) {
    final unread = first.unread;
    return unread == null
        ? figures
        : [_withUnreadCount(figures.first, unread), ...figures.skip(1)];
  }
  if (figures.length != clauses.length) return const [];
  final counted = [
    for (var i = 0; i < figures.length; i++)
      _placeClauseCount(figures[i], splits[i], first: i == 0),
  ];
  // The first clause's count went through the parser, which refuses a value
  // the taxonomy does not allow (more than 64 beats); a later clause's was set
  // here, so it is held to the same rule.
  final tax = taxonomy ?? contraTaxonomy;
  final invalid = counted.any(
    (f) => tax
        .validateFigure(f)
        .any((i) => i.severity == ValidationSeverity.error),
  );
  return invalid ? const [] : counted;
}

/// [figure], the one made from the clause [split] was read from, with that
/// clause's own count on it. The first clause's beats went through the parser.
Figure _placeClauseCount(
  Figure figure,
  _BeatSplit split, {
  required bool first,
}) {
  final beats = first ? 0 : split.beats;
  final counted = beats > 0
      ? figure.copyWith(params: {...figure.params, 'beats': beats})
      : figure;
  final unread = split.unread;
  return unread == null ? counted : _withUnreadCount(counted, unread);
}

/// What to re-parse for a saved import-gap custom with [text] and [beats]
/// (`reparseImportGapFigures`), or `null` when the line must stay custom.
///
/// A free-text custom keeps its count in its text and in its beats; peeling the
/// count the beats already state lets the line upgrade once the parser learns
/// it. A stray count (see [_BeatSplit.hasStrayCount]) keeps the line custom,
/// since the recogniser would drop the number.
///
/// Only the unit-less counts are read here (`_reparseCounts`): this also runs
/// over customs that came from imports, so a `beats` unit (#1826) is left to
/// the parser, as it was before. One exception: a line that free-text entry
/// would itself keep custom for a stray count, honouring the stored [beats]
/// (`circle left 8 beats (16)`, `circle left 8 beats (16 beats)`), stays
/// custom here too, rather than upgrading with two counts. Free-text and
/// import customs share [CustomOrigin.importGap], so this applies to both.
({String text, int beats})? splitForReparse(String text, int beats) {
  final typed = _splitInlineBeats(text);
  if (beats > 0 && typed.beats == beats && typed.hasStrayCount) return null;
  final split = _splitInlineBeats(text, _reparseCounts);
  final peel = split.beats > 0 && split.beats == beats;
  final line = peel ? split : _BeatSplit(text, 0, _reparseCounts);
  if (line.hasStrayCount) return null;
  return (text: line.text, beats: beats);
}

Figure _typedCustom(String trimmed, int beats) => customFigure(
  scrubFigureText(trimmed),
  beats: beats,
  origin: CustomOrigin.importGap,
);

List<Figure> _parseSplit(
  _BeatSplit split, {
  Taxonomy? taxonomy,
  Dialect? dialect,
}) {
  // Fan OUT across the three source front-ends in precedence order
  // (ContraDB > CallersBox/TCB > CallersCompanion) and take the highest-
  // precedence attempt that structures the whole line to non-custom figure(s);
  // on a full miss the line stays an import-gap custom (byte-identical to the
  // pre-fan-out CallersBox fallback). Only the TCB attempt `;`-splits, so a
  // `;`-compound still resolves through it, and it also builds a top-level
  // `||` into a meanwhile.
  List<Figure> attempt(String text) => parseFigureLinesFanOut(
    text,
    beats: split.beats,
    taxonomy: taxonomy,
    demoteNoteTails: true,
  );
  bool missed(List<Figure> fs) => fs.every((f) => f.isCustom);
  // Spoken turn amounts first (`once and a half` → `1 1/2`): the grammar would
  // read `once` and keep `and a half` as a note, so this cannot wait for a
  // miss. Only a reading that accounts for the whole line is taken, so the
  // rewrite never changes a line the grammar already read, or the user's
  // words in a note.
  final rewritten = rewriteTypedSpellings(split.text);
  if (!identical(rewritten, split.text)) {
    final read = attempt(rewritten);
    if (!missed(read) && !_anyNote(read)) return read;
  }
  final raw = attempt(split.text);
  if (raw.isEmpty || !missed(raw)) return raw;
  // Retries, each only on a miss: the dialect's role words, then the built-in
  // discouraged role terms by their meaning (`ravens` → `role2s`), read as
  // user-glossary text is (`canonicalizeGlossaryText`), so a role word the
  // dialect claims keeps the dialect's meaning.
  final tried = {split.text};
  final readTexts = <String>[];
  for (final retry in [
    if (dialect != null) canonicalizeText(split.text, dialect),
    canonicalizeGlossaryText(split.text, dialect ?? Dialect.canonical),
  ]) {
    if (!tried.add(retry)) continue;
    readTexts.add(retry);
    final retried = attempt(retry);
    if (!missed(retried)) return retried;
  }
  // Last, the line as a move's name (`hey.`, `mad robin`), alone or after a
  // dancer (`neighbor pass by`): only when no parse read it, so a line the
  // grammar reads keeps every fact it states. A role word in the dancer's place
  // (`ravens mad robin`) is read by the retries' meaning of it, as it is above.
  final names = taxonomy ?? contraTaxonomy;
  final named =
      figureFromTypedName(
        split.text,
        beats: split.beats,
        taxonomy: names,
        dialect: dialect,
      ) ??
      readTexts
          .map(
            (text) => figureFromTypedDancerName(
              text,
              beats: split.beats,
              taxonomy: names,
              dialect: dialect,
            ),
          )
          .nonNulls
          .firstOrNull;
  return named == null ? raw : [named];
}

/// Whether any of [figures], or any figure inside one, carries a note.
bool _anyNote(Iterable<Figure> figures) => figures.any(
  (f) => f.note != null || (f.isContainer && _anyNote(f.subFigures)),
);
