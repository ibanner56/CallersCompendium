import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// `DanceCardContent` is what the PDF builders lay out and `danceToPlainText`
/// serialises, so it must gate and render each block exactly as the text card
/// does.
void main() {
  final now = DateTime.utc(2026, 7, 10);
  const authorNames = ['Alice Author', ' Bob Writer '];
  const labels = DanceExportLabels();

  Dance dance({
    String callingNotes = '  The role1s lead out.  ',
    String walkthrough = '  Everyone forms a big circle.\n',
    List<String> tunes = const ['Tune One', ' ', 'Tune Two'],
    DanceStatus status = DanceStatus.broken,
  }) => Dance(
    id: 'd1',
    title: '  Rory O\'More ',
    formation: const Formation(FormationShape.dupleImproper),
    phraseStructure: '6*8*2',
    mixer: true,
    status: status,
    callingNotes: callingNotes,
    walkthrough: walkthrough,
    tunes: tunes,
    figures: [
      Figure(move: 'swing', params: {'who': 'partners', 'beats': 16}),
    ],
    createdAt: now,
    updatedAt: now,
  );

  DanceCardContent build(
    Dance d,
    Set<DanceShareField> fields, {
    Dialect? dialect,
    bool canonicalize = false,
  }) => DanceCardContent.build(
    d,
    dialect: dialect ?? Dialect.larksRobins,
    authorNames: authorNames,
    formationLabel: 'Becket',
    levelLabel: 'Intermediate',
    statusLabel: 'Broken',
    labels: labels,
    canonicalizeDiscouragedTerms: canonicalize,
    fields: fields,
  );

  String text(
    Dance d,
    Set<DanceShareField> fields, {
    Dialect? dialect,
    bool canonicalize = false,
  }) => danceToPlainText(
    d,
    dialect: dialect ?? Dialect.larksRobins,
    authorNames: authorNames,
    formationLabel: 'Becket',
    levelLabel: 'Intermediate',
    statusLabel: 'Broken',
    labels: labels,
    canonicalizeDiscouragedTerms: canonicalize,
    fields: fields,
  );

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

  test(
    'DanceCardContent.build gates each block exactly as danceToPlainText',
    () {
      final variants = [
        dance(),
        dance(callingNotes: '   '),
        dance(walkthrough: ''),
        dance(tunes: const []),
      ];
      for (final d in variants) {
        for (final fields in allSubsets()) {
          for (final dialect in [Dialect.canonical, Dialect.larksRobins]) {
            for (final canonicalize in [false, true]) {
              final content = build(
                d,
                fields,
                dialect: dialect,
                canonicalize: canonicalize,
              );
              final rendered = text(
                d,
                fields,
                dialect: dialect,
                canonicalize: canonicalize,
              );
              final lines = rendered.split('\n');
              final reason =
                  'fields: ${fields.map((f) => f.name).toList()}, '
                  'dialect: ${dialect.name}, canonicalize: $canonicalize';

              expect(lines.first, content.title, reason: reason);
              expect(
                lines.contains('${labels.callingNotes}:'),
                content.callingNotes != null,
                reason: reason,
              );
              if (content.callingNotes != null) {
                expect(lines, contains(content.callingNotes), reason: reason);
              }
              expect(
                lines.contains('${labels.walkthrough}:'),
                content.walkthrough != null,
                reason: reason,
              );
              if (content.walkthrough != null) {
                expect(lines, contains(content.walkthrough), reason: reason);
              }
              expect(
                lines.contains('${labels.tunes}:'),
                content.tuneNames.isNotEmpty,
                reason: reason,
              );
              expect(
                content.authorNames.isNotEmpty,
                fields.contains(DanceShareField.authors),
                reason: reason,
              );
              for (final line in content.metaLines) {
                expect(lines, contains(line), reason: reason);
              }
            }
          }
        }
      }
    },
  );

  test('renders notes and walkthrough in the requested dialect, trimmed', () {
    final canonical = build(
      dance(),
      DanceShareField.all,
      dialect: Dialect.canonical,
    );
    final larks = build(dance(), DanceShareField.all);
    expect(canonical.callingNotes, 'The role1s lead out.');
    expect(larks.callingNotes, 'The larks lead out.');
    expect(larks.walkthrough, 'Everyone forms a big circle.');
  });

  test('is null for blank or deselected notes and walkthrough', () {
    final blank = build(
      dance(callingNotes: '  ', walkthrough: ''),
      DanceShareField.all,
    );
    expect(blank.callingNotes, isNull);
    expect(blank.walkthrough, isNull);

    final deselected = build(dance(), const {DanceShareField.tunes});
    expect(deselected.callingNotes, isNull);
    expect(deselected.walkthrough, isNull);
    expect(deselected.authorNames, isEmpty);
    expect(deselected.metaLines, isEmpty);
    expect(deselected.tuneNames, ['Tune One', 'Tune Two']);
    // Figures are not gated by the picker.
    expect(deselected.figures, hasLength(1));
  });
}
