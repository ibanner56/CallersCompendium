/// Picks out the parts of a rendered figure line that a calling card sets
/// apart with the layout's `figures highlight` option: the move, the dancers
/// and the amounts, as Yona Appletree's Contra Card does. Display only: the
/// spans join back to exactly the line they came from.
library;

import 'package:compendium_core/compendium_core.dart';

/// What a stretch of a figure line is.
enum CallingCardSpanKind { plain, move, dancer, amount }

/// A stretch of a figure line and what it is.
typedef CallingCardSpan = ({String text, CallingCardSpanKind kind});

/// Whether a card highlights [figure]'s line at all: only when every word of
/// the line comes from the app's own wording. A line holding the user's own
/// text prints plain, since a word such as "lead" or "once" there is not
/// reliably a dancer or an amount. That is a figure written as free text (a
/// custom figure, which is also how the user's own figures are stored), one
/// with its wording overridden, and a container (meanwhile, modifier,
/// sequence) any of whose figures is either, or has a note, which its line
/// shows in parentheses.
bool callingCardHighlights(Figure figure) {
  if (figure.move == customMove) return false;
  if (figure.wordingOverride?.trim().isNotEmpty ?? false) return false;
  for (final inner in figure.subFigures) {
    if (inner.note?.trim().isNotEmpty ?? false) return false;
    if (!callingCardHighlights(inner)) return false;
  }
  return true;
}

/// The move names [figure]'s line may print under [dialect]: its own, or,
/// for a container (meanwhile, modifier, sequence), those of the figures
/// inside it, whose own lines make up its line. Free-text figures inside a
/// container name no move. Each comes as the dialect names the move, with
/// the figure's effective parameters (a `%S` substitution takes its default
/// side), and as free text's substitutions render that name (with
/// [canonicalizeDiscouragedTerms], a discouraged term's replacement), since
/// the line may hold either. A move whose line never prints its name (zig
/// zag, for one) is simply not found.
List<String> callingCardMoveNames(
  Figure figure,
  FigureRenderer renderer,
  Dialect dialect, {
  bool canonicalizeDiscouragedTerms = false,
}) {
  final own = figure.isContainer || !callingCardHighlights(figure)
      ? null
      : renderer.displayMoveName(
          figure.move,
          dialect,
          params: renderer.taxonomy.effectiveParams(figure),
        );
  return [
    if (own != null) ...[
      own,
      canonicalizeDiscouragedTerms
          ? renderer.renderFreeTextWithCanonicalDiscouragedTerms(own, dialect)
          : renderer.renderFreeText(own, dialect),
    ],
    for (final inner in figure.subFigures)
      ...callingCardMoveNames(
        inner,
        renderer,
        dialect,
        canonicalizeDiscouragedTerms: canonicalizeDiscouragedTerms,
      ),
  ];
}

/// Splits [line] into spans: each of [moves] and [dancers] found as whole
/// words, ignoring case, and the amounts (fractions such as `½` or `3/4`,
/// counts such as `3 places`, and words such as `once` or `clockwise`).
///
/// A move wins over a dancer word, and a dancer word over an amount, where
/// they would overlap, and a longer name over a shorter one. Text that is
/// none of these is [CallingCardSpanKind.plain]. The spans' texts join back
/// to [line] exactly.
List<CallingCardSpan> highlightFigureLine(
  String line, {
  required Iterable<String> moves,
  required Set<String> dancers,
}) {
  final kinds = List<CallingCardSpanKind?>.filled(line.length, null);

  // Matched on [line] itself, ignoring case, so no index depends on a
  // lower-cased copy keeping the line's length.
  void markAll(Iterable<String> names, CallingCardSpanKind kind) {
    final sorted = {
      for (final n in names)
        if (n.trim().isNotEmpty) n.trim().toLowerCase(),
    }.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final name in sorted) {
      final pattern = RegExp(
        RegExp.escape(name),
        caseSensitive: false,
        unicode: true,
      );
      for (final match in pattern.allMatches(line)) {
        final at = match.start;
        final end = match.end;
        if (!_boundary(line, at - 1) || !_boundary(line, end)) continue;
        if (kinds.sublist(at, end).any((k) => k != null)) continue;
        kinds.fillRange(at, end, kind);
      }
    }
  }

  markAll(moves, CallingCardSpanKind.move);
  markAll(dancers, CallingCardSpanKind.dancer);
  for (final match in _amount.allMatches(line)) {
    if (kinds.sublist(match.start, match.end).every((k) => k == null)) {
      kinds.fillRange(match.start, match.end, CallingCardSpanKind.amount);
    }
  }

  final spans = <CallingCardSpan>[];
  var start = 0;
  for (var i = 1; i <= line.length; i++) {
    if (i == line.length || kinds[i] != kinds[start]) {
      spans.add((
        text: line.substring(start, i),
        kind: kinds[start] ?? CallingCardSpanKind.plain,
      ));
      start = i;
    }
  }
  return spans;
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether the character at [index] of [text] does not continue a word
/// (outside the text counts as a boundary).
bool _boundary(String text, int index) =>
    index < 0 || index >= text.length || !_letterOrDigit.hasMatch(text[index]);

/// An amount in an English-rendered figure line. Longer phrases come first
/// in the alternation so `once and a half` is not cut short at `once`.
final _amount = RegExp(
  r'(?<![\p{L}\p{N}])(?:'
  r'once and a half|one and a half|three quarters?|halfway|'
  r'counter-?clockwise|clockwise|once|twice|'
  r'\d+(?:\.\d+)?\s*(?:places?|times?)|'
  r'\d+/\d+|'
  r'\d*[½¼¾⅓⅔⅛]'
  r')(?![\p{L}\p{N}])',
  caseSensitive: false,
  unicode: true,
);
