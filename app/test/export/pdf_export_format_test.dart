import 'dart:typed_data';

import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/export/program_matrix_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/pdf_probe.dart';

/// OUT-4 / OUT-9: the PDFs follow the paper the print dialog chose, and every
/// page carries "Page x of y" and (after the first) a running title.
///
/// The builders take a plain Helvetica theme here so each page's text is a
/// literal `(…) Tj` string in a deflated content stream that [_pdfText] can
/// read back, with no font subsetting in the way.

final _now = DateTime.utc(2026, 7, 13);
final _theme = pw.ThemeData.base();

String _words(int n) => List.filled(n, 'swing').join(' ');

Dance _dance(String id, String title, {String callingNotes = ''}) => Dance(
  id: id,
  title: title,
  figures: [
    testFigure(move: 'swing'),
    testFigure(move: 'balance'),
  ],
  callingNotes: callingNotes,
  createdAt: _now,
  updatedAt: _now,
  formation: const Formation(FormationShape.dupleImproper),
);

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final longNotes = _words(2500);

  group('paper size follows the print dialog (OUT-4)', () {
    test('the dance PDF lays out Letter when asked, A4 by default', () async {
      final d = _dance('d1', 'Butterfly');
      Future<Uint8List> build([PdfPageFormat? format]) => buildDancePdf(
        d,
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
        theme: _theme,
        pageFormat: format ?? PdfPageFormat.a4,
      );
      expect(pdfMediaBox(await build(PdfPageFormat.letter)), (612, 792));
      expect(pdfMediaBox(await build()), (595, 842));
    });

    test('the set-list PDF lays out Letter when asked', () async {
      final bytes = await buildProgramPdf(
        Program(
          id: 'p1',
          title: 'Friday Contra',
          createdAt: _now,
          updatedAt: _now,
        ),
        titleFor: (_) => null,
        theme: _theme,
        pageFormat: PdfPageFormat.letter,
      );
      expect(pdfMediaBox(bytes), (612, 792));
    });

    test('the matrix PDF is the chosen paper turned landscape', () async {
      final matrix = buildProgramMatrix([_dance('d1', 'Butterfly')]);
      Future<Uint8List> build(PdfPageFormat format) async =>
          buildProgramMatrixPdf(
            matrix,
            taxonomy: contraTaxonomy,
            dialect: Dialect.canonical,
            programTitle: 'Friday Contra',
            theme: _theme,
            markerFont: await loadProgramMatrixMarkerFont(),
            pageFormat: format,
          );
      expect(pdfMediaBox(await build(PdfPageFormat.letter)), (792, 612));
      // A format the dialog already made landscape is not turned back.
      expect(pdfMediaBox(await build(PdfPageFormat.letter.landscape)), (
        792,
        612,
      ));
    });
  });

  group('page numbers and running title (OUT-9)', () {
    test('the dance PDF numbers every page and repeats the title', () async {
      final d = _dance('d1', 'Butterfly Whirl', callingNotes: longNotes);
      final calls = <(int, int)>[];
      final bytes = await buildDancePdf(
        d,
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
        theme: _theme,
        labels: DanceExportLabels(
          pageOf: (page, pages) {
            calls.add((page, pages));
            return 'Page $page of $pages';
          },
        ),
      );
      final pages = pdfPageCount(bytes);
      expect(pages, greaterThan(1), reason: 'fixture must span pages');
      final text = pdfText(bytes);
      for (var p = 1; p <= pages; p++) {
        expect(text, contains('Page $p of $pages'));
      }
      // Page 1 prints the title once as the heading; each later page adds the
      // running title.
      expect(_count(text, 'Butterfly Whirl'), pages);
    });

    test('the set-list PDF numbers every page and repeats the title', () async {
      final bytes = await buildProgramPdf(
        Program(
          id: 'p1',
          title: 'Friday Contra',
          notes: longNotes,
          createdAt: _now,
          updatedAt: _now,
        ),
        titleFor: (_) => null,
        theme: _theme,
      );
      final pages = pdfPageCount(bytes);
      expect(pages, greaterThan(1), reason: 'fixture must span pages');
      final text = pdfText(bytes);
      for (var p = 1; p <= pages; p++) {
        expect(text, contains('Page $p of $pages'));
      }
      expect(_count(text, 'Friday Contra'), pages);
    });

    test('a one-page PDF has no running title, only the footer', () async {
      final bytes = await buildDancePdf(
        _dance('d1', 'Butterfly Whirl'),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple improper',
        statusLabel: 'Active',
        theme: _theme,
      );
      final text = pdfText(bytes);
      expect(pdfPageCount(bytes), 1);
      expect(text, contains('Page 1 of 1'));
      expect(_count(text, 'Butterfly Whirl'), 1);
    });

    test('the matrix header row repeats on every page', () async {
      final dances = [
        for (var i = 0; i < 90; i++) _dance('d$i', 'Dance number $i'),
      ];
      final matrix = buildProgramMatrix(dances);
      final bytes = await buildProgramMatrixPdf(
        matrix,
        taxonomy: contraTaxonomy,
        dialect: Dialect.canonical,
        programTitle: 'Friday Contra',
        theme: _theme,
        markerFont: await loadProgramMatrixMarkerFont(),
        labels: const ProgramMatrixExportLabels(danceColumn: 'Danceheader'),
      );
      final pages = pdfPageCount(bytes);
      expect(pages, greaterThan(1), reason: 'fixture must span pages');
      final text = pdfText(bytes);
      expect(_count(text, 'Danceheader'), pages);
      expect(text, contains('Page $pages of $pages'));
      expect(_count(text, 'Friday Contra'), pages);
    });
  });
}
