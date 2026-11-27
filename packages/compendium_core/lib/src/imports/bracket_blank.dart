/// Blanking `(…)` and `[…]` annotations out of a figure line in time linear in
/// the line (pre-release audit SEC-04).
library;

/// [text] with each `(…)` and then each `[…]` replaced by a space: the same
/// result as `text.replaceAll(RegExp(r'\([^)]*\)'), ' ')` followed by
/// `.replaceAll(RegExp(r'\[[^\]]*\]'), ' ')`.
///
/// Those regular expressions take time that grows with the square of a run of
/// opening brackets with no closing one (`((((…`): from each opening bracket
/// they scan to the end of the line before failing. This scans the line once
/// per bracket kind instead.
String blankBracketedAnnotations(String text) =>
    _blankDelimited(_blankDelimited(text, '(', ')'), '[', ']');

/// [text] with each [open]…[close] span blanked, leftmost first, as
/// `replaceAll` finds them: a span runs from an [open] to the first [close]
/// after it, whatever lies between (another [open] included). Once an [open]
/// has no [close] after it, no later one does either, so the scan stops.
String _blankDelimited(String text, String open, String close) {
  StringBuffer? out;
  var from = 0;
  while (true) {
    final start = text.indexOf(open, from);
    if (start < 0) break;
    final end = text.indexOf(close, start + 1);
    if (end < 0) break;
    (out ??= StringBuffer())
      ..write(text.substring(from, start))
      ..write(' ');
    from = end + 1;
  }
  if (out == null) return text;
  out.write(text.substring(from));
  return out.toString();
}
