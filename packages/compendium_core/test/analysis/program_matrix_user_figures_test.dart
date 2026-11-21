import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart' show testFigure;
import 'package:test/test.dart';

/// The program matrix and figures of your own (#1023): one column per figure
/// whose uses render live, beside the collapsed custom column.
void main() {
  final now = DateTime.utc(2026, 10, 16);

  UserGlossaryEntry figure(String id, String name) => UserGlossaryEntry(
    id: id,
    kindName: UserGlossaryEntryKind.customFigure.name,
    name: name,
    definition: 'A figure.',
    description: 'Of your own.',
    payload: {
      'form': 'contra',
      'template': '{who} $name',
      'defaultBeats': 8,
      'params': [
        {'key': 'who', 'kind': 'dancerSet', 'default': 'neighbors'},
      ],
    },
    createdAt: now,
  );

  final catalog = UserFigureCatalog.fromEntries([
    figure('a-id', 'zoom'),
    figure('b-id', 'whirl'),
    figure('c-id', 'arch'),
  ]);

  Figure use(String id, String name, {Object who = 'neighbors'}) =>
      userFigureUseFigure(
        id: id,
        args: {'who': who},
        text: '$who $name',
        beats: 8,
      );

  Figure custom(String text) =>
      testFigure(move: customMove, params: {'text': text});

  Dance dance(String id, List<Figure> figures) => Dance(
    id: id,
    title: 'Dance $id',
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );

  List<String> ids(ProgramMatrix m) => m.columns.map((c) => c.moveId).toList();

  test('each figure a program uses gets its own column, by name, before the '
      'custom column', () {
    final matrix = buildProgramMatrix([
      dance('d1', [use('a-id', 'zoom'), custom('wander')]),
      dance('d2', [use('b-id', 'whirl')]),
    ], userFigures: catalog);
    expect(
      ids(matrix).where((id) => id.startsWith('userFigure:') || id == 'custom'),
      ['userFigure:b-id', 'userFigure:a-id', customMove],
      reason: 'by name, and the unused figure has no column',
    );
    final zoom = matrix.columns.firstWhere(
      (c) => c.moveId == 'userFigure:a-id',
    );
    expect(zoom.kind, MatrixColumnKind.userFigure);
    expect(zoom.label, 'zoom');
    expect(matrix.rows[0].presentMoveIds, contains('userFigure:a-id'));
    expect(matrix.rows[0].presentMoveIds, contains(customMove));
    expect(matrix.rows[1].presentMoveIds, isNot(contains(customMove)));
    expect(matrix.rows[1].firstMoveId, 'userFigure:b-id');
    expect(
      matrix.columns.where((c) => c.kind == MatrixColumnKind.unknown),
      isEmpty,
      reason: 'a figure of your own is not an unknown move',
    );
  });

  test('a use that would not render live stays in the custom column', () {
    final detached = use('a-id', 'zoom').copyWith(
      params: {...use('a-id', 'zoom').params, 'text': 'typed elsewhere'},
    );
    final gone = use('gone-id', 'gone');
    final outOfRange = use('a-id', 'zoom', who: 'sideways');
    final matrix = buildProgramMatrix([
      dance('d1', [detached]),
      dance('d2', [gone]),
      dance('d3', [outOfRange]),
    ], userFigures: catalog);
    expect(ids(matrix).where((id) => id.startsWith('userFigure:')), isEmpty);
    for (final row in matrix.rows) {
      expect(row.presentMoveIds, {customMove});
    }
  });

  test('without the catalog every use is in the custom column', () {
    final matrix = buildProgramMatrix([
      dance('d1', [use('a-id', 'zoom')]),
    ]);
    expect(ids(matrix).where((id) => id.startsWith('userFigure:')), isEmpty);
    expect(matrix.rows.single.presentMoveIds, {customMove});
  });

  test('the same figure in adjacent dances collides, as a built-in does', () {
    final matrix = buildProgramMatrix([
      dance('d1', [use('a-id', 'zoom')]),
      dance('d2', [use('a-id', 'zoom')]),
    ], userFigures: catalog);
    final col = ids(matrix).indexOf('userFigure:a-id');
    expect(matrix.isCollision(0, col), isTrue);
    expect(matrix.isCollision(1, col), isTrue);
  });

  test(
    'the header is the figure\'s name in the dialect, and a rename wins',
    () {
      final larks = UserFigureCatalog.fromEntries([
        figure('larks-id', 'role1s zoom'),
      ]);
      final matrix = buildProgramMatrix([
        dance('d1', [use('larks-id', 'role1s zoom')]),
      ], userFigures: larks);
      final column = matrix.columns.firstWhere(
        (c) => c.kind == MatrixColumnKind.userFigure,
      );
      expect(
        matrixColumnLabel(column, contraTaxonomy, Dialect.larksRobins),
        'larks zoom',
      );
      expect(
        matrixColumnLabel(
          column,
          contraTaxonomy,
          Dialect.larksRobins,
          config: const MatrixColumnConfig(
            renames: {'userFigure:larks-id': 'Mine'},
          ),
        ),
        'Mine',
      );
    },
  );

  test('the header is the dialect\'s own name for the figure, when it gives '
      'one', () {
    final matrix = buildProgramMatrix([
      dance('d1', [use('a-id', 'zoom')]),
    ], userFigures: catalog);
    final column = matrix.columns.firstWhere(
      (c) => c.kind == MatrixColumnKind.userFigure,
    );
    final dialect = Dialect.larksRobins.copyWith(
      moves: {...Dialect.larksRobins.moves, userFigureKeyFor('a-id'): 'whizz'},
    );
    expect(matrixColumnLabel(column, contraTaxonomy, dialect), 'whizz');
    expect(
      matrixColumnLabel(column, contraTaxonomy, Dialect.larksRobins),
      'zoom',
    );
  });

  test('the column config hides and orders a figure\'s column by its id', () {
    List<String> built(MatrixColumnConfig config) => ids(
      buildProgramMatrix(
        [
          dance('d1', [use('a-id', 'zoom'), use('b-id', 'whirl')]),
        ],
        userFigures: catalog,
        config: config,
      ),
    ).where((id) => id.startsWith('userFigure:')).toList();
    expect(built(const MatrixColumnConfig(hidden: {'userFigure:a-id'})), [
      'userFigure:b-id',
    ]);
    expect(built(const MatrixColumnConfig(order: ['userFigure:a-id'])), [
      'userFigure:a-id',
      'userFigure:b-id',
    ]);
  });

  test('the column catalog lists every figure of your own, by name', () {
    expect(
      [for (final c in userFigureColumnCatalog(catalog)) c.moveId],
      ['userFigure:c-id', 'userFigure:b-id', 'userFigure:a-id'],
    );
  });

  test('the column catalog leaves out a figure that no longer decodes', () {
    final broken = UserGlossaryEntry(
      id: 'd-id',
      kindName: UserGlossaryEntryKind.customFigure.name,
      name: 'broken',
      definition: 'A figure.',
      description: 'Of your own.',
      payload: const {'template': 42},
      createdAt: now,
    );
    final withBroken = UserFigureCatalog.fromEntries([
      figure('a-id', 'zoom'),
      broken,
    ]);
    expect(
      [for (final c in userFigureColumnCatalog(withBroken)) c.moveId],
      ['userFigure:a-id'],
    );
  });

  test('deleting a figure leaves the column config without its column', () {
    const config = MatrixColumnConfig(
      order: ['swing:partner', 'userFigure:a-id', 'custom'],
      hidden: {'userFigure:a-id', 'balance'},
      renames: {'userFigure:a-id': 'Mine', 'balance': 'Bal'},
    );
    final kept = config.withoutColumn('userFigure:a-id');
    expect(kept.order, ['swing:partner', 'custom']);
    expect(kept.hidden, {'balance'});
    expect(kept.renames, {'balance': 'Bal'});
    expect(identical(kept.withoutColumn('userFigure:a-id'), kept), isTrue);
  });
}
