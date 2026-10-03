import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// `danceToPlainText` and the PDF builders gate the dance-card fields through
/// the same `dance_card_fields.dart` helpers. This pins that: for every subset
/// of the share-fields picker the text card carries exactly the lines the
/// helpers return — no more, no fewer.
void main() {
  final now = DateTime.utc(2026, 7, 10);

  Dance danceWith({required DanceStatus status, required bool mixer}) => Dance(
    id: 'd1',
    title: "Rory O'More",
    formation: const Formation(FormationShape.dupleImproper),
    phraseStructure: '6*8*2',
    mixer: mixer,
    status: status,
    tunes: const ['Tune One', 'Tune Two'],
    createdAt: now,
    updatedAt: now,
  );

  // Every gated field populated: non-active status, mixer, phrase, tunes.
  final full = danceWith(status: DanceStatus.broken, mixer: true);
  // The gates that depend on the dance itself (Status only for a non-active
  // dance, Mixer only for a mixer) must be exercised both ways, or dropping
  // the condition from one renderer would go unnoticed.
  final variants = [
    full,
    danceWith(status: DanceStatus.active, mixer: true),
    danceWith(status: DanceStatus.broken, mixer: false),
  ];
  const authorNames = ['Alice Author', 'Bob Writer'];
  const labels = DanceExportLabels();

  List<Set<DanceShareField>> allSubsets() {
    const values = DanceShareField.values;
    return [
      for (var mask = 0; mask < (1 << values.length); mask++)
        {
          for (var i = 0; i < values.length; i++)
            if (mask & (1 << i) != 0) values[i],
        },
    ];
  }

  /// The lines the helpers say the card carries for [fields], in order:
  /// authors, then the meta lines, then (with its header) the tunes.
  List<String> helperLines(Dance dance, Set<DanceShareField> fields) {
    final authors = danceCardAuthorNames(authorNames, fields);
    final tunes = danceCardTuneNames(dance, fields);
    return [
      if (authors.isNotEmpty) authors.join(', '),
      ...danceCardMetaLines(
        dance,
        formationLabel: 'Becket',
        levelLabel: 'Intermediate',
        statusLabel: 'Broken',
        labels: labels,
        fields: fields,
      ),
      if (tunes.isNotEmpty) ...['${labels.tunes}:', tunes.join(', ')],
    ];
  }

  test('danceToPlainText emits exactly the lines '
      'danceCardMetaLines/AuthorNames/TuneNames gate, '
      'for every DanceShareField subset', () {
    // Every line any subset can produce; each must appear iff gated in.
    final universe = helperLines(full, DanceShareField.all);
    expect(universe, hasLength(8));

    final subsets = allSubsets();
    expect(subsets, hasLength(512));
    for (final dance in variants) {
      for (final fields in subsets) {
        final text = danceToPlainText(
          dance,
          dialect: Dialect.larksRobins,
          authorNames: authorNames,
          formationLabel: 'Becket',
          levelLabel: 'Intermediate',
          statusLabel: 'Broken',
          labels: labels,
          fields: fields,
        );
        final textLines = text.split('\n');
        final expected = helperLines(dance, fields);
        final reason =
            'status: ${dance.status.name}, mixer: ${dance.mixer}, '
            'fields: ${fields.map((f) => f.name).toList()}';
        for (final line in universe) {
          expect(
            textLines.contains(line),
            expected.contains(line),
            reason: '"$line" — $reason',
          );
        }
        // Same relative order as the helpers emit.
        expect(
          textLines.where(universe.contains).toList(),
          expected,
          reason: reason,
        );
      }
    }
  });
}
