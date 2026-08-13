import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13);

  Dance dance(
    String id,
    String title,
    List<Figure> figures, {
    Formation? formation,
  }) => Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
    formation: formation ?? const Formation(FormationShape.dupleImproper),
  );

  Figure move(String id) => invalidTestFigure(
    move: id,
    reason:
        'unknown move ids are the subject here: they must each get their own matrix column',
  );
  Figure swing([String? who]) =>
      testFigure(move: 'swing', params: {'who': ?who});
  Figure swingWithPrefix(String? who, String prefix) =>
      testFigure(move: 'swing', params: {'who': ?who, 'prefix': prefix});
  Figure meltdownSwing([String? who]) =>
      testFigure(move: 'meltdown_swing', params: {'who': ?who});
  Figure allemande([String? who]) =>
      testFigure(move: 'allemande', params: {'who': ?who});
  Figure chain([String? who]) =>
      testFigure(move: 'chain', params: {'who': ?who});
  Figure seeSaw() => testFigure(move: 'see_saw', params: const {});
  Figure doSiDo() => testFigure(move: 'do_si_do', params: const {});
  Figure hey([String? length]) =>
      testFigure(move: 'hey', params: {'length': ?length});
  Figure custom(String text) =>
      testFigure(move: customMove, params: {'text': text});

  List<String> ids(ProgramMatrix m) => m.columns.map((c) => c.moveId).toList();
  int colOf(ProgramMatrix m, String moveId) =>
      m.columns.indexWhere((c) => c.moveId == moveId);

  group('buildProgramMatrix — column discovery & order', () {
    test('columns are only the moves present (plus swing baseline)', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing(), move('balance')]),
      ]);
      expect(ids(matrix), ['swing:partner', 'swing:neighbor', 'balance']);
      expect(matrix.columns[0].kind, MatrixColumnKind.split);
      expect(matrix.columns[2].kind, MatrixColumnKind.known);
    });

    test('columns follow taxonomy canonical order, not encounter order', () {
      // do_si_do comes before shoulder_round in the taxonomy; feed them in the
      // opposite order and across dances.
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('shoulder_round')]),
        dance('d2', 'B', [move('do_si_do'), swing()]),
      ]);
      expect(ids(matrix), [
        'swing:partner',
        'swing:neighbor',
        'do_si_do',
        'shoulder_round',
      ]);
    });

    test('unknown move ids get their own columns after known, sorted', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('zebra_move'), swing(), move('aardvark')]),
      ]);
      expect(ids(matrix), [
        'swing:partner',
        'swing:neighbor',
        'aardvark',
        'zebra_move',
      ]);
      expect(matrix.columns[0].kind, MatrixColumnKind.split);
      expect(matrix.columns[2].kind, MatrixColumnKind.unknown);
      expect(matrix.columns[3].kind, MatrixColumnKind.unknown);
    });

    test('all custom figures collapse into one trailing custom column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [custom('scoop them up'), swing()]),
        dance('d2', 'B', [custom('a different custom move')]),
      ]);
      expect(ids(matrix), ['swing:partner', 'swing:neighbor', customMove]);
      expect(matrix.columns.last.kind, MatrixColumnKind.custom);
      expect(matrix.columns.last.isCustom, isTrue);
    });
  });

  group('buildProgramMatrix — swing role split', () {
    test('a swing with no who defaults to the partner column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
      ]);
      expect(colOf(matrix, 'swing:partner'), isNonNegative);
      expect(matrix.rows.single.presentMoveIds, contains('swing:partner'));
    });

    test('who values map to their role-group columns', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing('neighbors')]),
        dance('d2', 'B', [swing('shadows'), swing('secondShadows')]),
        dance('d3', 'C', [swing('role1s'), swing('role2s')]),
        dance('d4', 'D', [swing('ones'), swing('twos')]),
        dance('d5', 'E', [swing('firstCorners'), swing('secondCorners')]),
        dance('d6', 'F', [swing('sameRoles')]),
      ]);
      final present = ids(matrix).toSet();
      expect(present, containsAll(['swing:partner', 'swing:neighbor']));
      expect(
        present,
        containsAll([
          'swing:shadow',
          'swing:larks',
          'swing:robins',
          'swing:ones',
          'swing:twos',
          'swing:corners',
          'swing:same',
        ]),
      );
      // shadows + secondShadows share one column; firstCorners + secondCorners
      // share one column.
      expect(present.where((k) => k == 'swing:shadow'), hasLength(1));
      expect(present.where((k) => k == 'swing:corners'), hasLength(1));
    });

    test('an unusual who lands in the other bucket', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing('everyone')]),
      ]);
      expect(colOf(matrix, 'swing:other'), isNonNegative);
    });

    test(
      'partner + neighbor baseline is always present; others present-only',
      () {
        // No dance swings partner or neighbor, yet both baseline columns appear;
        // no other swing columns leak in.
        final matrix = buildProgramMatrix([
          dance('d1', 'A', [swing('role1s')]),
        ]);
        final swingCols = ids(matrix).where((k) => k.startsWith('swing:'));
        expect(swingCols, ['swing:partner', 'swing:neighbor', 'swing:larks']);
      },
    );

    test('baseline appears even when every dance is figure-less', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'Stub', const []),
        dance('d2', 'Stub2', const []),
      ]);
      expect(ids(matrix), ['swing:partner', 'swing:neighbor']);
      expect(matrix.isEmpty, isFalse);
      expect(matrix.rows, hasLength(2));
    });

    test('swing columns are ordered partner, neighbor, then the rest', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing('sameRoles'), swing('role2s'), swing('ones')]),
      ]);
      final swingCols = ids(
        matrix,
      ).where((k) => k.startsWith('swing:')).toList();
      expect(swingCols, [
        'swing:partner',
        'swing:neighbor',
        'swing:robins',
        'swing:ones',
        'swing:same',
      ]);
    });
  });

  group('buildProgramMatrix — hey length split', () {
    test('a hey with no length defaults to the half column, present-only', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [hey()]),
      ]);
      final heyCols = ids(matrix).where((k) => k.startsWith('hey:'));
      expect(heyCols, ['hey:half']); // no full baseline
    });

    test('length values collapse into half/full groups, half before full', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [hey('lessThanHalf')]),
        dance('d2', 'B', [hey('betweenHalfAndFull')]),
        dance('d3', 'C', [hey('full')]),
      ]);
      final heyCols = ids(matrix).where((k) => k.startsWith('hey:')).toList();
      expect(heyCols, ['hey:half', 'hey:full']);
    });

    test('a full-only program shows only the full-hey column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [hey('full')]),
      ]);
      expect(ids(matrix).where((k) => k.startsWith('hey:')), ['hey:full']);
    });

    test('dolphin_hey is NOT split', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('dolphin_hey')]),
      ]);
      expect(colOf(matrix, 'dolphin_hey'), isNonNegative);
      expect(ids(matrix).where((k) => k.startsWith('hey:')), isEmpty);
    });
  });

  group('buildProgramMatrix — allemande/chain role split (issue #933)', () {
    test('allemande with no who defaults to the neighbor column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [allemande()]),
      ]);
      expect(colOf(matrix, 'allemande:neighbor'), isNonNegative);
    });

    test('chain with no who defaults to the robins column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [chain()]),
      ]);
      expect(colOf(matrix, 'chain:robins'), isNonNegative);
    });

    test('allemande/chain have NO baseline — present-only', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
      ]);
      expect(ids(matrix).where((k) => k.startsWith('allemande:')), isEmpty);
      expect(ids(matrix).where((k) => k.startsWith('chain:')), isEmpty);
    });

    test('lark allemande and robin allemande are DIFFERENT columns', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [allemande('role1s')]),
        dance('d2', 'B', [allemande('role2s')]),
      ]);
      expect(ids(matrix), containsAll(['allemande:larks', 'allemande:robins']));
    });

    test('gent chain and lady chain are DIFFERENT columns', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [chain('role1s')]),
        dance('d2', 'B', [chain('role2s')]),
      ]);
      expect(ids(matrix), containsAll(['chain:larks', 'chain:robins']));
    });

    test('an unusual allemande who lands in the other bucket', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [allemande('everyone')]),
      ]);
      expect(colOf(matrix, 'allemande:other'), isNonNegative);
    });

    test(
      'allemande/chain columns are present-only, role order matches swing',
      () {
        final matrix = buildProgramMatrix([
          dance('d1', 'A', [
            allemande('sameRoles'),
            allemande('role2s'),
            allemande('ones'),
          ]),
        ]);
        final allemandeCols = ids(
          matrix,
        ).where((k) => k.startsWith('allemande:')).toList();
        expect(allemandeCols, [
          'allemande:robins',
          'allemande:ones',
          'allemande:same',
        ]);
      },
    );
  });

  group('buildProgramMatrix — swing prefix split (issue #933)', () {
    test('a plain swing (prefix none) keeps its pre-existing key', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing('partners')]),
      ]);
      expect(ids(matrix), contains('swing:partner'));
      expect(ids(matrix).where((k) => k.contains(':partner:')), isEmpty);
    });

    test('a balance-prefixed swing gets its own sub-column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swingWithPrefix('partners', 'balance')]),
      ]);
      expect(colOf(matrix, 'swing:partner:balance'), isNonNegative);
      // The plain baseline column still appears (unconditional baseline,
      // maintainer decision), even though no dance has a plain partner swing.
      expect(colOf(matrix, 'swing:partner'), isNonNegative);
    });

    test('plain partner swing and balance-prefixed partner swing are '
        'DIFFERENT columns', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing('partners')]),
        dance('d2', 'B', [swingWithPrefix('partners', 'balance')]),
      ]);
      expect(
        ids(matrix),
        containsAll(['swing:partner', 'swing:partner:balance']),
      );
      // Each is present in exactly the dance that has it.
      final plain = colOf(matrix, 'swing:partner');
      final balance = colOf(matrix, 'swing:partner:balance');
      expect(matrix.isPresent(0, plain), isTrue);
      expect(matrix.isPresent(0, balance), isFalse);
      expect(matrix.isPresent(1, balance), isTrue);
    });

    test('a meltdown-prefixed swing (authored directly, not the alias) gets '
        'its own sub-column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swingWithPrefix('neighbors', 'meltdown')]),
      ]);
      expect(colOf(matrix, 'swing:neighbor:meltdown'), isNonNegative);
    });

    test('a NON-baseline role (larks) that is ALWAYS balance-prefixed shows '
        'ONLY the prefixed sub-column — no empty plain `swing:larks` column '
        'beside it (code review: the bare column is present-only for every '
        'non-baseline role, exactly like every other present-only column in '
        'this matrix — hey, allemande, chain — not a fixed baseline; only '
        'partner/neighbor get an unconditional bare column)', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swingWithPrefix('role1s', 'balance')]),
      ]);
      expect(colOf(matrix, 'swing:larks:balance'), isNonNegative);
      expect(ids(matrix), isNot(contains('swing:larks')));
    });

    test('once a role ALSO has a plain swing, its bare column appears '
        'alongside the prefixed one (present-only, keyed independently)', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [
          swing('role1s'),
          swingWithPrefix('role1s', 'balance'),
        ]),
      ]);
      expect(colOf(matrix, 'swing:larks'), isNonNegative);
      expect(colOf(matrix, 'swing:larks:balance'), isNonNegative);
    });

    test('the `meltdown_swing` ALIAS folds into the same swing:<role>:meltdown '
        'column as an explicit prefix=meltdown swing (issue #933) — not its '
        'own stray column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [meltdownSwing('partners')]),
        dance('d2', 'B', [swingWithPrefix('partners', 'meltdown')]),
      ]);
      expect(ids(matrix), contains('swing:partner:meltdown'));
      // Not present as its own raw alias-id column.
      expect(ids(matrix), isNot(contains('meltdown_swing')));
      // Both dances share the ONE column (the fold, not two distinct ones).
      expect(
        ids(matrix).where((k) => k == 'swing:partner:meltdown'),
        hasLength(1),
      );
      final col = colOf(matrix, 'swing:partner:meltdown');
      expect(matrix.isPresent(0, col), isTrue);
      expect(matrix.isPresent(1, col), isTrue);
    });

    test('meltdown_swing with no who defaults to the partner column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [meltdownSwing()]),
      ]);
      expect(colOf(matrix, 'swing:partner:meltdown'), isNonNegative);
    });
  });

  group('buildProgramMatrix — alias columns stay distinct (issue #933)', () {
    test('see_saw (alias of do_si_do, NOT split) keeps its own column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [seeSaw(), doSiDo()]),
      ]);
      expect(ids(matrix), containsAll(['see_saw', 'do_si_do']));
    });

    test(
      'an alias of a non-split move is classified `known`, not `unknown`',
      () {
        final matrix = buildProgramMatrix([
          dance('d1', 'A', [seeSaw()]),
        ]);
        final col = matrix.columns.firstWhere((c) => c.moveId == 'see_saw');
        expect(col.kind, MatrixColumnKind.known);
      },
    );
  });

  group('buildProgramMatrix — presence cells', () {
    test('presence is set exactly where a dance uses the move', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing(), move('balance')]),
        dance('d2', 'B', [swing()]),
      ]);
      final s = colOf(matrix, 'swing:partner');
      final balance = colOf(matrix, 'balance');

      expect(matrix.isPresent(0, s), isTrue);
      expect(matrix.isPresent(0, balance), isTrue);
      expect(matrix.isPresent(1, s), isTrue);
      expect(matrix.isPresent(1, balance), isFalse);
    });

    test('a move shared across dances is a single shared column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
        dance('d2', 'B', [swing()]),
      ]);
      final s = colOf(matrix, 'swing:partner');
      expect(
        matrix.columns.where((c) => c.moveId == 'swing:partner'),
        hasLength(1),
      );
      expect(matrix.isPresent(0, s), isTrue);
      expect(matrix.isPresent(1, s), isTrue);
    });

    test('a move repeated within a dance is a single boolean presence', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing(), move('balance'), swing()]),
      ]);
      expect(matrix.rows.single.presentMoveIds, {'swing:partner', 'balance'});
    });
  });

  group('buildProgramMatrix — first-figure highlight', () {
    test('flags each row first move and implies presence', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('balance'), swing()]),
        dance('d2', 'B', [swing('neighbors'), move('balance')]),
      ]);
      final partner = colOf(matrix, 'swing:partner');
      final neighbor = colOf(matrix, 'swing:neighbor');
      final balance = colOf(matrix, 'balance');

      expect(matrix.isFirst(0, balance), isTrue);
      expect(matrix.isFirst(0, partner), isFalse);
      // Second dance opens with a NEIGHBOR swing → highlight lands on that
      // split sub-column, not the partner baseline.
      expect(matrix.isFirst(1, neighbor), isTrue);
      expect(matrix.isFirst(1, partner), isFalse);
      expect(matrix.isFirst(1, balance), isFalse);

      expect(matrix.isPresent(0, balance), isTrue);
      expect(matrix.isPresent(1, neighbor), isTrue);
    });

    test('first-figure highlight lands on the correct hey length column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [hey('full'), move('balance')]),
      ]);
      final full = colOf(matrix, 'hey:full');
      expect(matrix.rows.single.firstMoveId, 'hey:full');
      expect(matrix.isFirst(0, full), isTrue);
    });

    test('first-figure works when the opening figure is custom', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [custom('big circle'), swing()]),
      ]);
      final customCol = matrix.columns.indexWhere((c) => c.isCustom);
      expect(matrix.rows.single.firstMoveId, customMove);
      expect(matrix.isFirst(0, customCol), isTrue);
      expect(matrix.isPresent(0, customCol), isTrue);
    });
  });

  group('buildProgramMatrix — program-debut highlight', () {
    test('debuts on the first row using a move, regardless of position', () {
      final matrix = buildProgramMatrix([
        // balance appears mid-dance here → this is its program debut.
        dance('d1', 'A', [swing(), move('balance')]),
        // balance opens this dance (its dance-first figure) but is NOT a debut.
        dance('d2', 'B', [move('balance'), swing('neighbors')]),
      ]);
      final balance = colOf(matrix, 'balance');

      expect(matrix.isProgramDebut(0, balance), isTrue);
      expect(matrix.isProgramDebut(1, balance), isFalse);
      // The dance-opening flag is independent: balance is d2's first figure.
      expect(matrix.isFirst(0, balance), isFalse);
      expect(matrix.isFirst(1, balance), isTrue);
    });

    test('a move used by a single dance debuts on that dance', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
        dance('d2', 'B', [move('balance')]),
      ]);
      final balance = colOf(matrix, 'balance');
      expect(matrix.isProgramDebut(0, balance), isFalse);
      expect(matrix.isProgramDebut(1, balance), isTrue);
    });

    test('each split sub-column debuts independently', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
        dance('d2', 'B', [swing('neighbors')]),
      ]);
      final partner = colOf(matrix, 'swing:partner');
      final neighbor = colOf(matrix, 'swing:neighbor');
      expect(matrix.isProgramDebut(0, partner), isTrue);
      expect(matrix.isProgramDebut(1, partner), isFalse);
      expect(matrix.isProgramDebut(1, neighbor), isTrue);
      expect(matrix.isProgramDebut(0, neighbor), isFalse);
    });

    test('the collapsed custom column debuts on its first appearance', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
        dance('d2', 'B', [custom('big circle')]),
        dance('d3', 'C', [custom('grand square')]),
      ]);
      final customCol = matrix.columns.indexWhere((c) => c.isCustom);
      expect(matrix.isProgramDebut(1, customCol), isTrue);
      expect(matrix.isProgramDebut(2, customCol), isFalse);
    });

    test('an unused swing baseline column has no debut', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [swing()]),
      ]);
      final neighbor = colOf(matrix, 'swing:neighbor');
      expect(matrix.isProgramDebut(0, neighbor), isFalse);
      expect(
        matrix.programDebutRowByMove.containsKey('swing:neighbor'),
        isFalse,
      );
    });

    test('figure-less rows contribute no debut', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'Stub', const []),
        dance('d2', 'B', [move('balance')]),
      ]);
      final balance = colOf(matrix, 'balance');
      expect(matrix.isProgramDebut(0, balance), isFalse);
      expect(matrix.isProgramDebut(1, balance), isTrue);
    });
  });

  group('buildProgramMatrix — edge cases', () {
    test('empty program has no rows and no columns', () {
      final matrix = buildProgramMatrix([]);
      expect(matrix.rows, isEmpty);
      expect(matrix.columns, isEmpty);
      expect(matrix.isEmpty, isTrue);
    });

    test('a figure-less dance produces a row; swing baseline still shows', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'Stub', const []),
        dance('d2', 'B', [swing()]),
      ]);
      expect(matrix.rows, hasLength(2));
      expect(matrix.rows[0].firstMoveId, isNull);
      expect(matrix.rows[0].presentMoveIds, isEmpty);
      expect(ids(matrix), ['swing:partner', 'swing:neighbor']);
    });

    test('a program with only figure-less dances still shows the baseline', () {
      // Per the confirmed behavior: the partner/neighbor swing baseline is
      // injected whenever there is at least one dance.
      final matrix = buildProgramMatrix([dance('d1', 'Stub', const [])]);
      expect(matrix.isEmpty, isFalse);
      expect(ids(matrix), ['swing:partner', 'swing:neighbor']);
      expect(matrix.rows, hasLength(1));
    });
  });

  group('buildProgramMatrix — half badge', () {
    test('rows carry the aligned half; null when no halves passed', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('balance')]),
        dance('d2', 'B', [move('balance')]),
      ]);
      expect(matrix.rows[0].half, isNull);
      expect(matrix.rows[1].half, isNull);
    });

    test('half is populated from the parallel halves list', () {
      final matrix = buildProgramMatrix(
        [
          dance('d1', 'A', [move('balance')]),
          dance('d2', 'B', [move('balance')]),
          dance('d3', 'C', [move('balance')]),
        ],
        halves: const [ProgramHalf.first, null, ProgramHalf.second],
      );
      expect(matrix.rows[0].half, ProgramHalf.first);
      expect(matrix.rows[1].half, isNull);
      expect(matrix.rows[2].half, ProgramHalf.second);
    });

    test('throws when halves length does not match dances', () {
      expect(
        () => buildProgramMatrix(
          [
            dance('d1', 'A', [move('balance')]),
            dance('d2', 'B', [move('balance')]),
          ],
          halves: const [ProgramHalf.first],
        ),
        throwsArgumentError,
      );
    });
  });

  group('buildProgramMatrix — formation', () {
    test('rows carry the dance\'s formation', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [
          move('balance'),
        ], formation: const Formation(FormationShape.becketCw)),
        dance('d2', 'B', [move('balance')]),
      ]);
      expect(matrix.rows[0].formation.shape, FormationShape.becketCw);
      expect(matrix.rows[1].formation.shape, FormationShape.dupleImproper);
    });

    test('preserves free-text formation detail', () {
      final matrix = buildProgramMatrix([
        dance(
          'd1',
          'A',
          [move('balance')],
          formation: const Formation(
            FormationShape.other,
            detail: 'double progression variant',
          ),
        ),
      ]);
      expect(
        matrix.rows[0].formation,
        const Formation(
          FormationShape.other,
          detail: 'double progression variant',
        ),
      );
    });

    test('MatrixRow equality/hashCode include formation', () {
      final base = MatrixRow(
        danceId: 'd1',
        title: 'A',
        firstMoveId: null,
        presentMoveIds: const {},
      );
      final sameFormation = MatrixRow(
        danceId: 'd1',
        title: 'A',
        firstMoveId: null,
        presentMoveIds: const {},
        formation: const Formation(FormationShape.dupleImproper),
      );
      final differentFormation = MatrixRow(
        danceId: 'd1',
        title: 'A',
        firstMoveId: null,
        presentMoveIds: const {},
        formation: const Formation(FormationShape.becketCw),
      );
      expect(base, sameFormation);
      expect(base.hashCode, sameFormation.hashCode);
      expect(base, isNot(differentFormation));
    });
  });

  group('matrixColumnLabel — split columns', () {
    MatrixColumn split(String base, String variant) => MatrixColumn(
      moveId: '$base:$variant',
      kind: MatrixColumnKind.split,
      baseMoveId: base,
      variant: variant,
    );

    String label(MatrixColumn c, [Dialect? d]) =>
        matrixColumnLabel(c, contraTaxonomy, d ?? Dialect.canonical);

    test('swing role labels under the canonical dialect', () {
      expect(label(split('swing', 'partner')), 'partner swing');
      expect(label(split('swing', 'neighbor')), 'neighbor swing');
      expect(label(split('swing', 'shadow')), 'shadow swing');
      expect(label(split('swing', 'ones')), 'ones swing');
      expect(label(split('swing', 'twos')), 'twos swing');
      expect(label(split('swing', 'corners')), 'corners swing');
      expect(label(split('swing', 'same')), 'same-role swing');
      expect(label(split('swing', 'other')), 'swing (other)');
    });

    test('hey length labels', () {
      expect(label(split('hey', 'half')), 'half hey');
      expect(label(split('hey', 'full')), 'full hey');
    });

    test('larks/robins honour a Larks & Robins role dialect', () {
      final larksRobins = Dialect(
        name: 'Larks & Robins',
        roles: const {
          'role1': RoleTerm('lark', plural: 'larks'),
          'role2': RoleTerm('robin', plural: 'robins'),
        },
      );
      expect(label(split('swing', 'larks'), larksRobins), 'lark swing');
      expect(label(split('swing', 'robins'), larksRobins), 'robin swing');
    });

    test('larks/robins honour a Gents & Ladies dialect', () {
      final gentsLadies = Dialect(
        name: 'Gents & Ladies',
        roles: const {
          'role1': RoleTerm('gent', plural: 'gents'),
          'role2': RoleTerm('lady', plural: 'ladies'),
        },
      );
      expect(label(split('swing', 'larks'), gentsLadies), 'gent swing');
      expect(label(split('swing', 'robins'), gentsLadies), 'lady swing');
    });

    test('the swing/hey move word honours a dialect move substitution', () {
      final dialect = Dialect(
        name: 'Test',
        moves: const {'swing': 'twirl', 'hey': 'reel'},
      );
      expect(label(split('swing', 'partner'), dialect), 'partner twirl');
      expect(label(split('hey', 'full'), dialect), 'full reel');
    });

    test('allemande/chain role labels under the canonical dialect '
        '(issue #933)', () {
      expect(label(split('allemande', 'neighbor')), 'neighbor allemande');
      expect(label(split('allemande', 'same')), 'same-role allemande');
      expect(label(split('allemande', 'other')), 'allemande (other)');
      expect(label(split('chain', 'ones')), 'ones chain');
      expect(label(split('chain', 'twos')), 'twos chain');
    });

    test('allemande/chain larks/robins honour a role dialect', () {
      final larksRobins = Dialect(
        name: 'Larks & Robins',
        roles: const {
          'role1': RoleTerm('lark', plural: 'larks'),
          'role2': RoleTerm('robin', plural: 'robins'),
        },
      );
      expect(label(split('allemande', 'larks'), larksRobins), 'lark allemande');
      expect(label(split('chain', 'robins'), larksRobins), 'robin chain');
    });

    test('a lark allemande and a robin allemande have DIFFERENT labels '
        '(issue #933 — the false-collision fix depends on this)', () {
      expect(
        label(split('allemande', 'larks')),
        isNot(label(split('allemande', 'robins'))),
      );
    });

    test('swing prefix headers ABBREVIATE balance (maintainer decision) but '
        'spell out meltdown (issue #933)', () {
      expect(label(split('swing', 'partner:balance')), 'partner bal & swing');
      expect(label(split('swing', 'neighbor:balance')), 'neighbor bal & swing');
      expect(
        label(split('swing', 'partner:meltdown')),
        'partner meltdown swing',
      );
    });

    test('a plain swing and a balance-prefixed swing of the SAME role have '
        'DIFFERENT labels (issue #933 — the false-collision fix depends on '
        'this)', () {
      expect(
        label(split('swing', 'partner')),
        isNot(label(split('swing', 'partner:balance'))),
      );
    });

    test('swing prefix headers honour a dialect move substitution', () {
      final dialect = Dialect(name: 'Test', moves: const {'swing': 'twirl'});
      expect(
        label(split('swing', 'partner:balance'), dialect),
        'partner bal & twirl',
      );
    });
  });

  group('matrixColumnLabel — non-split columns', () {
    const known = MatrixColumn(moveId: 'balance', kind: MatrixColumnKind.known);
    const customCol = MatrixColumn(
      moveId: customMove,
      kind: MatrixColumnKind.custom,
    );
    const unknown = MatrixColumn(
      moveId: 'zebra_move',
      kind: MatrixColumnKind.unknown,
    );

    test('known move uses its taxonomy display name by default', () {
      expect(
        matrixColumnLabel(known, contraTaxonomy, Dialect.canonical),
        'balance',
      );
    });

    test('applies a side-independent dialect move substitution', () {
      final dialect = Dialect(name: 'Test', moves: const {'balance': 'rock'});
      expect(matrixColumnLabel(known, contraTaxonomy, dialect), 'rock');
    });

    test('falls back to display name for %S side-dependent substitutions', () {
      final dialect = Dialect(
        name: 'Test',
        moves: const {'shoulder_round': '%S shoulder round'},
      );
      const col = MatrixColumn(
        moveId: 'shoulder_round',
        kind: MatrixColumnKind.known,
      );
      expect(matrixColumnLabel(col, contraTaxonomy, dialect), 'shoulder round');
    });

    test('custom column is labelled "Custom"', () {
      expect(
        matrixColumnLabel(customCol, contraTaxonomy, Dialect.canonical),
        'Custom',
      );
    });

    test('unknown move column shows its raw id', () {
      expect(
        matrixColumnLabel(unknown, contraTaxonomy, Dialect.canonical),
        'zebra_move',
      );
    });

    test(
      'an alias of a NON-split move is labelled under its OWN display name, '
      'not its target\'s (issue #933 — see_saw must not read as "do si do")',
      () {
        const seeSawCol = MatrixColumn(
          moveId: 'see_saw',
          kind: MatrixColumnKind.known,
        );
        const doSiDoCol = MatrixColumn(
          moveId: 'do_si_do',
          kind: MatrixColumnKind.known,
        );
        expect(
          matrixColumnLabel(seeSawCol, contraTaxonomy, Dialect.canonical),
          'see saw',
        );
        expect(
          matrixColumnLabel(doSiDoCol, contraTaxonomy, Dialect.canonical),
          'do si do',
        );
        // The load-bearing assertion: two figures a caller can tell apart
        // must not collapse to one header.
        expect(
          matrixColumnLabel(seeSawCol, contraTaxonomy, Dialect.canonical),
          isNot(
            matrixColumnLabel(doSiDoCol, contraTaxonomy, Dialect.canonical),
          ),
        );
      },
    );

    test('an alias column\'s dialect substitution is keyed by the CANONICAL '
        'move id, matching FigureRenderer.displayMoveName\'s rule', () {
      const seeSawCol = MatrixColumn(
        moveId: 'see_saw',
        kind: MatrixColumnKind.known,
      );
      final dialect = Dialect(
        name: 'Test',
        moves: const {'do_si_do': 'circle round'},
      );
      // A substitution keyed by the TARGET id still applies to the alias
      // column (matches displayMoveName's canonical-id lookup rule)...
      expect(
        matrixColumnLabel(seeSawCol, contraTaxonomy, dialect),
        'circle round',
      );
      // ...while a substitution keyed by the alias's OWN id does nothing,
      // since dialect.moves is a canonical-id map.
      final aliasKeyedDialect = Dialect(
        name: 'Test2',
        moves: const {'see_saw': 'circle round'},
      );
      expect(
        matrixColumnLabel(seeSawCol, contraTaxonomy, aliasKeyedDialect),
        'see saw',
      );
    });
  });

  group('isCollision — phrase mode (issue #582; opt-in via #962)', () {
    // A figure's phrase is derived from its cumulative beat offset under the
    // default 4x16 structure (A1 0-15, A2 16-31, B1 32-47, B2 48-63). `fig`
    // sets an explicit beat length so a move can be steered into a phrase.
    // Every buildProgramMatrix call below pins `collisionMode: phrase`
    // explicitly — these tests document and guard the ORIGINAL #582
    // behaviour, which #962 demoted to opt-in (exact-beat overlap is now the
    // default; see the "isCollision — exact-beat mode" group below).
    Figure fig(String id, int beats) =>
        testFigure(move: id, params: {'beats': beats});

    int colOfMove(ProgramMatrix m, String moveId) =>
        m.columns.indexWhere((c) => c.moveId == moveId);

    test('phraseLabelsByMove records the phrase each move starts in', () {
      final m = buildProgramMatrix([
        // balance A1 (beat 0), do_si_do B1 (beat 32).
        dance('d1', 'A', [fig('balance', 32), fig('do_si_do', 16)]),
      ]);
      expect(m.rows.first.phraseLabelsByMove['balance'], {'A1'});
      expect(m.rows.first.phraseLabelsByMove['do_si_do'], {'B1'});
    });

    test(
      'flags both cells when a move shares a phrase with the next dance',
      () {
        final balanceB1a = [fig('do_si_do', 32), fig('balance', 16)];
        final balanceB1b = [fig('circle', 32), fig('balance', 16)];
        final m = buildProgramMatrix([
          dance('d1', 'A', balanceB1a),
          dance('d2', 'B', balanceB1b),
        ], collisionMode: MatrixCollisionMode.phrase);
        final c = colOfMove(m, 'balance');
        expect(m.isCollision(0, c), isTrue);
        expect(m.isCollision(1, c), isTrue);
      },
    );

    test('does NOT flag the same move in a different phrase', () {
      final m = buildProgramMatrix([
        // balance in B1 (beat 32).
        dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 16)]),
        // balance in A1 (beat 0).
        dance('d2', 'B', [fig('balance', 16), fig('do_si_do', 16)]),
      ], collisionMode: MatrixCollisionMode.phrase);
      final c = colOfMove(m, 'balance');
      expect(m.isCollision(0, c), isFalse);
      expect(m.isCollision(1, c), isFalse);
    });

    test(
      'does NOT flag a same-phrase repeat that is not strictly adjacent',
      () {
        final balanceB1 = [fig('do_si_do', 32), fig('balance', 16)];
        final m = buildProgramMatrix([
          dance('d1', 'A', balanceB1),
          // Middle dance has no balance, so d1 and d3 are not neighbours.
          dance('d2', 'B', [fig('circle', 16)]),
          dance('d3', 'C', balanceB1),
        ], collisionMode: MatrixCollisionMode.phrase);
        final c = colOfMove(m, 'balance');
        expect(m.isCollision(0, c), isFalse);
        expect(m.isCollision(2, c), isFalse);
      },
    );

    test('flags a collision with either neighbour (above or below)', () {
      final balanceB1 = [fig('do_si_do', 32), fig('balance', 16)];
      final m = buildProgramMatrix([
        dance('d1', 'A', balanceB1),
        dance('d2', 'B', balanceB1),
        dance('d3', 'C', balanceB1),
      ], collisionMode: MatrixCollisionMode.phrase);
      final c = colOfMove(m, 'balance');
      // Middle row collides with both neighbours; ends collide with the middle.
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
      expect(m.isCollision(2, c), isTrue);
    });

    test('split (swing role) columns collide on same role + same phrase', () {
      // A partner swing landing in B2 (beat 48) in two adjacent dances.
      final swingB2 = [
        Figure(move: 'do_si_do', params: {'beats': 48}),
        swing(),
      ];
      final m = buildProgramMatrix([
        dance('d1', 'A', swingB2),
        dance('d2', 'B', swingB2),
      ], collisionMode: MatrixCollisionMode.phrase);
      final c = colOfMove(m, 'swing:partner');
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
    });

    test('different swing roles in the same phrase do NOT collide', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          swing('partners'),
        ]),
        dance('d2', 'B', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          swing('neighbors'),
        ]),
      ], collisionMode: MatrixCollisionMode.phrase);
      expect(m.isCollision(0, colOfMove(m, 'swing:partner')), isFalse);
      expect(m.isCollision(1, colOfMove(m, 'swing:neighbor')), isFalse);
    });

    test('a lark allemande and a robin allemande in the SAME phrase of '
        'adjacent dances do NOT collide (issue #933 — this is the reported '
        'defect)', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          allemande('role1s'),
        ]),
        dance('d2', 'B', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          allemande('role2s'),
        ]),
      ]);
      expect(m.isCollision(0, colOfMove(m, 'allemande:larks')), isFalse);
      expect(m.isCollision(1, colOfMove(m, 'allemande:robins')), isFalse);
    });

    test('two lark allemandes in the SAME phrase of adjacent dances DO still '
        'collide (pairs with the test above — proves it is not vacuous: the '
        'columns really are compared, just not across roles)', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          allemande('role1s'),
        ]),
        dance('d2', 'B', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          allemande('role1s'),
        ]),
      ]);
      final c = colOfMove(m, 'allemande:larks');
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
    });

    test('a plain swing and a balance-prefixed swing of the SAME role, in the '
        'SAME phrase of adjacent dances, do NOT collide (issue #933 — the '
        'other reported defect)', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          swing('partners'),
        ]),
        dance('d2', 'B', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          swingWithPrefix('partners', 'balance'),
        ]),
      ]);
      expect(m.isCollision(0, colOfMove(m, 'swing:partner')), isFalse);
      expect(m.isCollision(1, colOfMove(m, 'swing:partner:balance')), isFalse);
    });

    test('two balance-prefixed partner swings in the SAME phrase of adjacent '
        'dances DO still collide (pairs with the test above)', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          swingWithPrefix('partners', 'balance'),
        ]),
        dance('d2', 'B', [
          Figure(move: 'do_si_do', params: {'beats': 48}),
          swingWithPrefix('partners', 'balance'),
        ]),
      ]);
      final c = colOfMove(m, 'swing:partner:balance');
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
    });

    test('the collapsed custom column never collides', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [custom('petronella twirl')]),
        dance('d2', 'B', [custom('california twirl')]),
      ], collisionMode: MatrixCollisionMode.phrase);
      final c = colOfMove(m, customMove);
      expect(c, isNot(-1));
      expect(m.isCollision(0, c), isFalse);
      expect(m.isCollision(1, c), isFalse);
      // Custom is excluded from the phrase map entirely.
      expect(m.rows.first.phraseLabelsByMove.containsKey(customMove), isFalse);
    });

    test('a move present only in this dance does not collide', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('balance', 16)]),
        dance('d2', 'B', [fig('circle', 16)]),
      ], collisionMode: MatrixCollisionMode.phrase);
      expect(m.isCollision(0, colOfMove(m, 'balance')), isFalse);
    });

    test('a move repeated in one dance still needs a neighbour to collide', () {
      // balance twice in one dance (A1 and B1), no neighbour uses it.
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('balance', 32), fig('balance', 16)]),
        dance('d2', 'B', [fig('circle', 16)]),
      ], collisionMode: MatrixCollisionMode.phrase);
      expect(m.rows.first.phraseLabelsByMove['balance'], {'A1', 'B1'});
      expect(m.isCollision(0, colOfMove(m, 'balance')), isFalse);
    });

    test('figures with UNSET beats land in the right phrase via effective '
        'beats (not all A1)', () {
      // No figure carries an explicit beat count; positions come from taxonomy
      // effective beats (do_si_do 8, balance 4, swing 8), NOT raw Figure.beats
      // (which would read 0 and mislabel every figure as A1). Cumulative starts:
      // do_si_do@0 (A1), do_si_do@8 (A1), balance@16 (A2), swing@20 (A2).
      final m = buildProgramMatrix([
        dance('d1', 'A', [
          move('do_si_do'),
          move('do_si_do'),
          move('balance'),
          swing(),
        ]),
      ]);
      final labels = m.rows.first.phraseLabelsByMove;
      expect(labels['do_si_do'], {'A1'});
      expect(labels['balance'], {'A2'});
      expect(labels['swing:partner'], {'A2'});
    });

    test(
      'unset-beats figures no longer false-collide across adjacent dances',
      () {
        // Under the old raw-beats derivation every figure read as A1, so the
        // shared swing would falsely collide. With effective beats it lands in
        // A1 in A but A2 in B (after two 8-beat figures), so there is no collision.
        final m = buildProgramMatrix([
          dance('d1', 'A', [move('do_si_do'), swing()]),
          dance('d2', 'B', [move('do_si_do'), move('do_si_do'), swing()]),
        ], collisionMode: MatrixCollisionMode.phrase);
        expect(m.rows[0].phraseLabelsByMove['swing:partner'], {'A1'});
        expect(m.rows[1].phraseLabelsByMove['swing:partner'], {'A2'});
        expect(m.isCollision(0, colOfMove(m, 'swing:partner')), isFalse);
        expect(m.isCollision(1, colOfMove(m, 'swing:partner')), isFalse);
      },
    );

    test(
      'unknown moves with no beats still advance the cursor (fallback 8)',
      () {
        // An unknown move (not in the taxonomy) has no stored beats; effective
        // beats fall back to 8, so a following figure is pushed past A1 rather
        // than piling up at beat 0. Two unknowns (8+8=16) put balance in A2.
        final m = buildProgramMatrix([
          dance('d1', 'A', [
            move('mystery_move'),
            move('mystery_move'),
            move('balance'),
          ]),
        ]);
        expect(m.rows.first.phraseLabelsByMove['balance'], {'A2'});
      },
    );
  });

  group('isCollision — exact-beat mode (issue #962, the default)', () {
    Figure fig(String id, int beats) =>
        testFigure(move: id, params: {'beats': beats});

    int colOfMove(ProgramMatrix m, String moveId) =>
        m.columns.indexWhere((c) => c.moveId == moveId);

    test('buildProgramMatrix defaults to exact-beat mode', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('balance', 16)]),
      ]);
      expect(m.collisionMode, MatrixCollisionMode.exactBeats);
    });

    test("the issue's own example: same phrase bucket, no beat overlap, "
        'is NOT flagged', () {
      // balance at [32,40) in d1 vs [40,48) in d2 — both land in the B1
      // bucket (32-47) but their beat spans do not overlap at all. This is
      // #962's motivating case, reproduced exactly against the maintainer
      // comment's description.
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 8)]),
        dance('d2', 'B', [fig('do_si_do', 40), fig('balance', 8)]),
      ]);
      final c = colOfMove(m, 'balance');
      expect(m.isCollision(0, c), isFalse);
      expect(m.isCollision(1, c), isFalse);
      // The SAME dances would collide under the old phrase-bucket rule —
      // confirms this is a genuine behaviour narrowing, not a no-op.
      final phraseMatrix = buildProgramMatrix([
        dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 8)]),
        dance('d2', 'B', [fig('do_si_do', 40), fig('balance', 8)]),
      ], collisionMode: MatrixCollisionMode.phrase);
      final pc = colOfMove(phraseMatrix, 'balance');
      expect(phraseMatrix.isCollision(0, pc), isTrue);
      expect(phraseMatrix.isCollision(1, pc), isTrue);
    });

    test('a partial beat overlap across adjacent dances IS flagged', () {
      // d1 balance spans [32,48); d2 balance spans [40,56) — they overlap on
      // [40,48) even though they don't start at the same beat.
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('do_si_do', 32), fig('balance', 16)]),
        dance('d2', 'B', [fig('do_si_do', 40), fig('balance', 16)]),
      ]);
      final c = colOfMove(m, 'balance');
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
    });

    test('a zero-beat figure (form_long_waves) collides as a point at its '
        'start beat', () {
      // form_long_waves has no `beats` param stored, so its effective beats
      // is the taxonomy default 0 (contra_taxonomy.dart ~:1909) — a bare
      // formation label. Both dances land it at beat 16.
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('do_si_do', 16), move('form_long_waves')]),
        dance('d2', 'B', [fig('circle', 16), move('form_long_waves')]),
      ]);
      expect(m.rows[0].beatSpansByMove['form_long_waves'], [
        const BeatSpan(16, 0),
      ]);
      final c = colOfMove(m, 'form_long_waves');
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
    });

    test('a zero-beat figure does NOT collide with a non-overlapping span', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('do_si_do', 16), move('form_long_waves')]),
        dance('d2', 'B', [fig('do_si_do', 32), fig('form_long_waves', 8)]),
      ]);
      // d1's point is at beat 16; d2's span is [32,40) — no overlap.
      final c = colOfMove(m, 'form_long_waves');
      expect(m.isCollision(0, c), isFalse);
      expect(m.isCollision(1, c), isFalse);
    });

    test('a zero-beat figure DOES collide when it falls inside a '
        'non-zero-length neighbouring span', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [fig('do_si_do', 16), move('form_long_waves')]),
        dance('d2', 'B', [fig('do_si_do', 12), fig('form_long_waves', 8)]),
      ]);
      // d1's point is at beat 16; d2's span is [12,20), which contains 16.
      expect(m.rows[0].beatSpansByMove['form_long_waves'], [
        const BeatSpan(16, 0),
      ]);
      expect(m.rows[1].beatSpansByMove['form_long_waves'], [
        const BeatSpan(12, 8),
      ]);
      final c = colOfMove(m, 'form_long_waves');
      expect(m.isCollision(0, c), isTrue);
      expect(m.isCollision(1, c), isTrue);
    });

    test('the collapsed custom column never collides in exact-beat mode', () {
      final m = buildProgramMatrix([
        dance('d1', 'A', [custom('petronella twirl')]),
        dance('d2', 'B', [custom('california twirl')]),
      ]);
      final c = colOfMove(m, customMove);
      expect(c, isNot(-1));
      expect(m.isCollision(0, c), isFalse);
      expect(m.isCollision(1, c), isFalse);
      expect(m.rows.first.beatSpansByMove.containsKey(customMove), isFalse);
    });
  });

  group('BeatSpan.overlaps', () {
    test('two non-zero spans overlap iff their ranges intersect', () {
      expect(const BeatSpan(0, 16).overlaps(const BeatSpan(8, 16)), isTrue);
      expect(const BeatSpan(0, 16).overlaps(const BeatSpan(16, 16)), isFalse);
      expect(const BeatSpan(0, 16).overlaps(const BeatSpan(17, 16)), isFalse);
    });

    test('two zero-beat spans overlap only at the exact same start', () {
      expect(const BeatSpan(16, 0).overlaps(const BeatSpan(16, 0)), isTrue);
      expect(const BeatSpan(16, 0).overlaps(const BeatSpan(17, 0)), isFalse);
    });

    test(
      'a zero-beat span overlaps a non-zero span iff it falls inside it',
      () {
        expect(const BeatSpan(16, 0).overlaps(const BeatSpan(12, 8)), isTrue);
        expect(const BeatSpan(20, 0).overlaps(const BeatSpan(12, 8)), isFalse);
        // Boundary: the zero-beat point exactly at the non-zero span's start is
        // inside (half-open on the low end); exactly at its end is NOT.
        expect(const BeatSpan(12, 0).overlaps(const BeatSpan(12, 8)), isTrue);
        expect(const BeatSpan(20, 0).overlaps(const BeatSpan(12, 8)), isFalse);
        expect(const BeatSpan(12, 8).overlaps(const BeatSpan(12, 0)), isTrue);
      },
    );
  });

  group('MatrixRow equality/hashCode — beatSpansByMove (issue #962)', () {
    test('rows differing only in beatSpansByMove are NOT equal', () {
      final base = MatrixRow(
        danceId: 'd1',
        title: 'A',
        firstMoveId: null,
        presentMoveIds: const {'balance'},
        beatSpansByMove: const {
          'balance': [BeatSpan(0, 16)],
        },
      );
      final sameSpans = MatrixRow(
        danceId: 'd1',
        title: 'A',
        firstMoveId: null,
        presentMoveIds: const {'balance'},
        beatSpansByMove: const {
          'balance': [BeatSpan(0, 16)],
        },
      );
      final differentSpans = MatrixRow(
        danceId: 'd1',
        title: 'A',
        firstMoveId: null,
        presentMoveIds: const {'balance'},
        beatSpansByMove: const {
          'balance': [BeatSpan(16, 16)],
        },
      );
      expect(base, sameSpans);
      expect(base.hashCode, sameSpans.hashCode);
      expect(base, isNot(differentSpans));
    });
  });
}
