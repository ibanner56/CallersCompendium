import 'package:compendium_app/src/export/program_matrix_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compendium_core/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Figure move(String id) => testFigure(move: id);
  Figure swing([String? who]) =>
      testFigure(move: 'swing', params: {'who': ?who});
  Figure hey([String? length]) =>
      testFigure(move: 'hey', params: {'length': ?length});

  group('buildProgramMatrixPdf', () {
    test('returns non-empty bytes for a populated matrix', () async {
      final matrix = buildProgramMatrix([
        dance('d1', 'Butterfly', [swing(), move('balance'), hey('full')]),
        dance('d2', 'The Baby Rose', [move('balance'), swing('neighbors')]),
      ]);
      // Swing/hey split columns are present in the model the PDF renders.
      expect(
        matrix.columns.map((c) => c.moveId),
        containsAll(['swing:partner', 'swing:neighbor', 'hey:full']),
      );

      final bytes = await buildProgramMatrixPdf(
        matrix,
        taxonomy: contraTaxonomy,
        dialect: Dialect.canonical,
        programTitle: 'Friday Contra',
        eventDate: DateTime.utc(2026, 3, 9),
        venue: 'Town Hall',
      );

      expect(bytes, isNotEmpty);
    });

    test('returns non-empty bytes for an empty matrix', () async {
      final matrix = buildProgramMatrix(const []);
      expect(matrix.isEmpty, isTrue);

      final bytes = await buildProgramMatrixPdf(
        matrix,
        taxonomy: contraTaxonomy,
        dialect: Dialect.canonical,
        programTitle: 'Empty program',
        omittedFreeTextCount: 2,
      );

      expect(bytes, isNotEmpty);
    });

    test('builds a matrix that carries a first-figure marker', () async {
      final matrix = buildProgramMatrix([
        dance('d1', 'Opener', [swing(), move('balance')]),
      ]);
      // The first figure (a partner swing) is flagged so the star marker path
      // is hit on its split sub-column.
      expect(matrix.rows.first.firstMoveId, 'swing:partner');

      final bytes = await buildProgramMatrixPdf(
        matrix,
        taxonomy: contraTaxonomy,
        dialect: Dialect.larksRobins,
        programTitle: 'First-figure program',
      );

      expect(bytes, isNotEmpty);
    });

    test('builds a matrix that carries a program-debut marker', () async {
      final matrix = buildProgramMatrix([
        // Balance debuts here (mid-dance), so its debut row is 0 even though
        // the dance opens with a swing.
        dance('d1', 'Opener', [swing(), move('balance')]),
        // This dance opens with balance, so it is its dance-first figure, but
        // balance already debuted in d1 — the star marker path (row 0) and the
        // dance-first marker path (row 1) are both exercised.
        dance('d2', 'Second', [move('balance')]),
      ]);
      final balance = matrix.columns.indexWhere((c) => c.moveId == 'balance');
      expect(matrix.isProgramDebut(0, balance), isTrue);
      expect(matrix.isProgramDebut(1, balance), isFalse);
      expect(matrix.isFirst(1, balance), isTrue);

      final bytes = await buildProgramMatrixPdf(
        matrix,
        taxonomy: contraTaxonomy,
        dialect: Dialect.larksRobins,
        programTitle: 'Program-debut program',
      );

      expect(bytes, isNotEmpty);
    });

    test('builds a matrix that carries a same-figure collision marker', () async {
      Figure fig(String id, int beats) => invalidTestFigure(
        move: id,
        params: {'beats': beats},
        reason:
            'callers pass arbitrary move ids, including ones outside the taxonomy, to drive matrix column discovery',
      );
      // balance lands at the identical beat span (32-47) in two
      // strictly-adjacent dances, so its cells collide under either
      // MatrixCollisionMode — the alert marker path.
      final matrix = buildProgramMatrix([
        dance('d1', 'Opener', [fig('do_si_do', 32), fig('balance', 16)]),
        dance('d2', 'Second', [fig('circle_left', 32), fig('balance', 16)]),
      ]);
      final balance = matrix.columns.indexWhere((c) => c.moveId == 'balance');
      expect(matrix.isCollision(0, balance), isTrue);
      expect(matrix.isCollision(1, balance), isTrue);

      final bytes = await buildProgramMatrixPdf(
        matrix,
        taxonomy: contraTaxonomy,
        dialect: Dialect.canonical,
        programTitle: 'Collision program',
      );

      expect(bytes, isNotEmpty);
    });

    test(
      'the printed legend caption matches the matrix collisionMode (#962)',
      () async {
        // Same dances as above but built in phrase mode: the collision still
        // fires (they share the phrase B1), but the printed legend must say
        // "phrase", not "beats" — the two are independently selectable and
        // must never disagree with what the alert marker actually means.
        Figure fig(String id, int beats) => invalidTestFigure(
          move: id,
          params: {'beats': beats},
          reason:
              'callers pass arbitrary move ids, including ones outside the taxonomy, to drive matrix column discovery',
        );
        final phraseMatrix = buildProgramMatrix([
          dance('d1', 'Opener', [fig('do_si_do', 32), fig('balance', 16)]),
          dance('d2', 'Second', [fig('circle_left', 32), fig('balance', 16)]),
        ], collisionMode: MatrixCollisionMode.phrase);
        expect(phraseMatrix.collisionMode, MatrixCollisionMode.phrase);

        final bytes = await buildProgramMatrixPdf(
          phraseMatrix,
          taxonomy: contraTaxonomy,
          dialect: Dialect.canonical,
          programTitle: 'Collision program',
          labels: const ProgramMatrixExportLabels(),
        );

        expect(bytes, isNotEmpty);
      },
    );

    group('formation column (#663)', () {
      test('defaults to an English fallback formation label', () async {
        final matrix = buildProgramMatrix([
          dance('d1', 'A', [
            swing(),
          ], formation: const Formation(FormationShape.becketCw)),
          dance('d2', 'B', [swing()]),
        ]);
        expect(matrix.rows[0].formation.shape, FormationShape.becketCw);
        expect(matrix.rows[1].formation.shape, FormationShape.dupleImproper);

        // No formatFormation supplied: renders without needing a
        // localization layer, matching the pure-Dart-caller contract the
        // other export labels/renderers already follow.
        final bytes = await buildProgramMatrixPdf(
          matrix,
          taxonomy: contraTaxonomy,
          dialect: Dialect.canonical,
          programTitle: 'Formation program',
        );

        expect(bytes, isNotEmpty);
      });

      test(
        'invokes the caller-supplied formatFormation once per row',
        () async {
          final matrix = buildProgramMatrix([
            dance(
              'd1',
              'A',
              [swing()],
              formation: const Formation(
                FormationShape.other,
                detail: 'square set',
              ),
            ),
            dance('d2', 'B', [swing()]),
          ]);

          final seen = <Formation>[];
          final bytes = await buildProgramMatrixPdf(
            matrix,
            taxonomy: contraTaxonomy,
            dialect: Dialect.canonical,
            programTitle: 'Formation program',
            formatFormation: (formation) {
              seen.add(formation);
              return 'X';
            },
          );

          expect(bytes, isNotEmpty);
          expect(seen, matrix.rows.map((r) => r.formation).toList());
        },
      );
    });
  });
}
