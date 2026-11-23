import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:compendium_app/src/export/calling_card_pdf.dart';
import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/pdf_probe.dart';

/// An English dance is counted in bars on paper as on screen (ADR-006 §5.5),
/// and a set list that mixes forms names each dance's form (S5).
///
/// The builders take the plain Helvetica theme so [pdfText] can read each
/// drawn word back.

final _theme = pw.ThemeData.base();
final _now = DateTime.utc(2026, 11, 20);

/// Siding for 6 bars and a turn single for 1½, in 2/2 (a bar of 2 beats).
Dance _english() => Dance(
  id: 'e',
  title: 'Hole in the Wall',
  form: DanceForm.ecd,
  phraseStructure: '2*8*2',
  formation: const Formation(FormationShape.dupleMinor),
  figures: [
    Figure(move: 'ecd_siding', params: const {'beats': 12}),
    Figure(move: 'ecd_turn_single', params: const {'beats': 3}),
  ],
  createdAt: _now,
  updatedAt: _now,
);

Dance _contra() => Dance(
  id: 'c',
  title: 'Contra One',
  figures: [
    Figure(move: 'swing', params: const {'who': 'partners', 'beats': 12}),
  ],
  formation: const Formation(FormationShape.dupleImproper),
  createdAt: _now,
  updatedAt: _now,
);

CallingCardEntry _entry(Dance d) => CallingCardEntry(
  dance: d,
  number: '',
  labels: (
    authorNames: const [],
    formationLabel: 'Duple minor',
    levelLabel: null,
    statusLabel: 'Active',
    sourceLines: const [],
  ),
);

Future<String> _card(Dance d) async => pdfText(
  await buildCallingCardsPdf(
    [_entry(d)],
    layout: CallingCardLayout.parse('figures'),
    size: kDefaultCallingCardSize,
    dialects: DialectsByForm.all(Dialect.canonical),
    fields: DanceShareField.allExceptTunes,
    programTitle: '',
    theme: _theme,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a calling card counts an English dance in bars', () async {
    final text = await _card(_english());
    expect(text, contains('1½'));
    expect(text, contains('6'));
    expect(text, isNot(contains('12')));
    // Contra keeps its beats.
    expect(await _card(_contra()), contains('12'));
  });

  test('a card whose counts are not all whole half bars stays in beats', () {
    // 3/4: 21 beats is 7 bars, but 8 beats is no whole number of bars, so
    // the bare numbers of the column all stay in beats.
    return _card(
      _english().copyWith(
        meter: '3/4',
        phraseStructure: '2*24*3',
        figures: [
          Figure(move: 'ecd_siding', params: const {'beats': 21}),
          Figure(move: 'ecd_turn_single', params: const {'beats': 8}),
        ],
      ),
    ).then((text) {
      expect(text, contains('21'));
      expect(text, contains('8'));
      expect(text, isNot(contains('7')));
    });
  });

  Dance mixed(List<int> beats) => _english().copyWith(
    phraseStructure: 'A:2*4*3 + B:1*8*2',
    figures: [
      for (final (i, b) in beats.indexed)
        testFigure(
          move: i.isEven ? 'ecd_siding' : 'ecd_turn_single',
          params: {'beats': b},
        ),
    ],
  );

  test('a calling card counts a tune whose phrases differ in the bars of '
      'each phrase', () async {
    // 12 beats are 4 bars of 3, and 8 from beat 24 are 4 bars of 2.
    final text = await _card(mixed([12, 12, 8]));
    expect(text, contains('4'));
    expect(text, isNot(contains('12')));
    expect(text, isNot(contains('8')));
  });

  test('a mixed card with a count that is no whole number of half bars '
      'stays in beats', () async {
    final text = await _card(mixed([12, 5]));
    expect(text, contains('12'));
    expect(text, contains('5'));
  });

  test('the dance PDF counts a figure across the change by its own '
      'phrases', () async {
    final text = pdfText(
      await buildDancePdf(
        mixed([18, 10]),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple minor',
        statusLabel: 'Active',
        theme: _theme,
      ),
    );
    expect(text, contains('6 bars'));
    expect(text, contains('4 bars'));
    expect(text, isNot(contains('beats')));
  });

  test('the dance PDF counts an English dance in bars', () async {
    final text = pdfText(
      await buildDancePdf(
        _english(),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'Duple minor',
        statusLabel: 'Active',
        theme: _theme,
      ),
    );
    expect(text, contains('6 bars'));
    expect(text, contains('1½ bars'));
    expect(text, isNot(contains('beats')));
  });

  test('the set-list PDF\'s figures appendix counts a tune whose phrases '
      'differ by phrase', () async {
    final english = mixed([18, 10]);
    final text = pdfText(
      await buildProgramPdf(
        Program(
          id: 'p1',
          title: 'Friday Dance',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: 'e')],
          createdAt: _now,
          updatedAt: _now,
        ),
        titleFor: (id) => english.title,
        formLabelFor: (id) => 'English (ECD)',
        appendDances: [(dance: english, isAlternate: false)],
        danceLabels: const DanceExportLabels(),
        theme: _theme,
      ),
    ).replaceAll(r'\', '');
    expect(text, contains('6 bars'));
    expect(text, contains('4 bars'));
    expect(text, isNot(contains('beats')));
  });

  test('the set-list PDF names each form in a program that mixes them, and '
      'its figures appendix counts an English dance in bars', () async {
    final english = _english();
    final contra = _contra();
    final dances = {english.id: english, contra.id: contra};
    final text = pdfText(
      await buildProgramPdf(
        Program(
          id: 'p1',
          title: 'Friday Dance',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'e'),
            ProgramSlot(id: 's2', position: 1, danceId: 'c'),
          ],
          createdAt: _now,
          updatedAt: _now,
        ),
        titleFor: (id) => dances[id]?.title,
        formLabelFor: (id) =>
            dances[id]!.form == DanceForm.ecd ? 'English (ECD)' : 'Contra',
        appendDances: [
          (dance: english, isAlternate: false),
          (dance: contra, isAlternate: false),
        ],
        danceLabels: const DanceExportLabels(),
        theme: _theme,
      ),
      // The PDF string escapes its parentheses.
    ).replaceAll(r'\', '');
    expect(text, contains('Hole in the Wall (English (ECD))'));
    expect(text, contains('Contra One (Contra)'));
    expect(text, contains('6 bars'));
    expect(text, contains('12 beats'));
  });
}
