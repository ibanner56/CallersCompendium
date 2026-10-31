import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/reference_manager_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// The Authors and Sources managers (LIFE-5, `docs/design/tags-and-people.md`
/// T3), on the list the Tags manager shares.
Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos,
  Widget screen,
) async {
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Ids sort in this order, so the surviving id of a merge is easy to read.
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  final t0 = DateTime.utc(2026, 10, 1);

  late CompendiumRepositories repos;

  setUp(() => repos = openTestRepositories());

  Future<void> author(Choreographer row) async {
    // ignore: unused_result
    await repos.choreographers.upsert(row, at: t0);
  }

  Future<void> dance(
    String id, {
    List<String> authors = const [],
    List<SourceCitation> sources = const [],
  }) => repos.dances.create(
    Dance(
      id: id,
      title: 'Dance $id',
      authorIds: authors,
      sourceCitations: sources,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  Finder key(String value) => find.byKey(ValueKey(value));

  /// Opens [id]'s ⋮ menu in the [prefix] manager.
  Future<void> openActions(
    WidgetTester tester,
    String prefix,
    String id,
  ) async {
    await tester.tap(key('$prefix-actions-$id'));
    await tester.pumpAndSettle();
  }

  Future<void> act(
    WidgetTester tester,
    String prefix,
    String id,
    String action,
  ) async {
    await openActions(tester, prefix, id);
    await tester.tap(key('$prefix-action-$action-$id'));
    await tester.pumpAndSettle();
  }

  group('Authors', () {
    const screen = ReferenceManagerScreen.authors();

    testWidgets('an author a live dance credits offers Merge into and no '
        'Delete; one only a trashed dance credits offers Delete', (
      tester,
    ) async {
      await author(Choreographer(id: a, name: 'Gene Hubert'));
      await author(Choreographer(id: b, name: 'Gene Hurbert'));
      await dance('live', authors: [a]);
      await dance('trashed', authors: [b]);
      await repos.dances.softDelete('trashed', at: t0);
      await _pump(tester, repos, screen);

      await openActions(tester, 'author', a);
      expect(key('author-action-merge-$a'), findsOneWidget);
      expect(key('author-action-delete-$a'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await openActions(tester, 'author', b);
      expect(key('author-action-delete-$b'), findsOneWidget);
    });

    testWidgets('Delete of an unused author offers Undo, and Undo brings it '
        'back with its details', (tester) async {
      await author(
        Choreographer(id: a, name: 'Gene Hurbert', email: 'gene@example.com'),
      );
      await _pump(tester, repos, screen);

      await act(tester, 'author', a, 'delete');

      expect(await repos.choreographers.getById(a), isNull);
      expect(key('author-row-$a'), findsNothing);
      expect(find.text('Deleted “Gene Hurbert”'), findsOneWidget);

      await tester.tap(key('author-manager-undo'));
      await tester.pumpAndSettle();

      final back = await repos.choreographers.getById(a);
      expect(back!.email, 'gene@example.com');
      expect(key('author-row-$a'), findsOneWidget);
    });

    testWidgets('a rename onto another author offers a merge that lists the '
        'detail it drops, and Merge leaves one author with the blanks '
        'filled', (tester) async {
      await author(
        Choreographer(id: a, name: 'Gene Hubert', website: 'gene.example'),
      );
      await author(
        Choreographer(
          id: b,
          name: 'Gene Hurbert',
          website: 'other.example',
          email: 'gene@example.com',
        ),
      );
      await dance('d1', authors: [b]);
      await _pump(tester, repos, screen);

      await act(tester, 'author', b, 'rename');
      await tester.enterText(key('library-rename-field'), 'Gene Hubert');
      await tester.tap(key('library-rename-confirm'));
      await tester.pumpAndSettle();

      expect(key('library-merge-offer'), findsOneWidget);
      expect(key('library-merge-dropped'), findsOneWidget);
      expect(find.text('Website: other.example'), findsOneWidget);
      // The email fills a blank, so it is not listed as dropped.
      expect(find.textContaining('gene@example.com'), findsNothing);

      await tester.tap(key('library-merge-offer-merge'));
      await tester.pumpAndSettle();

      final live = await repos.choreographers.listAll();
      expect(live, hasLength(1));
      expect(live.single.id, a);
      expect(live.single.website, 'gene.example');
      expect(live.single.email, 'gene@example.com');
      expect((await repos.dances.getById('d1'))!.authorIds, [a]);
    });

    testWidgets('Merge into asks first when it would drop a detail, and '
        'Cancel writes nothing', (tester) async {
      await author(Choreographer(id: a, name: 'Gene Hubert', notes: 'caller'));
      await author(Choreographer(id: b, name: 'Gene Hurbert', notes: 'typo'));
      await _pump(tester, repos, screen);

      await act(tester, 'author', b, 'merge');
      await tester.tap(key('library-merge-into-$a'));
      await tester.pumpAndSettle();

      expect(key('library-merge-confirm'), findsOneWidget);
      expect(find.text('Notes: typo'), findsOneWidget);
      await tester.tap(key('library-merge-confirm-cancel'));
      await tester.pumpAndSettle();

      expect(await repos.choreographers.listAll(), hasLength(2));
    });

    testWidgets('Merge into runs at once when nothing conflicts, with Undo', (
      tester,
    ) async {
      await author(Choreographer(id: a, name: 'Gene Hubert'));
      await author(Choreographer(id: b, name: 'Gene Hurbert', notes: 'n'));
      await _pump(tester, repos, screen);

      await act(tester, 'author', b, 'merge');
      await tester.tap(key('library-merge-into-$a'));
      await tester.pumpAndSettle();

      expect(key('library-merge-confirm'), findsNothing);
      final merged = await repos.choreographers.listAll();
      expect(merged.single.notes, 'n');

      await tester.tap(key('author-manager-undo'));
      await tester.pumpAndSettle();
      expect(await repos.choreographers.listAll(), hasLength(2));
    });
  });

  group('Sources', () {
    const screen = ReferenceManagerScreen.sources();

    testWidgets('rows tell same-titled sources apart by author and year, '
        'and a merge keeps one citation with the page filled', (tester) async {
      await repos.publishedSources.upsert(
        PublishedSource(
          id: a,
          title: 'Zesty Contras',
          author: 'Larry Jennings',
        ),
        at: t0,
      );
      await repos.publishedSources.upsert(
        PublishedSource(id: b, title: 'Zesty Contras', year: 1983),
        at: t0,
      );
      await dance(
        'd1',
        sources: [
          SourceCitation(sourceId: a, number: '12'),
          SourceCitation(sourceId: b, page: '34'),
        ],
      );
      await _pump(tester, repos, screen);

      expect(
        find.descendant(
          of: key('source-row-$a'),
          matching: find.textContaining('Larry Jennings'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('source-row-$b'),
          matching: find.textContaining('1983'),
        ),
        findsOneWidget,
      );
      // In use, so no Delete.
      await openActions(tester, 'source', b);
      expect(key('source-action-delete-$b'), findsNothing);
      await tester.tap(key('source-action-merge-$b'));
      await tester.pumpAndSettle();
      await tester.tap(key('library-merge-into-$a'));
      await tester.pumpAndSettle();

      final citations = (await repos.dances.getById('d1'))!.sourceCitations;
      expect(citations, hasLength(1));
      expect(citations.single.sourceId, a);
      expect(citations.single.page, '34');
      expect(citations.single.number, '12');
      final merged = await repos.publishedSources.getById(a);
      expect(merged!.year, 1983);
    });

    testWidgets('Rename writes the new title, with Undo', (tester) async {
      await repos.publishedSources.upsert(
        PublishedSource(id: a, title: 'Zesty Contras'),
        at: t0,
      );
      await _pump(tester, repos, screen);

      await act(tester, 'source', a, 'rename');
      await tester.enterText(key('library-rename-field'), 'Zesty Contras II');
      await tester.tap(key('library-rename-confirm'));
      await tester.pumpAndSettle();

      expect(
        (await repos.publishedSources.getById(a))!.title,
        'Zesty Contras II',
      );
      await tester.tap(key('source-manager-undo'));
      await tester.pumpAndSettle();
      expect((await repos.publishedSources.getById(a))!.title, 'Zesty Contras');
    });
  });
}
