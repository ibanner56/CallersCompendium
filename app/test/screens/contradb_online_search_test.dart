import 'dart:convert';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

/// Widget tests for the ContraDB online-search source: it is reachable via the
/// source selector, renders results, hides the by-phrase panel (ContraDB search
/// is title-only), and imports through the existing ContraDB HTML adapter.

String _searchJson({String id = '1', String title = 'The Rendezvous'}) =>
    jsonEncode({
      'numberSearched': 2324,
      'numberMatching': 1,
      'dances': [
        {
          'id': int.parse(id),
          'title': title,
          'choreographer_id': 4,
          'choreographer_name': 'Dan Pearl',
          'formation': 'improper',
          'hook': '',
          'user_name': 'Someone',
          'publish': 'everywhere',
          'matching_figures_html': '',
        },
      ],
    });

const String _danceHtml = '''
<!DOCTYPE html><html><head><title>x</title></head>
<body class="dances-show-body">
<h1 class="dance-show-title">The Rendezvous</h1>
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Dan Pearl</a></strong></p>
<p class="dance-show-formation">formation: improper </p>
<table class="table table-bordered table-condensed contra-table-nonfluid">
  <tr class="a1b1 dance-show-long-figure">
    <td>A1</td><td class=dance-show-beats>16</td>
    <td><div class="show-figure">neighbors balance &amp; swing</div></td>
  </tr>
  <tr class="a1b1 dance-show-long-figure">
    <td>B1</td><td class=dance-show-beats>16</td>
    <td><div class="show-figure">partners balance &amp; <u>swing</u></div></td>
  </tr>
</table>
</body></html>
''';

ContraDbOnline _contraDb({
  Future<String> Function(String)? search,
  Future<String> Function(String)? html,
}) => ContraDbOnline(
  searchFetcher: search ?? (_) async => _searchJson(),
  htmlFetcher: html ?? (_) async => _danceHtml,
);

Future<void> _pumpShell(
  WidgetTester tester,
  CompendiumRepositories repos,
  ContraDbOnline contraDb, {
  Size size = const Size(1200, 2000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: dialect, child: child!),
      ),
      home: CollectionShell(
        callersBoxOnline: CallersBoxOnline(
          searchFetcher: (_) async => '<html><body></body></html>',
        ),
        contraDbOnline: contraDb,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Expands the Advanced panel, turns on the "Online search" switch, and selects
/// the ContraDB source.
Future<void> _enableContraDb(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('advanced-panel')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('online-search-enable')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ContraDB'));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('collection-search-field')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the ContraDB source is selectable via the source selector', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _contraDb());
    await tester.tap(find.byKey(const ValueKey('advanced-panel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('online-search-enable')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('online-source-selector')),
      findsOneWidget,
    );
    expect(find.text('ContraDB'), findsOneWidget);
  });

  testWidgets('selecting ContraDB hides the by-phrase panel (title-only)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _contraDb());
    await _enableContraDb(tester);

    expect(find.byKey(const ValueKey('by-phrase-panel')), findsNothing);
    expect(find.byKey(const ValueKey('filters-panel')), findsNothing);
  });

  testWidgets('ContraDB leaves no stray divider above the Advanced panel, and '
      'switching back to Caller\'s Box restores By phrase', (tester) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _contraDb());
    await _enableContraDb(tester);

    // With ContraDB (title-only) the By-phrase panel is dropped and the
    // Advanced panel is the first visible panel, so it must not carry a
    // leading inter-panel divider (the "white line" nit from #302).
    expect(find.byKey(const ValueKey('advanced-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('by-phrase-panel')), findsNothing);
    expect(find.byKey(const ValueKey('filter-panel-divider-1')), findsNothing);

    // Switching back to Caller's Box (supportsByPhrase) restores By phrase,
    // reintroducing the divider between it and Advanced.
    await tester.tap(find.text('Caller\'s Box'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('by-phrase-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('filter-panel-divider-1')),
      findsOneWidget,
    );
  });

  testWidgets('searching ContraDB renders results with its attribution', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _contraDb());
    await _enableContraDb(tester);
    await _search(tester, 'rendezvous');

    expect(find.byType(OnlineResultTile), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OnlineResultTile),
        matching: find.text('The Rendezvous'),
      ),
      findsOneWidget,
    );
    expect(find.text('From ContraDB (online)'), findsOneWidget);
  });

  testWidgets('importing a ContraDB result lands it in the collection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _contraDb());
    await _enableContraDb(tester);
    await _search(tester, 'rendezvous');

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-dance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Imported "The Rendezvous".'), findsOneWidget);
    final saved = await repos.dances.listAll();
    expect(saved.map((d) => d.title), contains('The Rendezvous'));
    expect(saved.single.provenance?.source, ProvenanceSource.contradb);
  });

  testWidgets('a ContraDB fetch failure shows the error message', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(
      tester,
      repos,
      _contraDb(
        search: (_) async => throw const UrlFetchException(
          UrlFetchFailureReason.contraDbUnreachable,
        ),
      ),
    );
    await _enableContraDb(tester);
    await _search(tester, 'rendezvous');

    expect(find.byKey(const ValueKey('online-error')), findsOneWidget);
  });
}
