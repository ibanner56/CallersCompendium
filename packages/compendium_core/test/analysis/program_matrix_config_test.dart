import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13);

  Dance dance(String id, String title, List<Figure> figures) => Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
    formation: const Formation(FormationShape.dupleImproper),
  );

  Figure move(String id) => invalidTestFigure(
    move: id,
    reason: 'unknown move ids each get their own matrix column',
  );
  Figure swing([String? who]) =>
      testFigure(move: 'swing', params: {'who': ?who});
  Figure doSiDo() => testFigure(move: 'do_si_do', params: const {});
  Figure hey([String? length]) =>
      testFigure(move: 'hey', params: {'length': ?length});

  List<String> ids(ProgramMatrix m) => m.columns.map((c) => c.moveId).toList();

  // A representative program exercising every built-in column kind that the
  // config can act on: split (swing partner/neighbor, hey half/full), known
  // (do_si_do), and unknown (zebra_move), across three dances so program-debut
  // and collision maps are non-trivial.
  List<Dance> representativeProgram() => [
    dance('d1', 'A', [doSiDo(), swing('partners')]),
    dance('d2', 'B', [doSiDo(), swing('neighbors')]),
    dance('d3', 'C', [hey('full'), move('zebra_move')]),
  ];

  group('empty config reproduces today\'s matrix (golden regression)', () {
    test('field-by-field snapshot of the default build', () {
      final matrix = buildProgramMatrix(representativeProgram());

      // Columns: id + kind, in emission order. Any leak of config-application
      // logic into the empty (default) path — a drop, a reorder — changes this.
      expect(ids(matrix), [
        'swing:partner',
        'swing:neighbor',
        'do_si_do',
        'hey:full',
        'zebra_move',
      ]);
      expect(matrix.columns.map((c) => c.kind).toList(), [
        MatrixColumnKind.split,
        MatrixColumnKind.split,
        MatrixColumnKind.known,
        MatrixColumnKind.split,
        MatrixColumnKind.unknown,
      ]);

      // Per-row presence + first figure.
      expect(matrix.rows.map((r) => r.presentMoveIds.toSet()).toList(), [
        {'swing:partner', 'do_si_do'},
        {'do_si_do', 'swing:neighbor'},
        {'hey:full', 'zebra_move'},
      ]);
      expect(matrix.rows.map((r) => r.firstMoveId).toList(), [
        'do_si_do',
        'do_si_do',
        'hey:full',
      ]);

      // Program-debut row per move.
      expect(matrix.programDebutRowByMove, {
        'swing:partner': 0,
        'do_si_do': 0,
        'swing:neighbor': 1,
        'hey:full': 2,
        'zebra_move': 2,
      });

      // Sample collision flags: do_si_do is present in adjacent d1/d2 and
      // collides; swing:partner is only in d1 and does not.
      final doSiDo0 = ids(matrix).indexOf('do_si_do');
      expect(matrix.isCollision(0, doSiDo0), isTrue);
      expect(matrix.isCollision(1, doSiDo0), isTrue);
      final partner = ids(matrix).indexOf('swing:partner');
      expect(matrix.isCollision(0, partner), isFalse);
    });

    test('explicit empty config is identical to no config, field-by-field', () {
      final program = representativeProgram();
      final a = buildProgramMatrix(program);
      final b = buildProgramMatrix(program, config: MatrixColumnConfig.empty);

      expect(a.columns, b.columns);
      expect(a.rows, b.rows);
      expect(a.programDebutRowByMove, b.programDebutRowByMove);
      expect(a.collisionMode, b.collisionMode);
    });
  });

  group('config honours built-in hide / reorder (display only)', () {
    test('hidden drops exactly that column, nothing else', () {
      final matrix = buildProgramMatrix(
        representativeProgram(),
        config: const MatrixColumnConfig(hidden: {'do_si_do'}),
      );
      expect(ids(matrix), [
        'swing:partner',
        'swing:neighbor',
        'hey:full',
        'zebra_move',
      ]);
    });

    test('order moves listed ids first, unlisted keep derived order after', () {
      final matrix = buildProgramMatrix(
        representativeProgram(),
        config: const MatrixColumnConfig(order: ['zebra_move', 'do_si_do']),
      );
      expect(ids(matrix), [
        'zebra_move',
        'do_si_do',
        'swing:partner',
        'swing:neighbor',
        'hey:full',
      ]);
    });

    test('hide + reorder compose; analysis maps are untouched by display', () {
      final matrix = buildProgramMatrix(
        representativeProgram(),
        config: const MatrixColumnConfig(
          hidden: {'swing:neighbor'},
          order: ['do_si_do'],
        ),
      );
      expect(ids(matrix), [
        'do_si_do',
        'swing:partner',
        'hey:full',
        'zebra_move',
      ]);
      // Debut map still keys off every analysed move, including the hidden
      // column — display filtering never rewrote it.
      expect(matrix.programDebutRowByMove['swing:neighbor'], 1);
    });

    test('ids in order/hidden not present in the matrix are inert', () {
      final matrix = buildProgramMatrix(
        representativeProgram(),
        config: const MatrixColumnConfig(
          hidden: {'not_a_move'},
          order: ['also_absent', 'do_si_do'],
        ),
      );
      expect(ids(matrix), [
        'do_si_do',
        'swing:partner',
        'swing:neighbor',
        'hey:full',
        'zebra_move',
      ]);
    });
  });

  group('matrixColumnLabel honours renames', () {
    const doSiDoCol = MatrixColumn(
      moveId: 'do_si_do',
      kind: MatrixColumnKind.known,
    );

    test('a rename entry overrides the default label', () {
      const config = MatrixColumnConfig(renames: {'do_si_do': 'Dosido'});
      expect(
        matrixColumnLabel(doSiDoCol, contraTaxonomy, Dialect.canonical),
        isNot('Dosido'),
      );
      expect(
        matrixColumnLabel(
          doSiDoCol,
          contraTaxonomy,
          Dialect.canonical,
          config: config,
        ),
        'Dosido',
      );
    });

    test('parameterized/compound columns label from renames, else raw id', () {
      const paramCol = MatrixColumn(
        moveId: 'param:abc',
        kind: MatrixColumnKind.parameterized,
      );
      expect(
        matrixColumnLabel(paramCol, contraTaxonomy, Dialect.canonical),
        'param:abc',
      );
      expect(
        matrixColumnLabel(
          paramCol,
          contraTaxonomy,
          Dialect.canonical,
          config: const MatrixColumnConfig(renames: {'param:abc': 'My Swing'}),
        ),
        'My Swing',
      );
    });
  });

  group('codec round-trips and rejects malformed input', () {
    test('round-trips a full config incl. parameterized/compound', () {
      const config = MatrixColumnConfig(
        order: ['swing:partner', 'param:1', 'do_si_do'],
        hidden: {'hey:full'},
        renames: {'do_si_do': 'Dosido'},
        parameterized: [
          ParameterizedColumn(
            id: 'param:1',
            baseMove: 'swing',
            params: {'who': 'partners'},
          ),
        ],
        compound: [
          CompoundColumn(
            id: 'compound:1',
            steps: [
              StepMatcher(move: 'swing', params: {'who': 'partners'}),
            ],
          ),
        ],
      );
      final decoded = MatrixColumnConfig.decode(config.toJson());
      expect(decoded, config);
    });

    test('null decodes to empty', () {
      expect(MatrixColumnConfig.decode(null), MatrixColumnConfig.empty);
    });

    test('dangling built-in ids are kept inert, not rejected', () {
      final decoded = MatrixColumnConfig.decode({
        'order': ['ghost_move'],
        'hidden': ['also_gone'],
      });
      expect(decoded.order, ['ghost_move']);
      expect(decoded.hidden, {'also_gone'});
    });

    test('non-map input throws', () {
      expect(
        () => MatrixColumnConfig.decode('nope'),
        throwsA(isA<MatrixColumnConfigFormatException>()),
      );
    });

    test('wrong value types throw', () {
      expect(
        () => MatrixColumnConfig.decode({'order': 'not-a-list'}),
        throwsA(isA<MatrixColumnConfigFormatException>()),
      );
      expect(
        () => MatrixColumnConfig.decode({
          'order': [1, 2],
        }),
        throwsA(isA<MatrixColumnConfigFormatException>()),
      );
    });

    test('a mis-namespaced custom id is rejected', () {
      expect(
        () => MatrixColumnConfig.decode({
          'parameterized': [
            {'id': 'swing', 'baseMove': 'swing'},
          ],
        }),
        throwsA(isA<MatrixColumnConfigFormatException>()),
      );
    });

    test('a duplicate custom id across lists is rejected', () {
      expect(
        () => MatrixColumnConfig.decode({
          'parameterized': [
            {'id': 'param:dup', 'baseMove': 'swing'},
          ],
          'compound': [
            {'id': 'param:dup', 'steps': <Object?>[]},
          ],
        }),
        throwsA(isA<MatrixColumnConfigFormatException>()),
      );
    });

    test('tryDecode returns null on malformed, config on valid', () {
      expect(MatrixColumnConfig.tryDecode('nope'), isNull);
      expect(MatrixColumnConfig.tryDecode(null), MatrixColumnConfig.empty);
      expect(
        MatrixColumnConfig.tryDecode({
          'hidden': ['do_si_do'],
        }),
        const MatrixColumnConfig(hidden: {'do_si_do'}),
      );
    });
  });

  group('builtInColumnCatalog', () {
    test('enumerates catalog ids that a built matrix\'s ids are a subset of', () {
      final catalog = builtInColumnCatalog(
        contraTaxonomy,
      ).map((c) => c.moveId).toSet();
      // Every BUILT-IN column a real build emits must be a known catalog id, so
      // a config editor keyed off the catalog lines up with any built matrix.
      // Unknown moves (kind == unknown) are per-program and never cataloged.
      final builtInIds = buildProgramMatrix(representativeProgram()).columns
          .where((c) => c.kind != MatrixColumnKind.unknown)
          .map((c) => c.moveId)
          .toSet();
      expect(builtInIds.difference(catalog), isEmpty);
      // Spot-check representative kinds are present.
      expect(catalog, containsAll(['swing:partner', 'hey:full', customMove]));
    });
  });
}
