import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Every label in a copied card or set list is joined to its value by the
/// labels' [DanceExportLabels.labelSeparator] or
/// [ProgramExportLabels.labelSeparator], never a hard-coded `": "`.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  test('a dance card uses the separator after every label', () {
    final text = danceToPlainText(
      Dance(
        id: 'd',
        title: 'Title',
        form: DanceForm.ecd,
        phraseStructure: 'A:2*4*2 + B:1*8*2',
        hook: 'Hook text',
        callingNotes: 'Notes text',
        walkthrough: 'Walk text',
        status: DanceStatus.broken,
        createdAt: now,
        updatedAt: now,
      ),
      dialect: Dialect.canonical,
      authorNames: const [],
      formationLabel: 'F',
      levelLabel: 'L',
      statusLabel: 'S',
      labels: const DanceExportLabels(labelSeparator: '|'),
      fields: DanceShareField.values.toSet(),
      sourceLines: const ['Source line'],
    );
    expect(text.split('\n'), [
      'Title',
      'Formation|F',
      'Level|L',
      'Status|S',
      'Phrase|AAB (A 4 bars, B 8 bars)',
      'Hook|Hook text',
      '',
      'Calling notes|',
      'Notes text',
      '',
      'Walkthrough|',
      'Walk text',
      '',
      'Sources|',
      'Source line',
    ]);
  });

  test('a set list uses the separator after every label', () {
    final text = programToPlainText(
      Program(
        id: 'p',
        title: 'Program',
        band: 'Band name',
        caller: 'Caller name',
        dancerLevel: 'All',
        notes: 'Program notes',
        slots: [
          ProgramSlot(id: 's0', position: 0, danceId: 'd0', isAlt: true),
          ProgramSlot(
            id: 's1',
            position: 1,
            danceId: 'd1',
            guestCaller: 'Guest',
          ),
          ProgramSlot(id: 's2', position: 2, danceId: 'd2', isAlt: true),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      titleFor: (id) => 'Dance $id',
      labels: const ProgramExportLabels(labelSeparator: '|'),
    );
    expect(text.split('\n'), [
      'Program',
      'Band|Band name',
      'Caller|Caller name',
      'Level|All',
      '',
      'ALT|Dance d0',
      '1. Dance d1 (guest|Guest)',
      '   ALT|Dance d2',
      '',
      'Notes|',
      'Program notes',
    ]);
  });
}
