import 'package:compendium_app/src/export/dance_pdf.dart';
import 'package:compendium_app/src/export/program_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/pdf_probe.dart';

/// The dance and set-list PDFs join each label to its value with the labels'
/// separator (`：` in Japanese), as the copied text does. The builders take
/// the plain Helvetica theme so [pdfText] can read each drawn word back, and
/// the separator is `|` so a hard-coded `": "` cannot pass for it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final theme = pw.ThemeData.base();
  final now = DateTime.utc(2026, 1, 1);
  const danceLabels = DanceExportLabels(labelSeparator: '|');
  const programLabels = ProgramExportLabels(labelSeparator: '|');

  Dance dance(String id) => Dance(
    id: id,
    title: 'Dance $id',
    hook: 'Hookline',
    figures: [
      Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
    ],
    createdAt: now,
    updatedAt: now,
  );

  test('the dance PDF', () async {
    final text = pdfText(
      await buildDancePdf(
        dance('d'),
        dialect: Dialect.canonical,
        authorNames: const [],
        formationLabel: 'F',
        statusLabel: 'S',
        labels: danceLabels,
        fields: DanceShareField.values.toSet(),
        theme: theme,
      ),
    );
    expect(text, contains('Formation|F'));
    expect(text, contains('Hook|Hookline'));
  });

  test('the set-list PDF, its venue block and its figures appendix', () async {
    final text = pdfText(
      await buildProgramPdf(
        Program(
          id: 'p',
          title: 'Program',
          venueId: 'v',
          slots: [
            ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
          ],
          createdAt: now,
          updatedAt: now,
        ),
        titleFor: (id) => 'Dance $id',
        venuesById: {
          'v': Venue(id: 'v', name: 'Hall', time: 'Eight', price: 'Ten'),
        },
        labels: programLabels,
        danceLabels: danceLabels,
        appendDances: [(dance: dance('d2'), isAlternate: true)],
        cardLabelsFor: (_) => (
          authorNames: const [],
          interpreterNames: const <String>[],
          formationLabel: 'F',
          levelLabel: null,
          statusLabel: 'S',
          sourceLines: const [],
        ),
        dialects: DialectsByForm.all(Dialect.canonical),
        fields: DanceShareField.values.toSet(),
        theme: theme,
      ),
    );
    expect(text, contains('Time|Eight'));
    expect(text, contains('Price|Ten'));
    expect(text, contains('ALT|Dance'));
    expect(text, contains('Alternate|Dance'));
    expect(text, contains('Hook|Hookline'));
  });
}
