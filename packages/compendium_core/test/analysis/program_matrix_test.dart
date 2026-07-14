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
  Figure custom(String text) =>
      Figure(move: customMove, params: {'text': text});

  group('buildProgramMatrix — column discovery & order', () {
    test('columns are only the moves actually present', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('swing'), move('balance')]),
      ]);
      expect(matrix.columns.map((c) => c.moveId), ['swing', 'balance']);
      expect(
        matrix.columns.every((c) => c.kind == MatrixColumnKind.known),
        isTrue,
      );
    });

    test('columns follow taxonomy canonical order, not encounter order', () {
      // do_si_do comes before shoulder_round in the taxonomy; feed them in the
      // opposite order and across dances.
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('shoulder_round')]),
        dance('d2', 'B', [move('do_si_do'), move('swing')]),
      ]);
      expect(matrix.columns.map((c) => c.moveId), [
        'swing',
        'do_si_do',
        'shoulder_round',
      ]);
    });

    test('unknown move ids get their own columns after known, sorted', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('zebra_move'), move('swing'), move('aardvark')]),
      ]);
      expect(matrix.columns.map((c) => c.moveId), [
        'swing',
        'aardvark',
        'zebra_move',
      ]);
      expect(matrix.columns[0].kind, MatrixColumnKind.known);
      expect(matrix.columns[1].kind, MatrixColumnKind.unknown);
      expect(matrix.columns[2].kind, MatrixColumnKind.unknown);
    });

    test('all custom figures collapse into one trailing custom column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [custom('scoop them up'), move('swing')]),
        dance('d2', 'B', [custom('a different custom move')]),
      ]);
      expect(matrix.columns.map((c) => c.moveId), ['swing', customMove]);
      expect(matrix.columns.last.kind, MatrixColumnKind.custom);
      expect(matrix.columns.last.isCustom, isTrue);
    });
  });

  group('buildProgramMatrix — presence cells', () {
    test('presence is set exactly where a dance uses the move', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('swing'), move('balance')]),
        dance('d2', 'B', [move('swing')]),
      ]);
      final swing = matrix.columns.indexWhere((c) => c.moveId == 'swing');
      final balance = matrix.columns.indexWhere((c) => c.moveId == 'balance');

      expect(matrix.isPresent(0, swing), isTrue);
      expect(matrix.isPresent(0, balance), isTrue);
      expect(matrix.isPresent(1, swing), isTrue);
      expect(matrix.isPresent(1, balance), isFalse);
    });

    test('a move shared across dances is a single shared column', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('swing')]),
        dance('d2', 'B', [move('swing')]),
      ]);
      expect(matrix.columns.where((c) => c.moveId == 'swing'), hasLength(1));
      expect(matrix.isPresent(0, 0), isTrue);
      expect(matrix.isPresent(1, 0), isTrue);
    });

    test('a move repeated within a dance is a single boolean presence', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('swing'), move('balance'), move('swing')]),
      ]);
      expect(matrix.columns.where((c) => c.moveId == 'swing'), hasLength(1));
      expect(matrix.rows.single.presentMoveIds, {'swing', 'balance'});
    });
  });

  group('buildProgramMatrix — first-figure highlight', () {
    test('flags each row first move and implies presence', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [move('balance'), move('swing')]),
        dance('d2', 'B', [move('swing'), move('balance')]),
      ]);
      final swing = matrix.columns.indexWhere((c) => c.moveId == 'swing');
      final balance = matrix.columns.indexWhere((c) => c.moveId == 'balance');

      expect(matrix.isFirst(0, balance), isTrue);
      expect(matrix.isFirst(0, swing), isFalse);
      expect(matrix.isFirst(1, swing), isTrue);
      expect(matrix.isFirst(1, balance), isFalse);

      // first implies present
      expect(matrix.isPresent(0, balance), isTrue);
      expect(matrix.isPresent(1, swing), isTrue);
    });

    test('first-figure works when the opening figure is custom', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'A', [custom('big circle'), move('swing')]),
      ]);
      final customCol = matrix.columns.indexWhere((c) => c.isCustom);
      expect(matrix.rows.single.firstMoveId, customMove);
      expect(matrix.isFirst(0, customCol), isTrue);
      expect(matrix.isPresent(0, customCol), isTrue);
    });
  });

  group('buildProgramMatrix — edge cases', () {
    test('empty program has no rows and no columns', () {
      final matrix = buildProgramMatrix([]);
      expect(matrix.rows, isEmpty);
      expect(matrix.columns, isEmpty);
      expect(matrix.isEmpty, isTrue);
    });

    test('a figure-less dance produces a row but contributes no columns', () {
      final matrix = buildProgramMatrix([
        dance('d1', 'Stub', const []),
        dance('d2', 'B', [move('swing')]),
      ]);
      expect(matrix.rows, hasLength(2));
      expect(matrix.rows[0].firstMoveId, isNull);
      expect(matrix.rows[0].presentMoveIds, isEmpty);
      expect(matrix.columns.map((c) => c.moveId), ['swing']);
    });

    test('a program with only figure-less dances yields an empty matrix', () {
      final matrix = buildProgramMatrix([dance('d1', 'Stub', const [])]);
      expect(matrix.isEmpty, isTrue);
      expect(matrix.rows, hasLength(1));
    });
  });

  group('matrixColumnLabel', () {
    const known = MatrixColumn(moveId: 'swing', kind: MatrixColumnKind.known);
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
        'swing',
      );
    });

    test('applies a side-independent dialect move substitution', () {
      final dialect = Dialect(name: 'Test', moves: const {'swing': 'twirl'});
      expect(matrixColumnLabel(known, contraTaxonomy, dialect), 'twirl');
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
