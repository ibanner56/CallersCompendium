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

  // ── Duplicate ──────────────────────────────────────────────────────────────

  testWidgets(
    'Duplicate creates an independent copy titled "<title> (copy)" and '
    'navigates to it',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'River Run'));

      await _pumpDetail(tester, repos, 'd1');

      await tester.tap(find.byKey(const ValueKey('duplicate-dance')));
      await tester.pumpAndSettle();

      // We are now on the detail screen for the copy.
      expect(find.text('River Run (copy)'), findsOneWidget);

      // Two dances exist: original and copy.
      final all = await repos.dances.listAll();
      expect(all.length, 2);
      expect(all.map((d) => d.title).toSet(), {
        'River Run',
        'River Run (copy)',
      });

      // The copy has a different id.
      final original = all.firstWhere((d) => d.title == 'River Run');
      final copy = all.firstWhere((d) => d.title == 'River Run (copy)');
      expect(copy.id, isNot(original.id));

      // The copy has no provenance (independent record).
      expect(copy.provenance, isNull);
    },
  );

  testWidgets('Duplicate preserves figures and metadata on the copy', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Petronella Jig',
        figures: [
          Figure(move: 'petronella', params: const {'beats': 8}),
        ],
        hook: 'A great hook',
      ),
    );

    await _pumpDetail(tester, repos, 'd1');
    await tester.tap(find.byKey(const ValueKey('duplicate-dance')));
    await tester.pumpAndSettle();

    // The copy's detail screen shows the same hook/figures.
    expect(find.text('A great hook'), findsOneWidget);
    expect(find.text('Petronella Jig (copy)'), findsOneWidget);

    final copy = (await repos.dances.listAll()).firstWhere(
      (d) => d.title == 'Petronella Jig (copy)',
    );
    expect(copy.figures.length, 1);
    expect(copy.figures.first.move, 'petronella');
    expect(copy.hook, 'A great hook');
  });

  // ── Soft-delete ────────────────────────────────────────────────────────────

  testWidgets('Delete soft-deletes the dance, pops back to the list, and shows '
      'an undo snackbar', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Doomed Dance'));

    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            RepositoriesScope(repositories: repos, child: child!),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: GestureDetector(
              onTap: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => const DanceDetailScreen(danceId: 'd1'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Doomed Dance'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-dance')));
    await tester.pumpAndSettle();

    // Popped back to the previous screen.
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Doomed Dance'), findsNothing);

    // Snackbar with undo action appears.
    expect(find.text('"Doomed Dance" deleted.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Dance is soft-deleted (not hard-deleted).
    final deleted = await repos.dances.getById('d1', includeDeleted: true);
    expect(deleted, isNotNull);
    expect(deleted!.deletedAt, isNotNull);

    // Dance no longer appears in normal listAll.
    final visible = await repos.dances.listAll();
    expect(visible.where((d) => d.id == 'd1'), isEmpty);
  });

  testWidgets('Undo on the delete snackbar restores the dance', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Undo Me'));

    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            RepositoriesScope(repositories: repos, child: child!),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: GestureDetector(
              onTap: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => const DanceDetailScreen(danceId: 'd1'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('delete-dance')));
    await tester.pumpAndSettle();

    // Tap Undo.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // Dance is no longer soft-deleted.
    final dance = await repos.dances.getById('d1');
    expect(dance, isNotNull);
    expect(dance!.deletedAt, isNull);
  });
}
