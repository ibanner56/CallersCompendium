import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #1434: these tests exercise the shared field-gating logic directly,
/// as plain data, rather than through a rendered PDF — the existing PDF
/// tests (`buildProgramPdf`/`buildDancePdf`) only assert non-empty bytes and
/// the `%PDF` magic header, which cannot catch a missing or wrong field.
/// Testing this pure layer is what makes the PDF field-gating genuinely
/// falsifiable.
void main() {
  final now = DateTime.utc(2026, 7, 10);

  Dance dance({
    String phraseStructure = '',
    bool mixer = false,
    DanceStatus status = DanceStatus.active,
    List<String> tunes = const [],
  }) => Dance(
    id: 'd1',
    title: 'Rory O\'More',
    phraseStructure: phraseStructure,
    mixer: mixer,
    status: status,
    tunes: tunes,
    createdAt: now,
    updatedAt: now,
  );

  group('danceCardMetaLines', () {
    test('includes every line when every field is selected', () {
      final lines = danceCardMetaLines(
        dance(
          phraseStructure: '6*8*2',
          mixer: true,
          status: DanceStatus.broken,
        ),
        formationLabel: 'Becket',
        levelLabel: 'Intermediate',
        statusLabel: 'Broken',
        labels: const DanceExportLabels(),
        fields: DanceShareField.all,
      );
      expect(lines, [
        'Formation: Becket',
        'Level: Intermediate',
        'Mixer',
        'Status: Broken',
        'Phrase: 6*8*2',
      ]);
    });

    test('omits each line individually when its field is deselected', () {
      for (final field in const [
        DanceShareField.formation,
        DanceShareField.level,
        DanceShareField.mixer,
        DanceShareField.status,
        DanceShareField.phraseStructure,
      ]) {
        final lines = danceCardMetaLines(
          dance(
            phraseStructure: '6*8*2',
            mixer: true,
            status: DanceStatus.broken,
          ),
          formationLabel: 'Becket',
          levelLabel: 'Intermediate',
          statusLabel: 'Broken',
          labels: const DanceExportLabels(),
          fields: {...DanceShareField.all}..remove(field),
        );
        expect(lines, hasLength(4), reason: field.name);
      }
    });

    test('an active dance never shows Status, regardless of fields', () {
      final lines = danceCardMetaLines(
        dance(),
        formationLabel: '',
        statusLabel: 'Active',
        labels: const DanceExportLabels(),
        fields: DanceShareField.all,
      );
      expect(lines.any((l) => l.contains('Status')), isFalse);
    });
  });

  group('danceCardAuthorNames', () {
    test('returns trimmed, non-blank names when authors is selected', () {
      expect(
        danceCardAuthorNames(const [
          'Carol Ormand',
          '  ',
          'Cary Ravitz',
        ], DanceShareField.all),
        ['Carol Ormand', 'Cary Ravitz'],
      );
    });

    test('returns empty when authors is not selected', () {
      expect(
        danceCardAuthorNames(const [
          'Carol Ormand',
        ], {...DanceShareField.all}..remove(DanceShareField.authors)),
        isEmpty,
      );
    });
  });

  group('danceCardTuneNames', () {
    test('returns empty when tunes is not selected (the default)', () {
      expect(
        danceCardTuneNames(
          dance(tunes: const ['Rakes of Kildare']),
          DanceShareField.allExceptTunes,
        ),
        isEmpty,
      );
    });

    test('returns trimmed, non-blank tune names when tunes is selected', () {
      expect(
        danceCardTuneNames(
          dance(tunes: const ['Rakes of Kildare', '  ', 'Kesh Jig']),
          DanceShareField.all,
        ),
        ['Rakes of Kildare', 'Kesh Jig'],
      );
    });

    test('an unreadable tune list renders as absent, not an error', () {
      final unreadable = Dance(
        id: 'd2',
        title: 'Stub',
        tunesSource: const UnreadableTunes('not json'),
        createdAt: now,
        updatedAt: now,
      );
      expect(danceCardTuneNames(unreadable, DanceShareField.all), isEmpty);
    });
  });
}
