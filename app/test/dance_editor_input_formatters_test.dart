// The editor's bounded fields: other titles and the Barnes reference stop at
// the bounds every saved dance holds, and typing at a full field never cuts
// text that was already there.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/dance_editor/dance_editor_form.dart';

TextEditingValue _at(String text, int offset) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset),
);

TextEditingValue _insert(TextEditingValue value, String inserted) {
  final at = value.selection.start;
  final text =
      value.text.substring(0, at) + inserted + value.text.substring(at);
  return _at(text, at + inserted.length);
}

void main() {
  group('Barnes reference', () {
    const formatter = CodeUnitLimitInputFormatter(kMaxBarnesReferenceLength);
    final full = '${'b' * (kMaxBarnesReferenceLength - 7)}BIII p.92'.substring(
      0,
      kMaxBarnesReferenceLength,
    );

    test('a keystroke before the end of a full field is refused, and the '
        'end of the reference is kept', () {
      final old = _at(full, 0);
      expect(formatter.formatEditUpdate(old, _insert(old, 'x')), old);
    });

    test('a paste at the cursor keeps what is there and cuts only the '
        'paste, on a character boundary', () {
      final old = _at('b' * (kMaxBarnesReferenceLength - 3), 0);
      final result = formatter.formatEditUpdate(
        old,
        _insert(old, 'a\u{1F3BB}\u{1F3BB}'),
      );
      expect(result.text, 'a\u{1F3BB}${'b' * (kMaxBarnesReferenceLength - 3)}');
      expect(result.selection, const TextSelection.collapsed(offset: 3));
    });
  });

  group('other titles', () {
    const formatter = AlternateTitlesInputFormatter();
    final twenty = [for (var i = 0; i < kMaxAlternateTitles; i++) 'T$i'];

    test('a line break typed among 20 titles is refused, and the last title '
        'is kept', () {
      final old = _at(twenty.join('\n'), 1);
      expect(formatter.formatEditUpdate(old, _insert(old, '\n')), old);
    });

    test('a keystroke early in a full-length title is refused, and the end '
        'of that title is kept', () {
      final old = _at('${'t' * (kMaxAlternateTitleLength - 1)}Z\nOther', 0);
      expect(formatter.formatEditUpdate(old, _insert(old, 'x')), old);
    });

    test('a paste into an empty field is cut line by line, so one long '
        'line does not lose the titles after it', () {
      final old = _at('', 0);
      final result = formatter.formatEditUpdate(
        old,
        _insert(old, '${'x' * (kMaxAlternateTitleLength + 4)}\nMonymusk'),
      );
      expect(result.text, '${'x' * kMaxAlternateTitleLength}\nMonymusk');
    });

    test('an edit that fits is left alone', () {
      final old = _at('Monymusk', 8);
      final next = _insert(old, '\nMoney Musk');
      expect(formatter.formatEditUpdate(old, next), next);
    });
  });
}
