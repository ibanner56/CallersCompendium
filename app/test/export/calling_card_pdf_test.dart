import 'dart:convert';

import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:compendium_app/src/export/calling_card_pdf.dart';
import 'package:compendium_app/src/export/calling_card_sample.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('figures highlight sets the moves and dancers in bold', () async {
    // Without the phrase column and beats, nothing else on the card is bold,
    // so the bold face is used only if the figure lines are highlighted.
    Future<String> raw(String layout) async => latin1.decode(
      await buildCallingCardsPdf(
        [_entry(_dance())],
        layout: CallingCardLayout.parse(layout),
        size: kDefaultCallingCardSize,
        dialect: Dialect.canonical,
        fields: DanceShareField.allExceptTunes,
        theme: _theme,
      ),
    );
    expect(
      await raw('figures phrases=off beats=off'),
      isNot(contains('Helvetica-Bold')),
    );
    final highlighted = await raw('figures phrases=off beats=off highlight');
    expect(highlighted, contains('Helvetica-Bold'));
    final text = pdfText(
      await buildCallingCardsPdf(
        [_entry(_dance())],
        layout: CallingCardLayout.parse('figures highlight'),
        size: kDefaultCallingCardSize,
        dialect: Dialect.canonical,
        fields: DanceShareField.allExceptTunes,
        theme: _theme,
      ),
    );
    expect(text, contains('swing'), reason: 'the words are all still there');
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
