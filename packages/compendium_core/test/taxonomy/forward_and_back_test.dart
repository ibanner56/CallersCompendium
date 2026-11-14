import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

/// `forward_and_back` and its `long_lines` alias (taxonomy v39).
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final canonical = Dialect.canonical;

  Figure fab([Map<String, Object?> params = const {}]) =>
      testFigure(move: 'forward_and_back', params: params);

  group('the move and its alias', () {
    test(
      'formation offers exactly the twelve formations, long lines first',
      () {
        final spec = tax.moves['forward_and_back']!.params['formation']!;
        expect(spec.kind, ParamKind.choice);
        expect(spec.defaultValue, 'longLines');
        expect(spec.choices, [
          'longLines',
          'inSquares',
          'linesOfThree',
          'linesOfFour',
          'linesOfFive',
          'linesOfSix',
          'asCouples',
          'headCouples',
          'sideCouples',
          'inARing',
          'inLinesAtHeads',
          'inLinesAtSides',
        ]);
      },
    );

    test('carries every param long lines had, plus formation', () {
      expect(tax.moves['forward_and_back']!.params.keys, [
        'formation',
        'goBack',
        'beats',
      ]);
      expect(tax.moves, isNot(contains('long_lines')));
      final alias = tax.aliases['long_lines']!;
      expect(alias.targetMove, 'forward_and_back');
      expect(alias.pinnedParams, {'formation': 'longLines'});
      expect(alias.displayName, 'long lines');
      expect(alias.listedAsMove, isTrue);
    });

    test('a stored long lines figure keeps its meaning', () {
      final params = tax.effectiveParams(Figure(move: 'long_lines'));
      expect(params, {'formation': 'longLines', 'goBack': true, 'beats': 8});
      expect(
        tax.effectiveParams(
          Figure(move: 'long_lines', params: {'goBack': false}),
        )['beats'],
        4,
      );
      expect(tax.validateFigure(Figure(move: 'long_lines')), isEmpty);
    });

    test('beats follow goBack in every formation', () {
      for (final formation in forwardAndBackFormations) {
        expect(tax.effectiveParams(fab({'formation': formation}))['beats'], 8);
        expect(
          tax.effectiveParams(
            fab({'formation': formation, 'goBack': false}),
          )['beats'],
          4,
          reason: formation,
        );
      }
    });

    test('only the alias is the other half of the formation pair', () {
      expect(tax.aliases['long_lines']!.inversePairId, 'forward_and_back');
      expect(tax.aliases.values.where((a) => a.listedAsMove).map((a) => a.id), [
        'long_lines',
      ]);
    });
  });

  group('routing between long_lines and forward_and_back', () {
    test('a long lines in another formation is a forward and back', () {
      for (final formation in forwardAndBackFormations) {
        final f = testFigure(
          move: 'long_lines',
          params: {'formation': formation},
        );
        expect(
          tax.resolvedMoveId(f),
          formation == 'longLines' ? 'long_lines' : 'forward_and_back',
          reason: formation,
        );
      }
    });

    test('a forward and back in long lines is a long lines', () {
      expect(tax.resolvedMoveId(fab()), 'long_lines');
      expect(tax.resolvedMoveId(fab({'formation': 'longLines'})), 'long_lines');
      expect(
        tax.resolvedMoveId(fab({'formation': 'inARing'})),
        'forward_and_back',
      );
    });

    test('changing formation in the editor routes the figure', () {
      final params = tax.entryParams('long_lines');
      final moved = applyParamChange(
        tax,
        move: 'long_lines',
        params: params,
        key: 'formation',
        value: 'asCouples',
        beatsTouched: false,
        aggressiveBeats: false,
      );
      expect(moved, 'forward_and_back');
      final back = applyParamChange(
        tax,
        move: moved,
        params: params,
        key: 'formation',
        value: 'longLines',
        beatsTouched: false,
        aggressiveBeats: false,
      );
      expect(back, 'long_lines');
    });
  });

  group('wording', () {
    test('long lines renders byte-for-byte as it did as a move', () {
      for (final params in [
        const <String, Object?>{},
        const {'goBack': true},
        const {'goBack': false},
        const {'formation': 'longLines'},
      ]) {
        final f = testFigure(move: 'long_lines', params: params);
        expect(renderer.renderCanonical(f), 'long lines', reason: '$params');
        expect(renderer.render(f, canonical), 'long lines', reason: '$params');
      }
      expect(
        renderer.renderSummary(Figure(move: 'long_lines'), canonical),
        'long lines forward & back',
      );
      expect(
        renderer.renderSummary(
          Figure(move: 'long_lines', params: {'goBack': false}),
          canonical,
        ),
        'long lines forward',
      );
    });

    test('a forward and back names its formation, then the direction', () {
      const words = {
        'longLines': 'long lines',
        'inSquares': 'in squares',
        'linesOfThree': 'lines of three',
        'linesOfFour': 'lines of four',
        'linesOfFive': 'lines of five',
        'linesOfSix': 'lines of six',
        'asCouples': 'as couples',
        'headCouples': 'head couples',
        'sideCouples': 'side couples',
        'inARing': 'in a ring',
        'inLinesAtHeads': 'in lines at heads',
        'inLinesAtSides': 'in lines at sides',
      };
      expect(words.keys, forwardAndBackFormations);
      for (final MapEntry(key: formation, value: phrase) in words.entries) {
        final there = fab({'formation': formation});
        final forward = fab({'formation': formation, 'goBack': false});
        expect(
          renderer.renderCanonical(there),
          '$phrase forward and back',
          reason: formation,
        );
        // The direction is not canonical text, as it never was for long lines.
        expect(renderer.renderCanonical(forward), '$phrase forward and back');
        expect(renderer.render(there, canonical), '$phrase forward & back');
        expect(
          renderer.renderSummary(there, canonical),
          '$phrase forward & back',
        );
        expect(
          renderer.renderSummary(there, canonical, verbose: true),
          '$phrase forward and back',
        );
        expect(renderer.render(forward, canonical), '$phrase forward');
        expect(renderer.renderSummary(forward, canonical), '$phrase forward');
      }
    });

    test('as a modifier side it reads as going forward', () {
      final figure = Figure.modifier(
        figures: [
          Figure(move: 'swing'),
          fab({'formation': 'linesOfThree'}),
          fab({'formation': 'inARing', 'goBack': false}),
          Figure(move: 'long_lines'),
        ],
        beats: 16,
      );
      final rendered = renderer.renderSummary(figure, canonical);
      expect(rendered, contains('lines of three going forward & back'));
      expect(rendered, contains('in a ring going forward'));
      expect(rendered, contains('forming long lines'));
    });
  });

  group('dialects', () {
    test('a name for long lines applies to long lines only', () {
      final d = Dialect(name: 'D', moves: {'long_lines': 'lines'});
      expect(renderer.render(Figure(move: 'long_lines'), d), 'lines');
      expect(
        renderer.renderSummary(Figure(move: 'long_lines'), d),
        'lines forward & back',
      );
      expect(renderer.displayMoveName('long_lines', d), 'lines');
      expect(
        renderer.render(fab({'formation': 'asCouples'}), d),
        'as couples forward & back',
      );
      expect(
        renderer.displayMoveName('forward_and_back', d),
        'forward and back',
      );
    });

    test('a name for forward and back never renames long lines', () {
      final d = Dialect(name: 'D', moves: {'forward_and_back': 'in and out'});
      expect(renderer.render(Figure(move: 'long_lines'), d), 'long lines');
      expect(
        renderer.renderSummary(Figure(move: 'long_lines'), d),
        'long lines forward & back',
      );
      expect(renderer.displayMoveName('long_lines', d), 'long lines');
      expect(
        renderer.render(fab({'formation': 'asCouples'}), d),
        'as couples in and out',
      );
      expect(renderer.displayMoveName('forward_and_back', d), 'in and out');
    });

    test('a wording for long lines applies to long lines only', () {
      final d = Dialect(
        name: 'D',
        moveWordings: {'long_lines': 'everyone {move} up'},
      );
      expect(
        renderer.render(Figure(move: 'long_lines'), d),
        'everyone long lines up',
      );
      expect(
        renderer.render(fab({'formation': 'asCouples'}), d),
        'as couples forward & back',
      );
    });

    test('a wording for forward and back never words long lines', () {
      final d = Dialect(
        name: 'D',
        moveWordings: {'forward_and_back': 'all {formation} {move} now'},
      );
      expect(renderer.render(Figure(move: 'long_lines'), d), 'long lines');
      expect(
        renderer.render(fab({'formation': 'asCouples'}), d),
        'all as couples forward & back now',
      );
    });

    test('a wording for long lines starts from its own name', () {
      expect(renderer.moveWordingTemplate('long_lines'), '{move}');
      expect(
        renderer.moveWordingTemplate('forward_and_back'),
        '{formation} {move}',
      );
    });
  });

  group('free text reads the displayed line back', () {
    Figure read(String text) => parseFreeTextFigureEntry(text).single;

    test('every formation, both directions', () {
      for (final formation in forwardAndBackFormations) {
        for (final goBack in [true, false]) {
          final figure = fab({
            'formation': formation,
            if (!goBack) 'goBack': false,
          });
          final text = renderer.renderSummary(figure, canonical);
          final f = read(text);
          expect(f.move, tax.resolvedMoveId(figure), reason: text);
          expect(tax.effectiveParams(f)['formation'], formation, reason: text);
          expect(tax.effectiveParams(f)['goBack'], goBack, reason: text);
        }
      }
    });

    test('spelled with "and", in any case, with a full stop', () {
      final f = read('LINES OF SIX Forward And Back.');
      expect(f.move, 'forward_and_back');
      expect(f.params, {'formation': 'linesOfSix'});
      expect(read('in a ring forward').params, {
        'formation': 'inARing',
        'goBack': false,
      });
    });

    test('a count on the line is its beats', () {
      expect(read('(8) as couples forward & back').params, {
        'formation': 'asCouples',
        'beats': 8,
      });
    });

    test("under the dialect's name for the move", () {
      final d = Dialect(
        name: 'D',
        moves: const {'forward_and_back': 'in and out'},
      );
      final figure = fab({'formation': 'linesOfThree'});
      final text = renderer.renderSummary(figure, d);
      expect(text, 'lines of three in and out');
      final f = parseFreeTextFigureEntry(text, dialect: d).single;
      expect(f.move, 'forward_and_back');
      expect(f.params, {'formation': 'linesOfThree'});
    });

    test('a bare forward and back is a long lines', () {
      final f = read('forward and back');
      expect(f.move, 'long_lines');
      expect(f.params, isEmpty);
    });

    test('a formation it does not offer stays custom', () {
      expect(read('lines of seven forward & back').isCustom, isTrue);
      expect(read('in squares backward').isCustom, isTrue);
    });
  });

  group('a matrix column saved on long lines while it was a move', () {
    final now = DateTime.utc(2026, 11, 13);
    Dance dance(String id, List<Figure> figures) => Dance(
      id: id,
      title: id,
      figures: figures,
      createdAt: now,
      updatedAt: now,
      formation: const Formation(FormationShape.dupleImproper),
    );

    test('still matches long lines, and no other formation', () {
      const config = MatrixColumnConfig(
        parameterized: [
          ParameterizedColumn(
            id: 'param:forward-only',
            baseMove: 'long_lines',
            params: {'goBack': false},
          ),
        ],
      );
      final matrix = buildProgramMatrix([
        dance('a', [
          Figure(move: 'long_lines', params: {'goBack': false}),
        ]),
        dance('b', [
          fab({'formation': 'asCouples', 'goBack': false}),
        ]),
      ], config: config);
      expect(matrix.rows[0].presentMoveIds, {'param:forward-only'});
      expect(matrix.rows[1].presentMoveIds, {'forward_and_back'});
    });

    test('as a compound step too', () {
      const config = MatrixColumnConfig(
        compound: [
          CompoundColumn(
            id: 'compound:lines-swing',
            steps: [
              StepMatcher(move: 'long_lines'),
              StepMatcher(move: 'swing'),
            ],
          ),
        ],
      );
      final matrix = buildProgramMatrix([
        dance('a', [Figure(move: 'long_lines'), Figure(move: 'swing')]),
        dance('b', [
          fab({'formation': 'inARing'}),
          Figure(move: 'swing'),
        ]),
      ], config: config);
      expect(matrix.rows[0].presentMoveIds, contains('compound:lines-swing'));
      expect(
        matrix.rows[1].presentMoveIds,
        isNot(contains('compound:lines-swing')),
      );
    });
  });

  test('the long lines matrix column follows forward and back', () {
    // Where it stood while it was a move: forward and back took its place.
    final catalog = [for (final c in builtInColumnCatalog(tax)) c.moveId];
    expect(
      catalog.indexOf('long_lines'),
      catalog.indexOf('forward_and_back') + 1,
    );
    final now = DateTime.utc(2026, 11, 13);
    final matrix = buildProgramMatrix([
      Dance(
        id: 'a',
        title: 'a',
        figures: [
          Figure(move: 'long_lines'),
          fab({'formation': 'asCouples'}),
          Figure(move: 'see_saw'),
          Figure(move: 'zig_zag'),
        ],
        createdAt: now,
        updatedAt: now,
        formation: const Formation(FormationShape.dupleImproper),
      ),
    ]);
    final ids = [for (final c in matrix.columns) c.moveId];
    expect(ids.indexOf('long_lines'), ids.indexOf('forward_and_back') + 1);
    expect(ids.indexOf('long_lines'), lessThan(ids.indexOf('zig_zag')));
    expect(ids.last, 'see_saw');
  });

  test('a long lines matrix column is named by its own dialect name', () {
    const column = MatrixColumn(
      moveId: 'long_lines',
      kind: MatrixColumnKind.known,
    );
    expect(
      matrixColumnLabel(
        column,
        tax,
        Dialect(name: 'D', moves: const {'forward_and_back': 'in and out'}),
      ),
      'long lines',
    );
    expect(
      matrixColumnLabel(
        column,
        tax,
        Dialect(name: 'D', moves: const {'long_lines': 'lines'}),
      ),
      'lines',
    );
  });

  test('a long lines keeps the snippet signature it had as a move', () {
    // Walkthrough snippets are stored under this key: a change would orphan
    // every one saved for long lines before taxonomy v39.
    expect(
      figureSnippetSignature(Figure(move: 'long_lines'), tax),
      'long_lines',
    );
    expect(
      figureSnippetSignature(
        Figure(move: 'long_lines', params: {'goBack': false}),
        tax,
      ),
      'long_lines',
    );
    // Stored as long lines, so it shares long lines' snippets.
    expect(figureSnippetSignature(fab(), tax), 'long_lines');
    expect(
      figureSnippetSignature(fab({'formation': 'asCouples'}), tax),
      'forward_and_back(formation=ascouples)',
    );
    expect(
      figureSnippetSignature(
        Figure(move: 'long_lines', params: {'formation': 'inARing'}),
        tax,
      ),
      'forward_and_back(formation=inaring)',
    );
  });

  group('a long lines never stores its formation', () {
    // A build before taxonomy v39 knows no `formation`: its validateFigure
    // rejects the key, and drops a synced shorthand holding such a figure.
    test('the pin is dropped, other params and other aliases kept', () {
      expect(
        tax.withoutListedAliasPins('long_lines', const {
          'formation': 'longLines',
          'goBack': false,
        }),
        {'goBack': false},
      );
      final kept = {'formation': 'asCouples'};
      expect(
        identical(tax.withoutListedAliasPins('long_lines', kept), kept),
        isTrue,
      );
      final seesaw = {'shoulder': 'left'};
      expect(
        identical(tax.withoutListedAliasPins('see_saw', seesaw), seesaw),
        isTrue,
      );
    });

    test('a dance write routes to long lines and drops the pin', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dances = DanceRepository(db, tax);
      await dances.create(
        sampleDance(
          id: 'fab',
          figures: [
            testFigure(
              move: 'forward_and_back',
              params: {'formation': 'longLines', 'goBack': false, 'beats': 4},
            ),
            testFigure(
              move: 'long_lines',
              params: {'formation': 'longLines', 'beats': 8},
            ),
            fab({'formation': 'asCouples', 'beats': 8}),
          ],
        ),
      );
      final stored =
          ((await dances.getById('fab'))!.figuresSource as DecodedFigures)
              .figures;
      expect(stored.map((f) => f.move), [
        'long_lines',
        'long_lines',
        'forward_and_back',
      ]);
      expect(stored[0].params, {'goBack': false, 'beats': 4});
      expect(stored[1].params, {'beats': 8});
      expect(stored[2].params, {'formation': 'asCouples', 'beats': 8});
    });

    test('free text reads a displayed long lines without it', () {
      // Only the display read-back reads this line (the grammar reads long
      // lines' own wording itself), and it reads a long lines.
      final d = Dialect(
        name: 'D',
        moves: const {'forward_and_back': 'in and out'},
      );
      final f = parseFreeTextFigureEntry(
        'long lines in and out',
        dialect: d,
      ).single;
      expect(f.move, 'long_lines');
      expect(f.params, isEmpty);
    });
  });

  test('a note repeating long lines is its own name, not left unread', () {
    final f = parseFreeTextFigureEntry(
      'long lines forward and back (long lines)',
    ).single;
    expect(f.move, 'long_lines');
    expect(tax.effectiveParams(f)['goBack'], isTrue);
  });

  test('a matrix column saved on long lines ranks as on its target', () {
    // Saved on the alias, it carries the pin: as specific as the same column
    // saved on forward and back with the pin.
    final now = DateTime.utc(2026, 11, 13);
    const config = MatrixColumnConfig(
      parameterized: [
        // Listed first, so a tie would go to it.
        ParameterizedColumn(id: 'param:fab-any', baseMove: 'forward_and_back'),
        ParameterizedColumn(id: 'param:any-lines', baseMove: 'long_lines'),
      ],
    );
    final matrix = buildProgramMatrix([
      Dance(
        id: 'a',
        title: 'a',
        figures: [testFigure(move: 'long_lines')],
        createdAt: now,
        updatedAt: now,
        formation: const Formation(FormationShape.dupleImproper),
      ),
    ], config: config);
    expect(matrix.rows.single.presentMoveIds, {'param:any-lines'});
  });

  test('long lines wordings offer no formation slot or condition', () {
    final names = [
      for (final n
          in renderer.moveWordingVocabulary('long_lines', canonical).names)
        n.name,
    ];
    expect(names, isNot(contains('formation')));
    final fabNames = [
      for (final n
          in renderer
              .moveWordingVocabulary('forward_and_back', canonical)
              .names)
        n.name,
    ];
    expect(fabNames, contains('formation'));
  });

  test('a copy of long lines is a long lines, not a forward and back', () {
    final seed = userFigureSeedFromMove(tax, 'long_lines')!;
    expect(seed.template, '{move}');
    expect(seed.copiedFrom, 'long_lines');
    expect(seed.params.map((p) => p.key), isNot(contains('formation')));
  });

  group('a matrix column is saved as long lines when it is one', () {
    test('a forward and back column stating long lines', () {
      final saved = savedMatrixConstraint('forward_and_back', const {
        'formation': 'longLines',
        'goBack': false,
      }, tax);
      expect(saved.move, 'long_lines');
      expect(saved.params, {'goBack': false});
    });

    test('but not one that leaves the formation open, or names another', () {
      for (final params in [
        const <String, Object?>{},
        const {'formation': 'asCouples'},
      ]) {
        final saved = savedMatrixConstraint('forward_and_back', params, tax);
        expect(saved.move, 'forward_and_back', reason: '$params');
        expect(saved.params, params);
      }
      final swing = savedMatrixConstraint('swing', const {'who': 'x'}, tax);
      expect(swing.move, 'swing');
    });
  });

  test('a switch of your own figure to forward and back in long lines '
      'stores a long lines', () {
    // A shorthand or default list holding it is not routed on write as a
    // dance is, and a build before v39 reads neither the move nor the key.
    final mine = UserFigureDefinition(
      template: '{formation} {move}',
      defaultBeats: 8,
      params: [
        UserFigureParam(
          key: 'formation',
          kind: ParamKind.choice,
          choices: [
            UserFigureChoice(id: 'll', label: 'long lines'),
            UserFigureChoice(id: 'ring', label: 'in a ring'),
          ],
        ),
      ],
    );
    final catalog = UserFigureCatalog.fromEntries([
      UserGlossaryEntry(
        id: 'mine',
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: 'forward and back',
        definition: 'Mine.',
        description: 'Mine.',
        payload: mine.toJson(),
        createdAt: DateTime.utc(2026),
      ),
    ]);
    final mineRenderer = FigureRenderer(tax, userFigures: catalog);
    Figure use(String choice) {
      final draft = userFigureUseFigure(
        id: 'mine',
        args: {'formation': choice},
        text: 'placeholder',
      );
      return userFigureUseFigure(
        id: 'mine',
        args: {'formation': choice},
        text: mineRenderer.renderUserFigureCanonical(draft)!,
      );
    }

    final switched = switchUserFigureUsesIn(
      [use('ll'), use('ring')],
      'mine',
      mine,
      UserFigureSwitch(
        target: 'forward_and_back',
        params: {'formation': 'formation'},
        choices: {
          'formation': {'ll': 'longLines', 'ring': 'inARing'},
        },
      ),
      tax,
      mineRenderer,
    );
    expect(switched.map((f) => f.move), ['long_lines', 'forward_and_back']);
    expect(switched[0].params, {'beats': 8});
    expect(switched[1].params, {'formation': 'inARing', 'beats': 8});
  });

  test('a search for the long lines id is never a dialect name', () {
    // A dialect may call another move "long_lines"; the id still searches
    // long lines, as it did when long lines was a move.
    final clash = Dialect(name: 'Clash', moves: {'swing': 'long_lines'});
    final compiler = FilterCompiler(clash, null, tax);
    expect(compiler.compile(FigureFilter.leaf('long_lines')).binds, [
      'long_lines',
    ]);
  });
}
