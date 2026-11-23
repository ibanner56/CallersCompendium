import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// `danceToPlainText` and the PDF builders gate the dance-card fields through
/// `DanceCardContent`, which uses the `dance_card_fields.dart` helpers. This
/// pins that: for every subset of the share-fields picker the text card carries
/// exactly the lines the
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
    hook: 'Open with a long swing',
    // English, so the Barnes reference is kept (the model clears it for
    // any other form).
    form: DanceForm.ecd,
    meter: '6/8',
    musicalKey: 'G minor',
    barnesReference: 'BIII p. 92',
    composedOn: PartialDate(1951),
    interpretedOn: PartialDate(1916),
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
  const interpreterNames = ['Cecil Interpreter'];
  const sourceLines = ['Give-and-Take — A. Author, 1990 (p. 12)'];
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
  /// the credit lines, then the meta lines, the music lines, the hook, the
  /// tunes and (each with its header) the sources.
  List<String> helperLines(Dance dance, Set<DanceShareField> fields) {
    final tunes = danceCardTuneNames(dance, fields);
    final sources = danceCardSourceLines(sourceLines, fields);
    return [
      ...danceCardCreditLines(
        dance,
        authorNames: authorNames,
        interpreterNames: interpreterNames,
        labels: labels,
        fields: fields,
      ),
      ...danceCardMetaLines(
        dance,
        formationLabel: 'Becket',
        levelLabel: 'Intermediate',
        statusLabel: 'Broken',
        labels: labels,
        fields: fields,
      ),
      ...danceCardMusicLines(
        dance,
        labels: labels,
        fields: fields,
        render: (v) => v,
      ),
      if (fields.contains(DanceShareField.hook))
        '${labels.labelled(labels.hook)}${dance.hook}',
      if (tunes.isNotEmpty) ...[labels.heading(labels.tunes), tunes.join(', ')],
      if (sources.isNotEmpty) ...[labels.heading(labels.sources), ...sources],
    ];
  }

  test('danceToPlainText emits exactly the lines '
      'danceCardCreditLines/MetaLines/MusicLines/TuneNames gate, '
      'for every DanceShareField subset', () {
    // Every line any subset can produce; each must appear iff gated in.
    final universe = helperLines(full, DanceShareField.all);
    expect(universe, hasLength(14));

    final subsets = allSubsets();
    expect(subsets, hasLength(4096));
    for (final dance in variants) {
      for (final fields in subsets) {
        final text = danceToPlainText(
          dance,
          dialect: Dialect.larksRobins,
          authorNames: authorNames,
          interpreterNames: interpreterNames,
          formationLabel: 'Becket',
          levelLabel: 'Intermediate',
          statusLabel: 'Broken',
          labels: labels,
          fields: fields,
          sourceLines: sourceLines,
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
