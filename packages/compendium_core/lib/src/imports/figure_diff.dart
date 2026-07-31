import 'package:collection/collection.dart';

import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/figure.dart';
import '../model/phrase_structure.dart';
import '../taxonomy/taxonomy.dart';

/// Maximum number of figures honoured on **either side** of [diffFigures]
/// before it declines the full O(n·m) LCS pass (issue #686, OWASP-adjacent
/// robustness).
///
/// Unlike the CC `.FMP` reader's `kMaxCcFiguresPerDance`-style parse limits,
/// there is currently **no global cap** anywhere in the domain model on
/// `Dance.figures.length` — a dance built from a generic/JSON/archive import,
/// or a hostile/huge one, can carry an unbounded figure list. The diff's LCS
/// dynamic-programming table is `O(n*m)` in time *and* memory, so without its
/// own bound a sufficiently large pair of figure lists could exhaust memory or
/// stall the caller (a denial-of-service surface on untrusted import content).
/// Above this size, [diffFigures] skips the quadratic pass entirely and
/// reports "differs, too large to diff in full" via [FigureDiffResult.truncated]
/// instead of computing it. 512 mirrors the order of magnitude of the app's
/// existing per-dance figure caps without coupling to any one of them.
const int kMaxFiguresForDiff = 512;

/// Maximum number of rendered diff entries [diffFigures] returns.
///
/// This is a separate, smaller bound than [kMaxFiguresForDiff]: it caps the
/// **rendered output** of a diff that WAS computed, so a "Variation?" prompt
/// (or any other UI) never has to lay out an unbounded number of diff lines.
/// [FigureDiffResult.truncated] / [FigureDiffResult.omittedCount] tell the
/// caller how much was left out so it can say "N more differences not shown".
const int kMaxFigureDiffLines = 200;

/// Derives the **canonical figure key** used by [diffFigures] (and by any
/// caller that just wants a cheap identical/differ check) to decide whether
/// two figures represent the same choreography (issue #686, owner-locked
/// design).
///
/// `key = moveId '(' sorted "name=value" of every DECLARED taxonomy param,
/// via [Taxonomy.effectiveParams] (so a stated value and a defaulted value
/// collapse identically), MINUS `beats` ')'`. [Figure.progression] is a
/// top-level [Figure] field (not a taxonomy param), so it never enters the
/// key by construction — no special-case removal needed. A `meanwhile`
/// (#590) container folds all of its concurrent sides' keys into one
/// composite key, in side order (the container is always a single flat-list
/// element — see [Figure.isMeanwhile] — so this yields exactly one key per
/// list position, matching [diffFigures]' one-key-per-figure sequence
/// model). A custom/free-text figure ([Figure.isCustom]) has no taxonomy
/// identity, so it keys on its own line text (`params['text']`), trimmed and
/// with internal whitespace collapsed — there is no structure to hide
/// dialect noise behind, so the text itself (once trivial formatting noise is
/// removed) IS the identity. `params['text']` is untrusted import content, so
/// a malformed/non-`String` value is treated as empty rather than thrown —
/// this must never crash the comparison.
///
/// **Deliberately excluded from the key** (owner-locked, #686): `beats`,
/// [Figure.progression], [Figure.note], [Figure.walkthroughOverride],
/// [Figure.customOrigin], [Figure.assumedSubject], and — by construction,
/// since the key is built from structured params rather than rendered text —
/// all dialect/rendered wording. This means two figures differing ONLY in
/// beat count or progression-point placement compare as the SAME choreography
/// ("a 6-beat circle + 10-beat swing" and an "8 + 8" split describe the same
/// dance, not a different one — notation/bookkeeping, not choreography). This
/// is an intentional, owner-approved consequence: it is what keeps timing- or
/// progression-only edits from ever surfacing #686's "Variation?" prompt.
///
/// This is a **different, narrower-scoped-on-params-but-broader-on-set**
/// key than `figureSnippetSignature` (#411's walkthrough-snippet-library key):
/// that key only includes the move's *display-salient* params (those actually
/// referenced by its render template) and is `null` for custom/unknown moves,
/// because it exists to key a shared, human-facing snippet library. This key
/// includes **every declared param** (so a param that only affects
/// choreography but never renders in words still counts as a real
/// difference) and is never `null` — every figure, known move or not, needs a
/// comparable identity for a line-level diff. An unknown move (not in
/// [taxonomy], e.g. authored in a newer app version) is still keyed: falls
/// back to its raw [Figure.move] id plus its own declared params (minus
/// `beats`), care of [Taxonomy.effectiveParams]'s already-graceful
/// unknown-move handling (never throws, never returns null).
String figureCanonicalKey(Figure figure, Taxonomy taxonomy) {
  if (figure.isMeanwhile) {
    final sideKeys = figure.subFigures.map(
      (side) => figureCanonicalKey(side, taxonomy),
    );
    return 'meanwhile(${sideKeys.join('|')})';
  }
  if (figure.isCustom) {
    final rawText = figure.params['text'];
    final text = rawText is String ? rawText : '';
    return 'custom:${_collapseWhitespace(text)}';
  }
  final def = taxonomy.resolve(figure.move);
  final moveId = def?.id ?? figure.move;
  final effective = Map<String, Object?>.of(taxonomy.effectiveParams(figure))
    ..remove('beats');
  final keys = effective.keys.toList()..sort();
  final parts = <String>[];
  for (final name in keys) {
    final value = effective[name];
    if (value == null) continue;
    parts.add('$name=${_normalizeValue(value)}');
  }
  return parts.isEmpty ? moveId : '$moveId(${parts.join(',')})';
}

/// Canonicalizes a param value to a stable string token: bools render
/// `true`/`false`, integral numbers render without a trailing `.0`, other
/// numbers trim trailing zeros, and strings (already canonical taxonomy
/// tokens) are lowercased. Mirrors `snippet_signature.dart`'s private
/// normalizer (kept as an independent copy — a shared helper would couple two
/// deliberately-different keys together for a few lines of formatting).
String _normalizeValue(Object value) {
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is num) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    var s = value.toString();
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
  return value.toString().toLowerCase();
}

String _collapseWhitespace(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// One line of a computed [FigureDiffResult]: either an [added] or [removed]
/// figure line, with the display text a caller should show and (when
/// derivable) the phrase label it falls under.
enum FigureDiffKind {
  /// Present in the new figures, absent (at this position) from the old ones.
  added,

  /// Present in the old figures, absent (at this position) from the new ones.
  removed,
}

/// One rendered entry of a [FigureDiffResult].
class FigureDiffEntry {
  const FigureDiffEntry({
    required this.kind,
    required this.displayText,
    required this.phraseLabel,
  });

  final FigureDiffKind kind;

  /// Human-readable line text, rendered via the caller's [FigureRenderer] +
  /// [Dialect] — the comparison itself is canonicalization-aware, but the
  /// user still reads the line in their own phrasing.
  final String displayText;

  /// Phrase label (e.g. `A2`) the source figure falls under, derived from
  /// whichever side (old/new) this entry came from. Empty when the source
  /// figure list was empty (no phrase to derive from).
  final String phraseLabel;
}

/// Result of [diffFigures]: whether the two figure sequences are canonically
/// [identical], and (when not) the line-level diff [entries].
class FigureDiffResult {
  const FigureDiffResult({
    required this.identical,
    required this.entries,
    required this.truncated,
    required this.omittedCount,
  });

  /// Whether the two canonical-key sequences are exactly equal (order
  /// included). When `true`, [entries] is always empty (#685 territory: a
  /// true duplicate — no reason to compute or render a diff at all).
  final bool identical;

  /// Added/removed lines, capped at [kMaxFigureDiffLines].
  final List<FigureDiffEntry> entries;

  /// Whether [entries] was truncated relative to the full computed (or, for
  /// an over-[kMaxFiguresForDiff] input, the *would-be*) diff.
  final bool truncated;

  /// How many additional diff lines were left out of [entries]. When the
  /// input exceeded [kMaxFiguresForDiff] (so the full diff was never
  /// computed), this is a coarse upper bound (`oldFigures.length +
  /// newFigures.length`) rather than an exact count — still enough to tell a
  /// user "there's more here than we're showing".
  final int omittedCount;
}

const ListEquality<String> _stringListEquality = ListEquality<String>();

/// Cheap identical/differ check (issue #686): compares [oldFigures] and
/// [newFigures] via [figureCanonicalKey] alone — an `O(n)` key computation
/// plus a list-equality check, with **no** `O(n·m)` LCS pass and no
/// rendering. Canonicalization-aware in exactly the same way [diffFigures]
/// is (dialect wording, `beats`, and progression never count as a
/// difference) since it uses the same per-figure key.
///
/// Non-interactive callers that only need to decide skip-vs-auto-import
/// (issue #686's program-import resolver) and never inspect
/// [FigureDiffResult.entries] should call this instead of [diffFigures] —
/// paying for a full diff (and the [FigureRenderer] calls it requires) that
/// is never rendered is wasted work, and on a large/hostile figure list it's
/// needless `O(n·m)` cost for an answer this function gives in `O(n)`.
bool figuresCanonicallyIdentical({
  required List<Figure> oldFigures,
  required List<Figure> newFigures,
  required Taxonomy taxonomy,
}) {
  final oldKeys = [for (final f in oldFigures) figureCanonicalKey(f, taxonomy)];
  final newKeys = [for (final f in newFigures) figureCanonicalKey(f, taxonomy)];
  return _stringListEquality.equals(oldKeys, newKeys);
}

/// Compares [oldFigures] (an existing dance's figures, under [oldStructure])
/// against [newFigures] (an incoming record's figures, under [newStructure])
/// using [figureCanonicalKey] as the per-figure identity, and produces a
/// [FigureDiffResult] describing HOW they differ (issue #686).
///
/// The comparison is **canonicalization-aware**: two figures that render
/// differently under different dialects, or differ only in `beats`/
/// progression/note/etc (see [figureCanonicalKey]), compare as the identical
/// figure — a reader on a different dialect never sees a phantom
/// "variation". [renderer] + [dialect] only control the *display* text of
/// [FigureDiffEntry.displayText]; they never affect [FigureDiffResult.identical]
/// or which lines are added/removed.
///
/// Bounded per the module doc of [kMaxFiguresForDiff] (comparison cost) and
/// [kMaxFigureDiffLines] (rendered output size) — a hostile/huge import can
/// never blow up this comparison or the prompt built from it.
///
/// A caller that only needs the identical/differ answer (never inspecting
/// [FigureDiffResult.entries]) should call [figuresCanonicallyIdentical]
/// instead — it never pays for the `O(n·m)` LCS pass or rendering below.
FigureDiffResult diffFigures({
  required List<Figure> oldFigures,
  required PhraseStructure oldStructure,
  required List<Figure> newFigures,
  required PhraseStructure newStructure,
  required Taxonomy taxonomy,
  required FigureRenderer renderer,
  required Dialect dialect,
}) {
  final oldKeys = [for (final f in oldFigures) figureCanonicalKey(f, taxonomy)];
  final newKeys = [for (final f in newFigures) figureCanonicalKey(f, taxonomy)];

  if (_stringListEquality.equals(oldKeys, newKeys)) {
    return const FigureDiffResult(
      identical: true,
      entries: [],
      truncated: false,
      omittedCount: 0,
    );
  }

  if (oldKeys.length > kMaxFiguresForDiff ||
      newKeys.length > kMaxFiguresForDiff) {
    // Bound the O(n·m) LCS cost (see [kMaxFiguresForDiff]): report "differs"
    // without ever computing the quadratic diff pass.
    return FigureDiffResult(
      identical: false,
      entries: const [],
      truncated: true,
      omittedCount: oldKeys.length + newKeys.length,
    );
  }

  final oldSections = deriveSections(oldFigures, oldStructure);
  final newSections = deriveSections(newFigures, newStructure);

  final ops = _lcsDiffOps(oldKeys, newKeys);
  final allEntries = <FigureDiffEntry>[];
  for (final op in ops) {
    switch (op.kind) {
      case _OpKind.unchanged:
        break;
      case _OpKind.removed:
        allEntries.add(
          FigureDiffEntry(
            kind: FigureDiffKind.removed,
            displayText: renderer.render(oldFigures[op.oldIndex!], dialect),
            phraseLabel: oldSections[op.oldIndex!].label,
          ),
        );
      case _OpKind.added:
        allEntries.add(
          FigureDiffEntry(
            kind: FigureDiffKind.added,
            displayText: renderer.render(newFigures[op.newIndex!], dialect),
            phraseLabel: newSections[op.newIndex!].label,
          ),
        );
    }
  }

  final truncated = allEntries.length > kMaxFigureDiffLines;
  final entries = truncated
      ? allEntries.sublist(0, kMaxFigureDiffLines)
      : allEntries;
  return FigureDiffResult(
    identical: false,
    entries: entries,
    truncated: truncated,
    omittedCount: truncated ? allEntries.length - kMaxFigureDiffLines : 0,
  );
}

enum _OpKind { unchanged, removed, added }

class _DiffOp {
  const _DiffOp.unchanged(this.oldIndex, this.newIndex)
    : kind = _OpKind.unchanged;
  const _DiffOp.removed(this.oldIndex)
    : kind = _OpKind.removed,
      newIndex = null;
  const _DiffOp.added(this.newIndex) : kind = _OpKind.added, oldIndex = null;

  final _OpKind kind;
  final int? oldIndex;
  final int? newIndex;
}

/// Classic LCS-based line diff: an `O(n*m)` dynamic-programming pass over
/// [a]/[b] (bounded by [kMaxFiguresForDiff] before this is ever called),
/// producing an ordered list of unchanged/removed/added ops that reconstructs
/// both sequences when replayed.
List<_DiffOp> _lcsDiffOps(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  // dp[i][j] = length of the LCS of a[i:] and b[j:].
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final ops = <_DiffOp>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(_DiffOp.unchanged(i, j));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      ops.add(_DiffOp.removed(i));
      i++;
    } else {
      ops.add(_DiffOp.added(j));
      j++;
    }
  }
  while (i < n) {
    ops.add(_DiffOp.removed(i));
    i++;
  }
  while (j < m) {
    ops.add(_DiffOp.added(j));
    j++;
  }
  return ops;
}
