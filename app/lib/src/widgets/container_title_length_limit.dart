import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/services.dart';

/// Keeps a group title's field within [kMaxContainerTitleLength] as the title
/// will be STORED, so Save never cuts what the field shows.
///
/// Two things make the stored form longer than what is typed, and a plain
/// `maxLength` sees neither:
/// - Save canonicalizes role words ("men" becomes "role1s"), so the length is
///   [measure]d after that rewrite; the dance editor passes the same
///   canonicalization it saves with.
/// - The model counts UTF-16 code units ([normalizeContainerTitle]), while
///   `maxLength` counts characters as a reader sees them, so 41 emoji pass a
///   limit of 80 there.
///
/// An edit that would go past the limit keeps as much of what it inserted as
/// fits, never inside a surrogate pair, and leaves the rest of the text and
/// the caret where the reader expects: typing into a full field changes
/// nothing, rather than dropping the title's last character. A plain edit
/// that does not lengthen the stored form is always accepted, so a title that
/// is already too long (from a dialect change) can still be shortened. While
/// an input method is composing, the edit is left alone; when the composition
/// is committed, the composed text is held to the limit like any insertion.
class ContainerTitleLengthLimit extends TextInputFormatter {
  const ContainerTitleLengthLimit({
    required this.measure,
    this.max = kMaxContainerTitleLength,
  });

  /// The stored length of a typed title.
  final int Function(String text) measure;

  /// The longest stored length allowed.
  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid) return newValue;
    final next = newValue.text;
    final measured = measure(next);
    if (measured <= max) return newValue;
    // Committing a composition leaves the text as it was, so it never
    // "lengthens" it: the composed span is checked as an insertion instead.
    final fromComposition = oldValue.composing.isValid;
    if (!fromComposition && measured <= measure(oldValue.text)) {
      return newValue;
    }

    final (start, stop) = _insertedSpan(oldValue, next);
    final before = next.substring(0, start);
    final after = next.substring(stop);
    final inserted = next.substring(start, stop);
    String withKept(int keep) => '$before${inserted.substring(0, keep)}$after';
    bool fits(int keep) => measure(withKept(keep)) <= max;

    // Every place the insertion may be cut, none inside a surrogate pair.
    final ends = [
      for (var keep = 0; keep <= inserted.length; keep++)
        if (keep == 0 ||
            keep == inserted.length ||
            _safeEnd(inserted, keep) == keep)
          keep,
    ];
    // The longest cut that fits, by binary search. `low` only moves to a cut
    // that fits, so only the empty cut can fail, which the walk below
    // handles. The measure is not monotone in the length kept (a word can
    // shrink once it stops being a role word), so the result always fits but
    // may not be the longest cut that does.
    var low = 0;
    var high = ends.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits(ends[mid])) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    var index = low;
    while (index >= 0 && !fits(ends[index])) {
      index--;
    }
    if (index < 0) {
      // Even without the insertion it is too long: refuse a plain edit; a
      // committed composition is dropped rather than kept past the limit.
      return fromComposition
          ? TextEditingValue(
              text: '$before$after',
              selection: TextSelection.collapsed(offset: start),
            )
          : oldValue;
    }
    final keep = ends[index];
    return TextEditingValue(
      text: withKept(keep),
      selection: TextSelection.collapsed(offset: start + keep),
    );
  }

  /// Where in [next] the edit from [oldValue] put its text: the composition
  /// it commits, when [oldValue] was composing and the text around it is
  /// unchanged, or else what lies between the text kept at the start and at
  /// the end.
  static (int, int) _insertedSpan(TextEditingValue oldValue, String next) {
    final old = oldValue.text;
    final composing = oldValue.composing;
    if (composing.isValid) {
      final start = composing.start;
      final stop = next.length - (old.length - composing.end);
      if (start <= stop &&
          next.startsWith(old.substring(0, start)) &&
          next.endsWith(old.substring(composing.end))) {
        return (start, stop);
      }
    }
    var start = 0;
    while (start < old.length &&
        start < next.length &&
        old.codeUnitAt(start) == next.codeUnitAt(start)) {
      start++;
    }
    var tail = 0;
    while (tail < old.length - start &&
        tail < next.length - start &&
        old.codeUnitAt(old.length - 1 - tail) ==
            next.codeUnitAt(next.length - 1 - tail)) {
      tail++;
    }
    return (start, next.length - tail);
  }

  /// [end], moved back one unit when it would split a surrogate pair.
  static int _safeEnd(String text, int end) {
    if (end <= 0 || end >= text.length) return end;
    final last = text.codeUnitAt(end - 1);
    return last >= 0xD800 && last <= 0xDBFF ? end - 1 : end;
  }
}
