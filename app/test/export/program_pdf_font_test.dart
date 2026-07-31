import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

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

        // Distinct Font *objects* alone wouldn't catch loading the same
        // Regular bytes into two separate Font instances, so also assert
        // the underlying asset bytes actually differ pairwise — this is
        // the real guard against the original "bold renders as regular"
        // failure mode.
        final regularBytes = await rootBundle.load(
          'assets/fonts/Roboto-Regular.ttf',
        );
        final boldBytes = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
        final italicBytes = await rootBundle.load(
          'assets/fonts/Roboto-Italic.ttf',
        );
        expect(
          regularBytes.buffer.asUint8List(),
          isNot(equals(boldBytes.buffer.asUint8List())),
          reason:
              'Roboto-Regular.ttf and Roboto-Bold.ttf must be different '
              'font files, not the same bytes registered twice',
        );
        expect(
          regularBytes.buffer.asUint8List(),
          isNot(equals(italicBytes.buffer.asUint8List())),
          reason:
              'Roboto-Regular.ttf and Roboto-Italic.ttf must be '
              'different font files, not the same bytes registered twice',
        );
        expect(
          boldBytes.buffer.asUint8List(),
          isNot(equals(italicBytes.buffer.asUint8List())),
          reason:
              'Roboto-Bold.ttf and Roboto-Italic.ttf must be different '
              'font files, not the same bytes registered twice',
        );
      },
    );
  });

  group('Program-matrix marker fallback font (#633)', () {
    const asset = 'assets/fonts/ProgramMatrixMarkers-Regular.ttf';

    test('$asset has no fvar (variable font) table', () async {
      final bytes = await rootBundle.load(asset);
      expect(
        _sfntTableTags(bytes),
        isNot(contains('fvar')),
        reason:
            '$asset must be a static, single-instance TTF, consistent with '
            "#614's static-font decision for the other bundled PDF fonts — "
            'the pdf package cannot resolve variable-font axes.',
      );
    });

    test('$asset covers the ★ ▸ ✓ marker glyphs Roboto lacks', () async {
      final bytes = await rootBundle.load(asset);
      // Mirrors the exact glyph-lookup the `pdf` package itself performs
      // (PdfTtfFont.isRuneSupported delegates to
      // TtfParser.charToGlyphIndexMap.containsKey) — see
      // `pdf/src/pdf/obj/ttffont.dart`.
      final glyphs = TtfParser(bytes).charToGlyphIndexMap;
      for (final MapEntry(key: name, value: codePoint) in const {
        'star (★, U+2605)': 0x2605,
        'triangle (▸, U+25B8)': 0x25B8,
        'check (✓, U+2713)': 0x2713,
      }.entries) {
        expect(
          glyphs.containsKey(codePoint),
          isTrue,
          reason: '$asset must map $name to a real glyph',
        );
      }

      // Regression guard: the *bundled Roboto* still must NOT cover these
      // — if a future Roboto update ever added them, the fallback font
      // (and this test) would be safe to drop, but until then the
      // fallback is load-bearing.
      final robotoBytes = await rootBundle.load(
        'assets/fonts/Roboto-Regular.ttf',
      );
      final robotoGlyphs = TtfParser(robotoBytes).charToGlyphIndexMap;
      expect(
        robotoGlyphs.containsKey(0x2605),
        isFalse,
        reason:
            'this test documents *why* the fallback font exists; if '
            'Roboto gains a ★ glyph, program_matrix_pdf.dart no longer '
            'strictly needs the fallback for it',
      );
    });

    test(
      'loadProgramMatrixMarkerFont loads a font supporting all 3 marks',
      () async {
        final font = await loadProgramMatrixMarkerFont();
        expect(font, isA<pw.Font>());

        final bytes = await rootBundle.load(asset);
        final glyphs = TtfParser(bytes).charToGlyphIndexMap;
        expect(glyphs.containsKey(0x2605), isTrue);
        expect(glyphs.containsKey(0x25B8), isTrue);
        expect(glyphs.containsKey(0x2713), isTrue);
      },
    );
  });
}
