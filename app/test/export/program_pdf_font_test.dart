import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/export/program_pdf.dart';

/// Returns the TrueType/OpenType table tags present in [bytes] by walking the
/// `sfnt` table directory (offset 12, `numTables` 16-byte entries, tag as the
/// first 4 bytes of each entry). Used to assert a bundled font is a static,
/// single-instance TTF (no `fvar` table) rather than an OpenType *variable*
/// font, which the `pdf` package cannot render correctly (issue #614: it
/// always renders the variable font's default master, ignoring the
/// requested weight/style).
Set<String> _sfntTableTags(ByteData bytes) {
  final numTables = bytes.getUint16(4);
  final tags = <String>{};
  for (var i = 0; i < numTables; i++) {
    final entryOffset = 12 + i * 16;
    final tag = String.fromCharCodes([
      bytes.getUint8(entryOffset),
      bytes.getUint8(entryOffset + 1),
      bytes.getUint8(entryOffset + 2),
      bytes.getUint8(entryOffset + 3),
    ]);
    tags.add(tag);
  }
  return tags;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF export font (#614)', () {
    const fontAssets = [
      'assets/fonts/Roboto-Regular.ttf',
      'assets/fonts/Roboto-Bold.ttf',
      'assets/fonts/Roboto-Italic.ttf',
    ];

    for (final asset in fontAssets) {
      test('$asset has no fvar (variable font) table', () async {
        final bytes = await rootBundle.load(asset);
        expect(
          _sfntTableTags(bytes),
          isNot(contains('fvar')),
          reason:
              '$asset must be a static, single-instance TTF — the pdf '
              'package cannot resolve variable-font axes and would always '
              'render the default master regardless of requested '
              'weight/style.',
        );
      });
    }

    test(
      'loadProgramPdfTheme registers distinct regular/bold/italic fonts',
      () async {
        final theme = await loadProgramPdfTheme();
        final style = theme.defaultTextStyle;

        expect(style.fontNormal, isNotNull);
        expect(style.fontBold, isNotNull);
        expect(style.fontItalic, isNotNull);

        // Regression guard: previously base and bold were the *same* Font
        // object (loaded once from the variable font), so requesting bold
        // text silently rendered as regular weight.
        expect(
          identical(style.fontNormal, style.fontBold),
          isFalse,
          reason:
              'bold text must use a distinct static Bold font, not reuse '
              'the regular face',
        );
        expect(
          identical(style.fontNormal, style.fontItalic),
          isFalse,
          reason:
              'italic text must use a distinct static Italic font, not '
              'reuse the regular face',
        );
      },
    );
  });
}
