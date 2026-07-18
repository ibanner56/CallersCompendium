import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13);

  Dance dance(String id, String title, List<Figure> figures) => Dance(
    id: id,
    title: title,
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );

  Figure move(String id) => Figure(move: id);
  Figure swing([String? who]) => Figure(move: 'swing', params: {'who': ?who});
  Figure hey([String? length]) =>
      Figure(move: 'hey', params: {'length': ?length});
  Figure custom(String text) =>
      Figure(move: customMove, params: {'text': text});

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
  });
}
