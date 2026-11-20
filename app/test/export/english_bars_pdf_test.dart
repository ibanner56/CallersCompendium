import 'package:compendium_app/src/export/calling_card_layout.dart';
import 'package:compendium_app/src/export/calling_card_pdf.dart';
import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
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
