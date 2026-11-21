import 'package:compendium_app/src/widgets/container_title_length_limit.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ContainerTitleLengthLimit] keeps a group title's field to what the model
/// stores, measured as Save stores it.
void main() {
  final larksRobins = Dialect.larksRobins;
  final limit = ContainerTitleLengthLimit(
    measure: (text) => canonicalizeText(text.trim(), larksRobins).length,
  );

  TextEditingValue at(String text, int caret) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );

  /// The value a keystroke or paste of [inserted] at [caret] in [text] gives.
  (TextEditingValue, TextEditingValue) typed(
    String text,
    int caret,
    String inserted,
  ) => (
    at(text, caret),
    at(
      '${text.substring(0, caret)}$inserted${text.substring(caret)}',
      caret + inserted.length,
    ),
  );

  test('an edit that fits is taken as it is', () {
    final (old, next) = typed('Flutter', 7, 'wheel');
    expect(limit.formatEditUpdate(old, next), next);
  });

  test('typing into the middle of a full field changes nothing, rather than '
      'dropping the last character', () {
    final full = 'x' * kMaxContainerTitleLength;
    final (old, next) = typed(full, 0, 'A');
    final result = limit.formatEditUpdate(old, next);
    expect(result.text, full);
    expect(result.selection, const TextSelection.collapsed(offset: 0));
  });

  test('a paste past the limit keeps what fits of the paste, and the text '
      'after it', () {
    final text = '${'a' * 70}TAIL';
    final (old, next) = typed(text, 70, 'b' * 20);
    final result = limit.formatEditUpdate(old, next);
    expect(result.text, '${'a' * 70}${'b' * 6}TAIL');
    expect(result.text.length, kMaxContainerTitleLength);
    expect(result.selection, const TextSelection.collapsed(offset: 76));
  });

  test('counts UTF-16 units, never splitting a surrogate pair', () {
    final (old, next) = typed('', 0, '\u{1F483}' * 41);
    final result = limit.formatEditUpdate(old, next);
    expect(result.text, '\u{1F483}' * 40);
  });

  test('measures the title as Save stores it: role words grow when '
      'canonicalized', () {
    // "men" is stored as "role1s", three units longer.
    final (old, next) = typed('', 0, 'men ${'x' * 76}');
    expect(next.text.length, kMaxContainerTitleLength);
    final result = limit.formatEditUpdate(old, next);
    final stored = canonicalizeText(result.text.trim(), larksRobins);
    expect(stored.length, lessThanOrEqualTo(kMaxContainerTitleLength));
    // And so the model keeps all of it.
    expect(normalizeContainerTitle(stored), stored);
    expect(result.text, 'men ${'x' * 73}');
  });

  test('an edit that does not lengthen an over-long title is taken', () {
    final long = 'x' * (kMaxContainerTitleLength + 5);
    final shorter = TextEditingValue(
      text: long.substring(1),
      selection: const TextSelection.collapsed(offset: 0),
    );
    expect(limit.formatEditUpdate(at(long, 1), shorter), shorter);
  });

  test('leaves an edit alone while an input method is composing', () {
    final full = 'x' * kMaxContainerTitleLength;
    final composing = TextEditingValue(
      text: '$fullか',
      selection: const TextSelection.collapsed(
        offset: kMaxContainerTitleLength + 1,
      ),
      composing: const TextRange(
        start: kMaxContainerTitleLength,
        end: kMaxContainerTitleLength + 1,
      ),
    );
    expect(
      limit.formatEditUpdate(at(full, kMaxContainerTitleLength), composing),
      composing,
    );
  });

  test('a composition committed past the limit is held to it', () {
    // The field held 78 units; the input method composed four more.
    final committed = '${'x' * 78}かなかな';
    final composing = TextEditingValue(
      text: committed,
      selection: const TextSelection.collapsed(offset: 82),
      composing: const TextRange(start: 78, end: 82),
    );
    final commit = TextEditingValue(
      text: committed,
      selection: const TextSelection.collapsed(offset: 82),
    );
    final result = limit.formatEditUpdate(composing, commit);
    expect(result.text, '${'x' * 78}かな');
    expect(result.composing.isValid, isFalse);
  });

  test('a paste that starts with a surrogate pair keeps what fits', () {
    final (old, next) = typed('x' * 78, 78, '\u{1F483}abc');
    expect(limit.formatEditUpdate(old, next).text, '${'x' * 78}\u{1F483}');
  });
}
