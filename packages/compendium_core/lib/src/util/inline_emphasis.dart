/// Lightweight, ReDoS-safe inline emphasis markup for user-authored figure
/// text (`Figure.note` and custom-figure text). Pure Dart — NO Flutter imports —
/// so the Flutter-free `compendium_core` invariant holds and the rendering of
/// [EmphasisSpan]s into `RichText`/`TextSpan` lives in the app layer.
///
/// ## Syntax
/// - `*text*`  → bold
/// - `_text_`  → underline
/// - `\`       → escapes the next character (so `\*` is a literal `*`, `\\` a
///   literal backslash). A trailing backslash is a literal backslash.
///
/// Bold and underline may nest (`*_x_*` sets both flags on `x`).
///
/// ## Safety (untrusted input)
/// [Figure.note]/custom text can arrive from imported or shared programs
/// authored by third parties, so this parser is a trust boundary and is safe by
/// construction:
/// - **No regular expressions** — impossible to trigger catastrophic
///   backtracking / ReDoS.
/// - Single left-to-right O(n) pass; state is two booleans, so there is no
///   recursion and no super-linear work regardless of nesting or length.
/// - Never throws on any input (malformed, unterminated, adversarial, unicode).
/// - Can ONLY ever emit bold/underline flags over literal text runs — it cannot
///   produce HTML, links, arbitrary spans, or any other structure.
///
/// Malformed or unterminated markup degrades to the literal characters rather
/// than crashing or dropping text.
library;

/// A run of text sharing the same emphasis styling.
class EmphasisSpan {
  const EmphasisSpan({
    required this.text,
    this.bold = false,
    this.underline = false,
  });

  /// Literal display text (markup delimiters already removed).
  final String text;
  final bool bold;
  final bool underline;

  @override
  bool operator ==(Object other) =>
      other is EmphasisSpan &&
      other.text == text &&
      other.bold == bold &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(text, bold, underline);

  @override
  String toString() =>
      'EmphasisSpan(${_q(text)}, bold: $bold, underline: $underline)';

  static String _q(String s) => '"${s.replaceAll('\n', r'\n')}"';
}

const int _star = 0x2a; // *
const int _underscore = 0x5f; // _
const int _backslash = 0x5c; // \

/// Parses [input] into a list of [EmphasisSpan]s.
///
/// A delimiter (`*` or `_`) only toggles its style when a matching closing
/// delimiter of the same kind appears later in the string; an unmatched
/// delimiter is emitted as a literal character. The returned list coalesces
/// adjacent runs that share styling and never contains empty spans (an empty
/// input yields an empty list).
List<EmphasisSpan> parseInlineEmphasis(String input) {
  if (input.isEmpty) return const <EmphasisSpan>[];

  final units = input.codeUnits;
  final n = units.length;

  // Precompute, for each `*`/`_`, whether it is "active" (part of a matched
  // open/close pair). Single forward pass tracking the last unmatched open
  // index per delimiter kind — O(n), no regex, no backtracking. Escaped
  // delimiters are skipped so they can never open or close a pair.
  final active = List<bool>.filled(n, false);
  var openStar = -1;
  var openUnderscore = -1;
  for (var i = 0; i < n; i++) {
    final c = units[i];
    if (c == _backslash) {
      i++; // skip the escaped character (if any)
      continue;
    }
    if (c == _star) {
      if (openStar >= 0) {
        active[openStar] = true;
        active[i] = true;
        openStar = -1;
      } else {
        openStar = i;
      }
    } else if (c == _underscore) {
      if (openUnderscore >= 0) {
        active[openUnderscore] = true;
        active[i] = true;
        openUnderscore = -1;
      } else {
        openUnderscore = i;
      }
    }
  }

  final spans = <EmphasisSpan>[];
  final buf = StringBuffer();
  var bold = false;
  var underline = false;

  void flush() {
    if (buf.isNotEmpty) {
      final text = buf.toString();
      if (spans.isNotEmpty &&
          spans.last.bold == bold &&
          spans.last.underline == underline) {
        final prev = spans.removeLast();
        spans.add(
          EmphasisSpan(
            text: prev.text + text,
            bold: bold,
            underline: underline,
          ),
        );
      } else {
        spans.add(EmphasisSpan(text: text, bold: bold, underline: underline));
      }
      buf.clear();
    }
  }

  for (var i = 0; i < n; i++) {
    final c = units[i];
    if (c == _backslash) {
      // Escape: emit the next char literally; a trailing backslash is literal.
      if (i + 1 < n) {
        buf.writeCharCode(units[i + 1]);
        i++;
      } else {
        buf.writeCharCode(_backslash);
      }
      continue;
    }
    if (c == _star && active[i]) {
      flush();
      bold = !bold;
      continue;
    }
    if (c == _underscore && active[i]) {
      flush();
      underline = !underline;
      continue;
    }
    buf.writeCharCode(c);
  }
  flush();

  return spans;
}

/// Returns [input] with all emphasis markup removed, yielding the plain text a
/// screen reader should announce. Equivalent to concatenating the [text] of
/// [parseInlineEmphasis]'s spans.
String stripInlineEmphasis(String input) {
  if (input.isEmpty) return '';
  final buf = StringBuffer();
  for (final span in parseInlineEmphasis(input)) {
    buf.write(span.text);
  }
  return buf.toString();
}
