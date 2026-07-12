import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'Test Dance',
  List<String> authorIds = const [],
  List<String> tagIds = const [],
  List<Figure> figures = const [],
  DanceStatus status = DanceStatus.active,
  String hook = '',
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: tagIds,
  figures: figures,
  status: status,
  hook: hook,
  provenance: provenance,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpDetail(
  WidgetTester tester,
  CompendiumRepositories repos,
  String danceId,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: DanceDetailScreen(danceId: danceId),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders header: title, authors, hook, tags', (tester) async {
    final repos = openTestRepositories();
    await repos.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Gene Hubert'),
    );
    await repos.tags.upsert(Tag(id: 't1', name: 'smooth'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Midwest Folklore',
        authorIds: ['c1'],
        tagIds: ['t1'],
        hook: 'a lovely hook',
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    expect(find.text('Midwest Folklore'), findsOneWidget);
    expect(find.text('Gene Hubert'), findsOneWidget);
    expect(find.text('a lovely hook'), findsOneWidget);
    expect(find.text('smooth'), findsOneWidget);
  });

  testWidgets('figure table groups by section and toggles dialect', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    // Section header A1 is derived (figure starts at beat 0).
    expect(find.text('A1'), findsOneWidget);
    // Default view applies the Larks/Robins preset: role2s -> Robins.
    expect(find.text('Robins chain across'), findsOneWidget);

    // Toggle to canonical: role tokens are shown verbatim.
    await tester.tap(find.byKey(const ValueKey('dialect-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('role2s chain across'), findsOneWidget);
  });

  testWidgets('shows status banner for a broken dance', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', status: DanceStatus.broken));

    await _pumpDetail(tester, repos, 'd1');

    expect(find.text('Broken'), findsOneWidget);
  });

  testWidgets('shows provenance line', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        provenance: Provenance(
          source: ProvenanceSource.callersbox,
          importedAt: _now,
          license: 'CC BY-NC',
        ),
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    expect(find.textContaining("The Caller's Box"), findsOneWidget);
    expect(find.textContaining('CC BY-NC'), findsOneWidget);
  });

  testWidgets('Edit action opens the editor', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Editable'));

    await _pumpDetail(tester, repos, 'd1');

    await tester.tap(find.byKey(const ValueKey('edit-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Edit dance'), findsOneWidget);
    expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
  });

  testWidgets('missing dance shows not-found', (tester) async {
    final repos = openTestRepositories();
    await _pumpDetail(tester, repos, 'nope');
    expect(find.text('Dance not found.'), findsOneWidget);
  });
}
