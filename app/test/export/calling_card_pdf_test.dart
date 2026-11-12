import 'dart:convert';

import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:compendium_app/src/export/calling_card_pdf.dart';
import 'package:compendium_app/src/export/calling_card_sample.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/pdf_probe.dart';

/// The builder runs with the plain Helvetica theme so [pdfText] can read each
/// drawn word back (see `pdf_export_format_test.dart`).
final _theme = pw.ThemeData.base();
final _now = DateTime.utc(2026, 11, 6);

Dance _dance({
  String title = 'Ladder Contra',
  String callingNotes = 'Watch the ends',
  String walkthrough = '',
  List<Figure>? figures,
}) => Dance(
  id: title,
  title: title,
  callingNotes: callingNotes,
  walkthrough: walkthrough,
  figures:
      figures ??
      [
        Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 16}),
        Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
      ],
  formation: const Formation(FormationShape.dupleImproper),
  createdAt: _now,
  updatedAt: _now,
);

CallingCardEntry _entry(Dance d, {String number = ''}) => CallingCardEntry(
  dance: d,
  number: number,
  labels: (
    authorNames: const ['Pat Author'],
    formationLabel: 'Improper',
    levelLabel: 'Easy',
    statusLabel: 'Active',
    sourceLines: const [],
  ),
);

Future<String> _text(
  List<CallingCardEntry> entries, {
  String layout = kDefaultCallingCardLayout,
  CallingCardSize size = kDefaultCallingCardSize,
  Set<DanceShareField> fields = DanceShareField.allExceptTunes,
  String programTitle = '',
  CallingCardFitReport? report,
}) async => pdfText(
  await buildCallingCardsPdf(
    entries,
    layout: CallingCardLayout.parse(layout),
    size: size,
    dialect: Dialect.canonical,
    fields: fields,
    programTitle: programTitle,
    theme: _theme,
    report: report,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'each card is one page of the card size, whatever the dialog paper',
    () async {
      final pdf = await buildCallingCardsPdf(
        [_entry(_dance()), _entry(_dance(title: 'Second'))],
        layout: CallingCardLayout.parse(kDefaultCallingCardLayout),
        size: kDefaultCallingCardSize,
        dialect: Dialect.canonical,
        fields: DanceShareField.allExceptTunes,
        theme: _theme,
      );
      expect(pdfPageCount(pdf), 2);
      expect(pdfMediaBox(pdf), (360, 216));

      final a6 = await buildCallingCardsPdf(
        [_entry(_dance())],
        layout: CallingCardLayout.parse('title'),
        size: kCallingCardSizePresets['a6']!.oriented(landscape: false),
        dialect: Dialect.canonical,
        fields: DanceShareField.allExceptTunes,
        theme: _theme,
      );
      expect(pdfMediaBox(a6), (298, 420));
    },
  );

  test('the default layout prints the header, figures and notes', () async {
    final text = await _text([_entry(_dance())]);
    for (final word in [
      'Ladder',
      'Improper',
      'Pat',
      'Easy',
      'A1',
      'A2',
      '16',
      'swing',
      'Calling',
      'Watch',
    ]) {
      expect(text, contains(word), reason: word);
    }
  });

  test('only the blocks the layout names are printed', () async {
    final text = await _text([_entry(_dance())], layout: 'title\nfigures');
    expect(text, contains('Ladder'));
    expect(text, contains('swing'));
    expect(text, isNot(contains('Improper')));
    expect(text, isNot(contains('Watch')));
    expect(text, isNot(contains('Pat')));
  });

  test('a field turned off in the share picker stays off the card', () async {
    final text = await _text(
      [_entry(_dance())],
      fields: {DanceShareField.walkthrough},
    );
    expect(text, contains('Ladder'));
    expect(text, isNot(contains('Watch')), reason: 'calling notes are off');
    expect(text, isNot(contains('Pat')), reason: 'authors are off');
    expect(text, isNot(contains('Improper')), reason: 'formation is off');
    expect(text, isNot(contains('Easy')), reason: 'level is off');
  });

  test('labels, text, number and program blocks', () async {
    final text = await _text(
      [_entry(_dance(), number: '7')],
      layout: '''
number | program
text "Hello hall"
notes label="NB: "
notes label=""
''',
      programTitle: 'Friday Dance',
    );
    expect(text, contains('7'));
    expect(text, contains('Friday'));
    expect(text, contains('Hello hall'.split(' ').first));
    expect(text, contains('NB:'));
    expect(text, isNot(contains('Calling')));
  });

  test('figure options drop beats, phrases and figure notes', () async {
    final dance = _dance(
      figures: [
        Figure(
          move: 'swing',
          params: {'who': 'partners', 'beats': 16},
          note: 'Noted',
        ),
      ],
    );
    final full = await _text([_entry(dance)], layout: 'figures');
    expect(full, contains('16'));
    expect(full, contains('A1'));
    expect(full, contains('Noted'));
    final bare = await _text([
      _entry(dance),
    ], layout: 'figures beats=off phrases=off notes=off');
    expect(bare, contains('swing'));
    expect(bare, isNot(contains('16')));
    expect(bare, isNot(contains('A1')));
    expect(bare, isNot(contains('Noted')));
  });

  group('shrink to fit', () {
    test('a card that fits prints at full size', () async {
      final report = CallingCardFitReport();
      await _text([_entry(_dance())], report: report);
      expect(report.scales, [1.0]);
      expect(report.overflowed, isEmpty);
    });

    test(
      'a long card shrinks to fit, and the report says by how much',
      () async {
        final report = CallingCardFitReport();
        final figures = [
          for (var i = 0; i < 16; i++)
            Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
        ];
        await _text([
          _entry(_dance(figures: figures, callingNotes: '')),
        ], report: report);
        expect(report.scales.single, lessThan(1));
        expect(
          report.scales.single,
          greaterThanOrEqualTo(kCallingCardMinScale),
        );
        expect(report.overflowed, isEmpty);
      },
    );

    test('a card too long even at the smallest scale is reported', () async {
      final report = CallingCardFitReport();
      final text = await _text(
        [
          _entry(_dance(title: 'Endless', callingNotes: 'word ' * 2000)),
          _entry(_dance(title: 'Short')),
        ],
        // No `lines=` cap, which would keep the notes short enough to fit.
        layout: 'title\nnotes',
        report: report,
      );
      expect(report.scales, [kCallingCardMinScale, 1.0]);
      expect(report.overflowed, ['Endless']);
      expect(text, contains('Short'));
    });

    test('the report is cleared by each build', () async {
      final report = CallingCardFitReport();
      await _text([_entry(_dance())], report: report);
      await _text([_entry(_dance())], report: report);
      expect(report.scales, [1.0]);
    });
  });

  test('a row whose blocks are all empty takes no space', () async {
    // The sample has no level; a level-only row must not leave a gap, which
    // shows as the same scale as a layout without it.
    final withRow = CallingCardFitReport();
    final withoutRow = CallingCardFitReport();
    final long = _dance(
      figures: [
        for (var i = 0; i < 14; i++)
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
      ],
    );
    CallingCardEntry noLevel(Dance d) => CallingCardEntry(
      dance: d,
      labels: (
        authorNames: const [],
        formationLabel: '',
        levelLabel: null,
        statusLabel: 'Active',
        sourceLines: const [],
      ),
    );
    await _text([noLevel(long)], layout: 'level\nfigures', report: withRow);
    await _text([noLevel(long)], layout: 'figures', report: withoutRow);
    expect(withRow.scales, withoutRow.scales);
  });

  test(
    'bold italic never falls back to a Latin-1-only standard font',
    () async {
      // No theme: the bundled one, which has no bold-italic face of its own.
      final pdf = await buildCallingCardsPdf(
        [_entry(_dance())],
        layout: CallingCardLayout.parse('notes italic\ntitle bold italic'),
        size: kDefaultCallingCardSize,
        dialect: Dialect.canonical,
        fields: DanceShareField.allExceptTunes,
      );
      expect(latin1.decode(pdf), isNot(contains('Helvetica')));
    },
  );

  group('several to a page', () {
    test('the grid fits the most cards, turning them when that fits more', () {
      // 5 × 3 in on Letter: 3 upright (one column), 4 turned (2 × 2).
      expect(
        callingCardSheetGrid(PdfPageFormat.letter, kDefaultCallingCardSize),
        (columns: 2, rows: 2, rotated: true, margin: kCallingCardSheetMargin),
      );
      // 6 × 4 in on Letter: 2 either way, so they stay upright.
      expect(
        callingCardSheetGrid(
          PdfPageFormat.letter,
          kCallingCardSizePresets['index4x6']!,
        ),
        (columns: 1, rows: 2, rotated: false, margin: kCallingCardSheetMargin),
      );
      // An upright 5 × 8 in card fits once; turned, it is 8 in across,
      // exactly Letter's printable width, and two stack in its 10.5 in.
      expect(
        callingCardSheetGrid(
          PdfPageFormat.letter,
          const CallingCardSize(5, 8, CallingCardUnit.inch),
        ),
        (columns: 1, rows: 2, rotated: true, margin: kCallingCardSheetMargin),
      );
      // A6 is a quarter of A4 and A7 an eighth: they only tile it by
      // filling the page, which needs no margin.
      expect(
        callingCardSheetGrid(PdfPageFormat.a4, kCallingCardSizePresets['a6']!),
        (columns: 2, rows: 2, rotated: true, margin: 0.0),
      );
      final a7 = callingCardSheetGrid(
        PdfPageFormat.a4,
        kCallingCardSizePresets['a7']!,
      );
      expect(a7.columns * a7.rows, 8);
      expect(a7.margin, 0);
      // Larger than the paper either way.
      final big = callingCardSheetGrid(
        PdfPageFormat.letter,
        const CallingCardSize(14, 13, CallingCardUnit.inch),
      );
      expect(big.columns * big.rows, 0);
    });

    test('paper as print dialogs report it still takes an exact grid', () {
      // Windows reports A4 as 595.2 × 841.8 pt, macOS as 595 × 842, against
      // the true 595.28 × 841.89.
      for (final a4 in [
        const PdfPageFormat(595.2, 841.8),
        const PdfPageFormat(595, 842),
      ]) {
        final a6 = callingCardSheetGrid(a4, kCallingCardSizePresets['a6']!);
        final a7 = callingCardSheetGrid(a4, kCallingCardSizePresets['a7']!);
        expect(a6.columns * a6.rows, 4, reason: '$a4');
        expect(a7.columns * a7.rows, 8, reason: '$a4');
      }
    });

    test('the tolerance is a point, no more', () {
      // Two 3 in (216 pt) cards across need 432 pt.
      const card = CallingCardSize(3, 13, CallingCardUnit.inch);
      int across(double width) =>
          callingCardSheetGrid(PdfPageFormat(width, 1000), card).columns;
      expect(across(431.1), 2);
      expect(across(430.9), 1);
    });

    group('cut marks', () {
      /// Every mark is a full-length mark on one of the grid's cut lines,
      /// so it never crosses a card's content, and keeps [inset] from the
      /// paper's edge.
      void expectOnCutLines(
        List<CallingCardCutMark> marks, {
        required double pageWidth,
        required double pageHeight,
        required double left,
        required double top,
        required double cellWidth,
        required double cellHeight,
        required int columns,
        required int rows,
        required double inset,
      }) {
        final columnLines = [
          for (var c = 0; c <= columns; c++) left + c * cellWidth,
        ];
        final rowLines = [for (var r = 0; r <= rows; r++) top + r * cellHeight];
        for (final m in marks) {
          if (m.x1 == m.x2) {
            expect(columnLines, contains(m.x1), reason: '$m');
            expect((m.y2 - m.y1).abs(), closeTo(11, 1e-9), reason: '$m');
          } else {
            expect(m.y1, m.y2, reason: '$m is not straight');
            expect(rowLines, contains(m.y1), reason: '$m');
            expect((m.x2 - m.x1).abs(), closeTo(11, 1e-9), reason: '$m');
          }
          for (final (x, y) in [(m.x1, m.y1), (m.x2, m.y2)]) {
            expect(x, inInclusiveRange(inset, pageWidth - inset), reason: '$m');
            expect(
              y,
              inInclusiveRange(inset, pageHeight - inset),
              reason: '$m',
            );
          }
        }
      }

      // A6 on A4, turned: 2 × 2 cells filling the page.
      const a6w = 105 * 72 / 25.4, a6h = 148 * 72 / 25.4;
      final a6left = (595.28 - 2 * a6w) / 2, a6top = (841.89 - 2 * a6h) / 2;

      for (final inset in [12.0, 18.0]) {
        test(
          'a grid that fills the page is marked inside a $inset pt edge',
          () {
            final marks = callingCardCutMarks(
              pageWidth: 595.28,
              pageHeight: 841.89,
              left: a6left,
              top: a6top,
              cellWidth: a6w,
              cellHeight: a6h,
              columns: 2,
              rows: 2,
              printableInset: inset,
            );
            // The outer lines are the paper's edges: only the middle column
            // line (above and below) and the middle row line (either side).
            expect(marks, hasLength(4));
            expectOnCutLines(
              marks,
              pageWidth: 595.28,
              pageHeight: 841.89,
              left: a6left,
              top: a6top,
              cellWidth: a6w,
              cellHeight: a6h,
              columns: 2,
              rows: 2,
              inset: inset,
            );
          },
        );
      }

      test('room around the grid: full marks outside it', () {
        // 3 × 5 in cards turned on Letter: 2 × 2 cells of 216 × 360 pt.
        const left = (612 - 432) / 2, top = (792 - 720) / 2;
        final marks = callingCardCutMarks(
          pageWidth: 612,
          pageHeight: 792,
          left: left,
          top: top,
          cellWidth: 216,
          cellHeight: 360,
          columns: 2,
          rows: 2,
          printableInset: 12,
        );
        expect(marks, hasLength(12));
        for (final m in marks) {
          final outside =
              math.max(m.y1, m.y2) <= top ||
              math.min(m.y1, m.y2) >= top + 720 ||
              math.max(m.x1, m.x2) <= left ||
              math.min(m.x1, m.x2) >= left + 432;
          expect(outside, isTrue, reason: '$m');
        }
        expectOnCutLines(
          marks,
          pageWidth: 612,
          pageHeight: 792,
          left: left,
          top: top,
          cellWidth: 216,
          cellHeight: 360,
          columns: 2,
          rows: 2,
          inset: 12,
        );
      });

      test('too little room outside for a full mark: inward instead', () {
        // 23 pt from an 18 pt inset leaves 2 pt outside; the marks run in.
        final marks = callingCardCutMarks(
          pageWidth: 600,
          pageHeight: 600,
          left: 23,
          top: 23,
          cellWidth: 277,
          cellHeight: 277,
          columns: 2,
          rows: 2,
          printableInset: 18,
        );
        expect(marks, hasLength(12));
        expect(marks.first.y1, 23, reason: 'starts at the grid edge');
        expectOnCutLines(
          marks,
          pageWidth: 600,
          pageHeight: 600,
          left: 23,
          top: 23,
          cellWidth: 277,
          cellHeight: 277,
          columns: 2,
          rows: 2,
          inset: 18,
        );
      });
    });

    Future<Uint8List> sheets(
      int count, {
      CallingCardSize size = kDefaultCallingCardSize,
      CallingCardFitReport? report,
    }) => buildCallingCardsPdf(
      [for (var i = 0; i < count; i++) _entry(_dance(title: 'Dance $i'))],
      layout: CallingCardLayout.parse('title'),
      size: size,
      dialect: Dialect.canonical,
      fields: DanceShareField.allExceptTunes,
      theme: _theme,
      sheet: PdfPageFormat.letter,
      report: report,
    );

    test('pages are the paper, filled a grid at a time', () async {
      final report = CallingCardFitReport();
      final pdf = await sheets(5, report: report);
      expect(pdfMediaBox(pdf), (612, 792));
      expect(pdfPageCount(pdf), 2, reason: '4 to a page, then 1');
      expect(report.scales, hasLength(5));
      expect(report.cardsShrunkToSheet, isFalse);
      final text = pdfText(pdf);
      for (var i = 0; i < 5; i++) {
        expect(text, contains('$i'));
      }
      expect(pdfPageCount(await sheets(4)), 1);
    });

    test(
      'cards bigger than the paper print one to a page, and say so',
      () async {
        final report = CallingCardFitReport();
        final pdf = await sheets(
          3,
          size: const CallingCardSize(14, 13, CallingCardUnit.inch),
          report: report,
        );
        expect(pdfMediaBox(pdf), (612, 792));
        expect(pdfPageCount(pdf), 3);
        expect(report.cardsShrunkToSheet, isTrue);
        // The flag is cleared by the next build.
        await sheets(1, report: report);
        expect(report.cardsShrunkToSheet, isFalse);
      },
    );
  });

  test('the editor sample dance is valid under the taxonomy', () {
    final sample = callingCardSampleDance(
      title: 'Sample',
      notes: 'notes',
      figureNote: 'note',
    );
    final figures = (sample.figuresSource as DecodedFigures).figures;
    for (final f in figures) {
      // testFigure validates against the contra taxonomy and throws if the
      // move or its params are not valid.
      testFigure(
        move: f.move,
        params: f.params,
        note: f.note,
        progression: f.progression,
      );
    }
    expect(figures.where((f) => f.progression), hasLength(1));
  });
}
