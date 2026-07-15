import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';

import 'support/fake_url_launcher.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'Test Dance',
  List<String> authorIds = const [],
  List<String> tagIds = const [],
  List<Figure> figures = const [],
  List<DanceLink> links = const [],
  DanceStatus status = DanceStatus.active,
  String hook = '',
  Provenance? provenance,
}) => Dance(
  id: id,
  title: title,
  authorIds: authorIds,
  tagIds: tagIds,
  figures: figures,
  links: links,
  status: status,
  hook: hook,
  provenance: provenance,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _pumpDetail(
  WidgetTester tester,
  CompendiumRepositories repos,
  String danceId, {
  Dialect? activeDialect,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
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

  testWidgets('overview is presented in a card and figure rows are separated', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Separated Reel',
        figures: [
          Figure(move: 'balance', params: const {'beats': 8}),
          Figure(move: 'swing', params: const {'beats': 8}),
          Figure(move: 'circle', params: const {'beats': 8}),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    // Overview title sits in a Card, styled as the Fraunces headline.
    final title = tester.widget<Text>(find.text('Separated Reel'));
    final expected = Theme.of(
      tester.element(find.text('Separated Reel')),
    ).textTheme.headlineMedium;
    expect(title.style, expected);
    expect(
      find.ancestor(
        of: find.text('Separated Reel'),
        matching: find.byType(Card),
      ),
      findsOneWidget,
    );

    // Consecutive figure rows are divided by outlineVariant separators.
    expect(find.byType(Divider), findsWidgets);
  });

  testWidgets('Duplicate succeeds for a dance that has links', (tester) async {
    // Regression: duplicating a dance with links used to reuse the link ids
    // and crash on the DanceLinks primary-key constraint.
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Linked Dance',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://v'),
          DanceLink(id: 'l2', kind: LinkKind.source, url: 'https://s'),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');
    await tester.tap(find.byKey(const ValueKey('duplicate-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Linked Dance (copy)'), findsOneWidget);
    final copy = (await repos.dances.listAll()).firstWhere(
      (d) => d.title == 'Linked Dance (copy)',
    );
    expect(copy.links.length, 2);
    expect(copy.links.map((l) => l.id).toSet(), isNot(contains('l1')));
  });

  // ── Soft-delete ────────────────────────────────────────────────────────────

  testWidgets('Delete soft-deletes the dance, pops back to the list, and shows '
      'an undo snackbar', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Doomed Dance'));

    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
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
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
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

  // ── Active dialect threading ───────────────────────────────────────────────

  testWidgets('figure table uses active dialect and toggle shows canonical', (
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

    await _pumpDetail(tester, repos, 'd1', activeDialect: Dialect.larksRobins);

    // Active dialect = Larks/Robins: role2s → Robins.
    expect(find.text('Robins chain across'), findsOneWidget);
    // Toggle is visible because active dialect is not canonical.
    expect(find.byKey(const ValueKey('dialect-toggle')), findsOneWidget);

    // Toggle to canonical.
    await tester.tap(find.byKey(const ValueKey('dialect-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('role2s chain across'), findsOneWidget);
  });

  testWidgets('with Gents/Ladies dialect figure table shows those terms', (
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

    await _pumpDetail(
      tester,
      repos,
      'd1',
      activeDialect: Dialect(
        name: 'Gents/Ladies',
        roles: const {'role1': RoleTerm('Gent'), 'role2': RoleTerm('Lady')},
      ),
    );

    // role2s → Ladies in Gents/Ladies dialect.
    expect(find.text('Ladies chain across'), findsOneWidget);
    // Toggle is present (non-canonical dialect).
    expect(find.byKey(const ValueKey('dialect-toggle')), findsOneWidget);
  });

  testWidgets('with Canonical dialect the dialect toggle is hidden', (
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

    await _pumpDetail(tester, repos, 'd1', activeDialect: Dialect.canonical);

    // Toggle is hidden when active dialect is already canonical.
    expect(find.byKey(const ValueKey('dialect-toggle')), findsNothing);
    // Canonical role tokens shown.
    expect(find.text('role2s chain across'), findsOneWidget);
  });

  // ── relatedDance links ─────────────────────────────────────────────────────

  testWidgets('relatedDance link shows target dance title, not raw id', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target', title: 'Petronella Jig'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'target',
            label: '',
          ),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    // Title is shown, not the raw id.
    expect(find.text('Petronella Jig'), findsOneWidget);
    expect(find.text('target'), findsNothing);
  });

  testWidgets('relatedDance link with label shows label (not title or id)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target', title: 'Hidden Title'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'target',
            label: 'See this one',
          ),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    // Label takes priority.
    expect(find.text('See this one'), findsOneWidget);
  });

  testWidgets(
    'relatedDance link with dangling targetDanceId shows placeholder',
    (tester) async {
      final repos = openTestRepositories();
      // Create the target dance and then soft-delete it to simulate a link
      // whose target has been removed from the visible collection.
      await repos.dances.create(_dance(id: 'gone-target', title: 'Was Here'));
      await repos.dances.create(
        _dance(
          id: 'd1',
          links: [
            DanceLink(
              id: 'l1',
              kind: LinkKind.relatedDance,
              targetDanceId: 'gone-target',
              label: '',
            ),
          ],
        ),
      );
      await repos.dances.softDelete('gone-target', at: DateTime.now().toUtc());

      await _pumpDetail(tester, repos, 'd1');

      // Falls back to placeholder text because getById returns null.
      expect(find.text('(missing dance)'), findsOneWidget);
    },
  );

  testWidgets('relatedDance link is tappable when target exists', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'target', title: 'Target Dance', hook: 'target hook'),
    );
    await repos.dances.create(
      _dance(
        id: 'd1',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'target',
          ),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    // Tap the related-dance link row.
    await tester.tap(find.byKey(const ValueKey('link-row-l1')));
    await tester.pumpAndSettle();

    // Navigated to the target dance's detail screen.
    expect(find.text('Target Dance'), findsOneWidget);
    expect(find.text('target hook'), findsOneWidget);
  });

  testWidgets('renders a cited source: title, author/year, page/number', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.publishedSources.upsert(
      PublishedSource(
        id: 's1',
        title: 'Zesty Contras',
        author: 'Larry Jennings',
        year: 1983,
        url: 'https://example.com/zesty',
      ),
    );
    await repos.dances.create(
      _dance(id: 'd1', title: 'Cited Dance').copyWith(
        sourceCitations: [
          SourceCitation(sourceId: 's1', page: '12-14', number: 'A1'),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    expect(find.text('Published sources'), findsOneWidget);
    expect(find.byKey(const ValueKey('source-citation-s1')), findsOneWidget);
    expect(find.text('Zesty Contras — Larry Jennings, 1983'), findsOneWidget);
    expect(find.text('p. 12-14, no. A1'), findsOneWidget);
    expect(find.text('https://example.com/zesty'), findsOneWidget);
  });

  // ── External-link launching ──────────────────────────────────────────────

  testWidgets('tapping a video link launches its URL externally', (
    tester,
  ) async {
    final fake = installFakeUrlLauncher();
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Linked Dance',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.video,
            url: 'https://youtu.be/abc',
            label: 'Watch it',
          ),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');
    await tester.tap(find.byKey(const ValueKey('link-row-l1')));
    await tester.pumpAndSettle();

    expect(fake.lastLaunchedUrl, 'https://youtu.be/abc');
    expect(fake.launchedModes.single, PreferredLaunchMode.externalApplication);
  });

  testWidgets('tapping a source-citation URL launches it externally', (
    tester,
  ) async {
    final fake = installFakeUrlLauncher();
    final repos = openTestRepositories();
    await repos.publishedSources.upsert(
      PublishedSource(
        id: 's1',
        title: 'Zesty Contras',
        url: 'https://example.com/zesty',
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Cited Dance',
      ).copyWith(sourceCitations: [SourceCitation(sourceId: 's1')]),
    );

    await _pumpDetail(tester, repos, 'd1');
    await tester.tap(find.byKey(const ValueKey('source-citation-s1')));
    await tester.pumpAndSettle();

    expect(fake.lastLaunchedUrl, 'https://example.com/zesty');
    expect(fake.launchedModes.single, PreferredLaunchMode.externalApplication);
  });

  testWidgets('a non-http(s) link URL renders plain text, no launch on tap', (
    tester,
  ) async {
    final fake = installFakeUrlLauncher();
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Linked Dance',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.other, url: 'mailto:a@b.com'),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    // Plain-text row: not exposed as a button, and tapping launches nothing.
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('link-row-l1')),
    );
    expect(semantics, isNot(isSemantics(isButton: true)));

    await tester.tap(find.byKey(const ValueKey('link-row-l1')));
    await tester.pumpAndSettle();
    expect(fake.launchedUrls, isEmpty);
  });

  testWidgets('a launch failure surfaces a SnackBar and does not crash', (
    tester,
  ) async {
    final fake = installFakeUrlLauncher();
    fake.launchResult = false;
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Linked Dance',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.video, url: 'https://v.example'),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');
    await tester.tap(find.byKey(const ValueKey('link-row-l1')));
    await tester.pump();

    expect(find.text("Couldn't open link"), findsOneWidget);
  });

  testWidgets('a launchable link exposes a reachable button in the a11y tree', (
    tester,
  ) async {
    installFakeUrlLauncher();
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Linked Dance',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.video,
            url: 'https://v.example',
            label: 'A video',
          ),
        ],
      ),
    );

    await _pumpDetail(tester, repos, 'd1');

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('link-row-l1')),
    );
    expect(
      semantics,
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        label: 'Open video: A video',
      ),
    );
  });
}
