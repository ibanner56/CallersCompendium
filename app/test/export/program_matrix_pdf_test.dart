import 'package:compendium_app/src/export/program_matrix_pdf.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}
