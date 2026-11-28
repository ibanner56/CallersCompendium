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
    String hook = '  The role1s open with a swing.  ',
    List<SourceCitation> sourceCitations = const [],
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
    hook: hook,
    sourceCitations: sourceCitations,
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
    List<String> sourceLines = const [],
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
    sourceLines: sourceLines,
  );

  String text(
    Dance d,
    Set<DanceShareField> fields, {
    Dialect? dialect,
    bool canonicalize = false,
    List<String> sourceLines = const [],
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
    sourceLines: sourceLines,
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
                sourceLines: const ['Give-and-Take (p. 12)'],
              );
              final rendered = text(
                d,
                fields,
                dialect: dialect,
                canonicalize: canonicalize,
                sourceLines: const ['Give-and-Take (p. 12)'],
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
                lines.contains('${labels.hook}: ${content.hook}'),
                content.hook != null,
                reason: reason,
              );
              expect(
                lines.contains('${labels.sources}:'),
                content.sourceLines.isNotEmpty,
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

  group('hook and sources (OUT-6)', () {
    const sources = ['Give-and-Take — A. Author, 1990 (p. 12)', '  '];

    test('are off in the default set and on in all', () {
      for (final f in [DanceShareField.hook, DanceShareField.sources]) {
        expect(DanceShareField.allExceptTunes, isNot(contains(f)));
        expect(DanceShareField.all, contains(f));
        expect(DanceShareField.fromJson(f.toJson()), f);
      }
      final content = DanceCardContent.build(
        dance(),
        dialect: Dialect.larksRobins,
        authorNames: authorNames,
        formationLabel: 'Becket',
        statusLabel: 'Broken',
        sourceLines: sources,
      );
      expect(content.hook, isNull);
      expect(content.sourceLines, isEmpty);
    });

    test('hook is trimmed, dialect-rendered and gated', () {
      final larks = build(dance(), const {DanceShareField.hook});
      final canonical = build(dance(), const {
        DanceShareField.hook,
      }, dialect: Dialect.canonical);
      expect(larks.hook, 'The larks open with a swing.');
      expect(canonical.hook, 'The role1s open with a swing.');
      expect(build(dance(hook: '  '), DanceShareField.all).hook, isNull);
      expect(
        text(dance(), const {DanceShareField.hook}).split('\n'),
        contains('Hook: The larks open with a swing.'),
      );
    });

    test('sources drop blank lines, gate on the field and get a heading', () {
      final content = build(dance(), const {
        DanceShareField.sources,
      }, sourceLines: sources);
      expect(content.sourceLines, [sources.first]);
      expect(
        text(dance(), const {
          DanceShareField.sources,
        }, sourceLines: sources).split('\n'),
        containsAllInOrder(['Sources:', sources.first]),
      );
      expect(
        text(dance(), const {DanceShareField.hook}, sourceLines: sources),
        isNot(contains('Sources:')),
      );
    });

    test('count as a card body, so a set-list appends a card for them', () {
      Dance bare({String hook = '', List<SourceCitation>? cites}) => Dance(
        id: 'b',
        title: 'Bare',
        formation: const Formation(FormationShape.dupleImproper),
        hook: hook,
        sourceCitations: cites ?? const [],
        createdAt: now,
        updatedAt: now,
      );
      final cited = bare(
        cites: [SourceCitation(sourceId: 's1', page: '12')],
      );
      expect(DanceCardContent.hasBody(bare(), DanceShareField.all), isFalse);
      expect(
        DanceCardContent.hasBody(bare(hook: 'x'), const {DanceShareField.hook}),
        isTrue,
      );
      expect(
        DanceCardContent.hasBody(bare(hook: 'x'), const {
          DanceShareField.tunes,
        }),
        isFalse,
      );
      expect(
        DanceCardContent.hasBody(cited, const {DanceShareField.sources}),
        isTrue,
      );
      expect(
        DanceCardContent.hasBody(cited, const {DanceShareField.hook}),
        isFalse,
      );
    });
  });

  test('formation and level on their own, gated by their fields', () {
    final d = dance();
    final all = build(d, DanceShareField.values.toSet());
    expect(all.formation, 'Becket');
    expect(all.level, 'Intermediate');
    final none = build(d, {DanceShareField.callingNotes});
    expect(none.formation, isNull);
    expect(none.level, isNull);
    final blank = DanceCardContent.build(
      d,
      dialect: Dialect.larksRobins,
      authorNames: authorNames,
      formationLabel: '  ',
      levelLabel: null,
      statusLabel: 'Broken',
      fields: DanceShareField.values.toSet(),
    );
    expect(blank.formation, isNull);
    expect(blank.level, isNull);
    expect(
      build(d, {DanceShareField.formation}).formation,
      'Becket',
      reason: 'trimmed label, without the Formation: prefix',
    );
  });

  group('credits and tune details', () {
    Dance english({
      String meter = ' 6/8 ',
      String musicalKey = 'G minor',
      String barnes = ' BIII p. 92 ',
      PartialDate? composedOn,
      PartialDate? interpretedOn,
    }) => Dance(
      id: 'e1',
      title: 'Hole in the Wall',
      form: DanceForm.ecd,
      formation: const Formation(FormationShape.dupleMinor),
      meter: meter,
      musicalKey: musicalKey,
      barnesReference: barnes,
      composedOn: composedOn,
      interpretedOn: interpretedOn,
      createdAt: now,
      updatedAt: now,
    );

    DanceCardContent card(
      Dance d, {
      List<String> authors = const ['Pat Shaw'],
      List<String> interpreters = const [],
      Set<DanceShareField> fields = DanceShareField.allExceptTunes,
      bool canonicalize = false,
    }) => DanceCardContent.build(
      d,
      dialect: Dialect.larksRobins,
      authorNames: authors,
      interpreterNames: interpreters,
      formationLabel: 'Duple minor',
      statusLabel: 'Active',
      canonicalizeDiscouragedTerms: canonicalize,
      fields: fields,
    );

    test('music is on by default, in all, and keeps its stored name', () {
      expect(DanceShareField.allExceptTunes, contains(DanceShareField.music));
      expect(DanceShareField.all, contains(DanceShareField.music));
      expect(DanceShareField.music.toJson(), 'music');
      expect(DanceShareField.fromJson('music'), DanceShareField.music);
    });

    test('meter and key share a line and Barnes has its own', () {
      expect(card(english()).musicLines, [
        'Meter: 6/8 · Key: G minor',
        'Barnes: BIII p. 92',
      ]);
      expect(card(english(meter: '  ')).musicLines, [
        'Key: G minor',
        'Barnes: BIII p. 92',
      ]);
      expect(card(english(musicalKey: '', barnes: '')).musicLines, [
        'Meter: 6/8',
      ]);
      expect(
        card(english(meter: '', musicalKey: '', barnes: ' ')).musicLines,
        isEmpty,
      );
    });

    test('tune details are gated on the music field', () {
      final off = {...DanceShareField.all}..remove(DanceShareField.music);
      expect(card(english(), fields: off).musicLines, isEmpty);
      expect(
        danceToPlainText(
          english(),
          dialect: Dialect.larksRobins,
          authorNames: const [],
          formationLabel: 'Duple minor',
          statusLabel: 'Active',
          fields: off,
        ),
        isNot(anyOf(contains('Meter'), contains('Barnes'))),
      );
    });

    test('the meter and key go through the discouraged-term rendering; the '
        'Barnes reference is printed as typed', () {
      // The maintainer, decision sheet question 18: a Barnes reference
      // names a book and often a tune, so it is shown as typed, as the
      // title is.
      final d = english(
        meter: 'Gypsy time',
        musicalKey: '',
        barnes: 'B2 p. 9, Ladies of London; Gypsy Round',
      );
      expect(card(d).musicLines, [
        'Meter: Gypsy time',
        'Barnes: B2 p. 9, Ladies of London; Gypsy Round',
      ]);
      expect(card(d, canonicalize: true).musicLines, [
        'Meter: Shoulder round time',
        'Barnes: B2 p. 9, Ladies of London; Gypsy Round',
      ]);
    });

    test('authors carry the composed year, interpreters their own line', () {
      final d = english(
        composedOn: PartialDate(1951, 3),
        interpretedOn: PartialDate(1916),
      );
      expect(card(d, interpreters: const ['Cecil Sharp']).creditLines, [
        'Pat Shaw (1951)',
        'Interpreted by Cecil Sharp (1916)',
      ]);
      expect(card(english(), interpreters: const ['Cecil Sharp']).creditLines, [
        'Pat Shaw',
        'Interpreted by Cecil Sharp',
      ]);
      expect(card(d, authors: const [' ']).creditLines, [
        'Composed 1951',
        'Interpreted 1916',
      ]);
      expect(card(english(), authors: const []).creditLines, isEmpty);
    });

    test('credits are gated on the authors field', () {
      final d = english(composedOn: PartialDate(1951));
      final off = {...DanceShareField.all}..remove(DanceShareField.authors);
      expect(
        card(d, interpreters: const ['Cecil Sharp'], fields: off).creditLines,
        isEmpty,
      );
    });

    test('interpreters never choose the dialect', () {
      final d = english();
      final content = DanceCardContent.build(
        d,
        dialect: Dialect.canonical,
        authorNames: const ['Pat Shaw'],
        interpreterNames: const ['Rae Fifer'],
        formationLabel: 'Duple minor',
        statusLabel: 'Active',
      );
      expect(content.dialect, Dialect.canonical);
    });

    test('the text card prints credits under the title, music after meta', () {
      final text = danceToPlainText(
        english(
          composedOn: PartialDate(1951),
          interpretedOn: PartialDate(1916),
        ),
        dialect: Dialect.larksRobins,
        authorNames: const ['Pat Shaw'],
        interpreterNames: const ['Cecil Sharp'],
        formationLabel: 'Duple minor',
        statusLabel: 'Active',
      );
      expect(text.split('\n'), [
        'Hole in the Wall',
        'Pat Shaw (1951)',
        'Interpreted by Cecil Sharp (1916)',
        'Formation: Duple minor',
        'Meter: 6/8 · Key: G minor',
        'Barnes: BIII p. 92',
      ]);
    });
  });
}
