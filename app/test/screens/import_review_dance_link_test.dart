import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dance_links.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A dance link pasted into Import (#2335): the path for desktop and for a
/// camera app that shows the link but will not open it. It opens the same
/// review an opened share file gets, and never touches the network.
void main() {
  late List<String> fetched;
  setUp(() => fetched = []);
  setUp(readDanceLinksInPlace);

  Future<String> recordingFetcher(String url) async {
    fetched.add(url);
    throw StateError('no network while opening a dance link');
  }

  Future<CompendiumRepositories> pumpImport(
    WidgetTester tester, {
    List<ImportSource>? sources,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: RepositoriesScope(
          repositories: repos,
          child: ImportReviewScreen(
            sources: sources ?? defaultImportSources(),
            fetcher: recordingFetcher,
            onlineService: CallersBoxOnline(jsonFetcher: recordingFetcher),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repos;
  }

  Future<void> pasteIntoLinkField(WidgetTester tester, String link) async {
    await tester.enterText(
      find.byKey(const ValueKey('import-url-field')),
      link,
    );
    await tester.tap(find.byKey(const ValueKey('import-fetch-url')));
    await tester.pumpAndSettle();
  }

  testWidgets('a link in the link field opens the review without fetching, '
      'and commits the dance', (tester) async {
    final repos = await pumpImport(tester);

    await pasteIntoLinkField(tester, goodDanceLink());

    expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
    expect(find.text(danceLinkTitle), findsWidgets);
    expect(await repos.dances.listAll(), isEmpty);
    expect(fetched, isEmpty);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    expect((await repos.dances.listAll()).map((d) => d.title), [
      danceLinkTitle,
    ]);
    expect(fetched, isEmpty);
  });

  testWidgets('a link in the text field opens the review', (tester) async {
    final repos = await pumpImport(tester);

    await tester.enterText(
      find.byKey(const ValueKey('import-paste-field')),
      '${goodDanceLink()}\n',
    );
    // The field grows to fit the link; lay it out before tapping below it.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('import-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
    expect(find.text(danceLinkTitle), findsWidgets);
    expect(await repos.dances.listAll(), isEmpty);
    expect(fetched, isEmpty);
  });

  testWidgets('a link pasted as a title list is read, not looked up online', (
    tester,
  ) async {
    await pumpImport(
      tester,
      sources: [
        ImportSource(
          kind: ImportSourceKind.titleList,
          adapterFactory: CallersBoxAdapter.new,
          pastedTextOnly: true,
          preselected: true,
        ),
        ImportSource(
          kind: ImportSourceKind.genericJson,
          adapterFactory: GenericJsonAdapter.new,
        ),
      ],
    );

    await tester.enterText(
      find.byKey(const ValueKey('import-titles-field')),
      goodDanceLink(),
    );
    // The field grows to fit the link; lay it out before tapping below it.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('import-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-review-list')), findsOneWidget);
    expect(find.text(danceLinkTitle), findsWidgets);
    expect(fetched, isEmpty);
  });

  testWidgets('a link that cannot be read says so and leaves the input', (
    tester,
  ) async {
    final l10n = AppLocalizationsEn();
    await pumpImport(tester);

    await pasteIntoLinkField(tester, unknownVersionDanceLink());
    expect(find.text(l10n.danceLinkRefusedNewerVersion), findsOneWidget);

    await pasteIntoLinkField(tester, truncatedDanceLink());
    expect(find.text(l10n.danceLinkRefusedDamaged), findsOneWidget);

    await pasteIntoLinkField(tester, emptyArchiveDanceLink());
    expect(find.text(l10n.danceLinkRefusedNoContent), findsOneWidget);

    expect(find.byKey(const ValueKey('import-review-list')), findsNothing);
    expect(find.byKey(const ValueKey('import-url-field')), findsOneWidget);
    expect(fetched, isEmpty);
  });
}
