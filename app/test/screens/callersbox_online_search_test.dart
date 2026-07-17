import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

String _danceJson({String id = '10600', String name = 'Money Musk'}) =>
    '{'
    '"ID":"$id","Name":"$name","Authors":["Traditional"],'
    '"InterpretedBy":[],"Permission":"full",'
    '"FormationBase":"Triple Minor - Proper","FormationDetail":"",'
    '"Progression":"Single","PhraseStructure":"",'
    '"CallingNotes":[],"OtherNames":[],"Music":[],"Tunes":[],'
    '"Appearances":[],'
    '"phrases":[{"name":"A1","figures":["Actives balance and swing"]}]'
    '}';

const String _resultsHtml = '''
<html><head><meta charset='windows-1252'></head><body>
<p>Of 16874 dances in the database, your query matches 1.</p>
<table>
<tr>
  <td>&#x24bb;</td><td></td><td></td>
  <td><a href='dance.php?id=10600' target='_blank'>Money Musk</a></td>
  <td>Traditional</td>
  <td>Triple Minor - Proper</td>
</tr>
</table>
</body></html>
''';

const String _emptyResultsHtml = '''
<html><body>
<p>Of 16874 dances in the database, your query matches 0.</p>
<table></table>
</body></html>
''';

Future<void> _pumpShell(
  WidgetTester tester,
  CompendiumRepositories repos,
  CallersBoxOnline online, {
  Size size = const Size(1200, 2000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: dialect, child: child!),
      ),
      home: CollectionShell(callersBoxOnline: online),
    ),
  );
  await tester.pumpAndSettle();
}

/// Expands the Advanced panel and turns on the "Online search" switch.
Future<void> _enableOnline(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('advanced-panel')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('online-search-enable')));
  await tester.pumpAndSettle();
}

/// Types [query] into the search field and lets the online debounce fire.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('collection-search-field')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

CallersBoxOnline _online({
  Future<String> Function(String)? search,
  Future<String> Function(String)? json,
}) => CallersBoxOnline(
  searchFetcher: search ?? (_) async => _resultsHtml,
  jsonFetcher: json ?? (_) async => _danceJson(),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Online search toggle sits above the advanced-query switch', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await tester.tap(find.byKey(const ValueKey('advanced-panel')));
    await tester.pumpAndSettle();

    final onlineY = tester
        .getTopLeft(find.byKey(const ValueKey('online-search-enable')))
        .dy;
    final advancedY = tester
        .getTopLeft(find.byKey(const ValueKey('advanced-enable')))
        .dy;
    expect(onlineY, lessThan(advancedY));
  });

  testWidgets('the by-phrase panel is available in Online search mode', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);

    // Un-gated for online: TCB supports its own "search by phrase" fields, so
    // the panel stays reachable (only the local Filters panel is hidden online).
    expect(find.byKey(const ValueKey('by-phrase-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('filters-panel')), findsNothing);
  });

  testWidgets('turning on Online search and typing shows online results', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    expect(find.byType(OnlineResultTile), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OnlineResultTile),
        matching: find.text('Money Musk'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1 online result'), findsOneWidget);
  });

  testWidgets('tapping a result previews it with an Import FAB (no Edit)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('import-dance')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-dance')), findsNothing);
    // The preview renders the dance detail body.
    expect(find.text('Money Musk'), findsWidgets);
  });

  testWidgets('Import lands on the imported dance in the detail pane', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');
    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('import-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Imported "Money Musk".'), findsOneWidget);
    final saved = await repos.dances.listAll();
    expect(saved.map((d) => d.title), contains('Money Musk'));

    // The detail pane now shows the imported (persisted) dance as a normal
    // detail view with full collection actions — not the online preview.
    expect(find.byKey(const ValueKey('edit-dance')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-dance')), findsNothing);
  });

  testWidgets('re-importing the same dance does not create a duplicate', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');
    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-dance')));
    await tester.pumpAndSettle();
    expect((await repos.dances.listAll()).length, 1);

    // Let the first import's snackbar auto-dismiss so the second import's
    // message isn't queued behind it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Search + preview the same dance again: it is now recognized as already
    // imported and re-importing opens the existing dance without duplicating.
    await _search(tester, 'Money Musk');
    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-dance')));
    await tester.pumpAndSettle();

    expect(
      find.text('"Money Musk" is already in your collection.'),
      findsOneWidget,
    );
    expect((await repos.dances.listAll()).length, 1);
    expect(find.byKey(const ValueKey('edit-dance')), findsOneWidget);
  });

  testWidgets('a fetch failure shows the error message', (tester) async {
    final repos = openTestRepositories();
    await _pumpShell(
      tester,
      repos,
      _online(search: (_) async => throw const UrlFetchException('Offline.')),
    );
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    expect(find.text('Offline.'), findsOneWidget);
  });

  testWidgets('zero results shows the no-matches message', (tester) async {
    final repos = openTestRepositories();
    await _pumpShell(
      tester,
      repos,
      _online(search: (_) async => _emptyResultsHtml),
    );
    await _enableOnline(tester);
    await _search(tester, 'Nonexistent');

    expect(find.byKey(const ValueKey('online-no-results')), findsOneWidget);
  });

  testWidgets('online mode with no query shows a type-a-title hint', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);

    expect(find.byKey(const ValueKey('online-empty-query')), findsOneWidget);
  });

  testWidgets('narrow mode pushes a preview route and imports from it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // Below the 900px split breakpoint → single-pane push navigation.
    await _pumpShell(tester, repos, _online(), size: const Size(500, 900));
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();

    // The pushed preview route shows the Import FAB (and no Edit FAB).
    expect(find.byKey(const ValueKey('import-dance')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-dance')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('import-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Imported "Money Musk".'), findsOneWidget);
    final saved = await repos.dances.listAll();
    expect(saved.map((d) => d.title), contains('Money Musk'));

    // After import the user lands on the persisted dance as a normal detail
    // view (Edit FAB), not the preview (Import FAB).
    expect(find.byKey(const ValueKey('edit-dance')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-dance')), findsNothing);
  });
}
