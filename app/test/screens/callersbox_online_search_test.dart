import 'dart:async';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/widgets/advanced_query_builder.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';
import 'package:compendium_app/src/widgets/online_result_tile.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';
import '../support/panel_chip.dart';

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
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: dialect, child: child!),
      ),
      home: CollectionShell(callersBoxOnline: online),
    ),
  );
  await tester.pumpAndSettle();
}

/// Turns on "Online search" with the icon beside the search tools.
Future<void> _enableOnline(WidgetTester tester) async {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Online search icon ends the row of search tools', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());

    final online = tester.getRect(
      find.byKey(const ValueKey('online-search-enable')),
    );
    final advanced = tester.getRect(
      find.byKey(const ValueKey('advanced-panel')),
    );
    expect(online.center.dy, closeTo(advanced.center.dy, 1));
    expect(online.left, greaterThanOrEqualTo(advanced.right));
    expect(find.byKey(const ValueKey('advanced-enable')), findsNothing);
  });

  testWidgets('the Online search icon carries its help text as a tooltip and '
      'shows whether it is on', (tester) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());

    final toggle = find.byKey(const ValueKey('online-search-enable'));
    final icon = find.descendant(of: toggle, matching: find.byType(IconButton));
    expect(
      tester.widget<IconButton>(icon).isSelected,
      isFalse,
      reason: 'off until tapped',
    );
    final tooltip = find.descendant(of: toggle, matching: find.byType(Tooltip));
    expect(
      tester.widget<Tooltip>(tooltip).message,
      'Search online and import dances directly (requires internet). Local '
      'filters do not apply.',
    );

    // A screen reader activates it through the semantic tap action.
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel('Online search'));
    expect(
      node,
      isSemantics(
        label: 'Online search',
        isButton: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: false,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Online search'));
    await tester.pumpAndSettle();
    handle.dispose();
    expect(tester.widget<IconButton>(icon).isSelected, isTrue);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(icon).isSelected, isFalse);
  });

  testWidgets(
    'going online greys out Filters instead of removing it, closes it '
    'if it was open, and shows a full-width source selector',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Petronella',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await _pumpShell(tester, repos, _online());
      final filters = find.byKey(const ValueKey('filters-panel'));
      final rowTop = tester.getRect(filters).top;
      await tester.tap(filters);
      await tester.pumpAndSettle();
      expect(find.byType(FacetPanel), findsOneWidget);

      await _enableOnline(tester);

      expectPanelDisabled(tester, 'filters-panel');
      expect(
        tester.getRect(filters).top,
        rowTop,
        reason: 'the row did not jump',
      );
      expect(find.byType(FacetPanel), findsNothing, reason: 'its panel closed');
      final selector = tester.getRect(
        find.byKey(const ValueKey('online-source-selector')),
      );
      expect(selector.top, greaterThan(tester.getRect(filters).bottom - 1));
      expect(
        selector.width,
        greaterThan(300),
        reason: 'full width, not intrinsic',
      );
    },
  );

  testWidgets('the advanced query editor is always on, with no enable switch '
      'and a greyed-out Advanced tool while online', (tester) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());

    await tester.tap(find.byKey(const ValueKey('advanced-panel')));
    await tester.pumpAndSettle();
    expect(find.byType(AdvancedQueryBuilder), findsOneWidget);

    await _enableOnline(tester);
    expectPanelDisabled(tester, 'advanced-panel');
    expect(
      find.byKey(const ValueKey('online-source-selector')),
      findsOneWidget,
    );

    // Back offline, the tool that was open when online search began is closed
    // rather than springing open again.
    await _enableOnline(tester);
    expect(find.byType(AdvancedQueryBuilder), findsNothing);
    expect(find.byKey(const ValueKey('online-source-selector')), findsNothing);
  });

  testWidgets('the by-phrase panel is available in Online search mode', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpShell(tester, repos, _online());
    await _enableOnline(tester);

    // Un-gated for online: TCB supports its own "search by phrase" fields, so
    // the panel stays reachable (the local Filters panel is greyed out online).
    expect(find.byKey(const ValueKey('by-phrase-panel')), findsOneWidget);
    // This collection is empty, so Filters was never in the row.
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
      _online(
        search: (_) async => throw const UrlFetchException(
          UrlFetchFailureReason.callersBoxUnreachable,
        ),
      ),
    );
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    expect(
      find.text(
        "Couldn't reach The Caller's Box. Check your connection, then "
        'try again.',
      ),
      findsOneWidget,
    );
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

  testWidgets('the loader while an online dance is fetched can be cancelled', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final gate = Completer<String>();
    await _pumpShell(
      tester,
      repos,
      _online(json: (_) => gate.future),
      size: const Size(500, 900),
    );
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('online-preview-loading')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('online-preview-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('online-preview-loading')), findsNothing);
    // A late answer is dropped: no preview opens, no error is shown.
    gate.complete(_danceJson());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-dance')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(OnlineResultTile), findsOneWidget);
  });

  testWidgets('tapping a result again after Cancel joins the fetch still in '
      'flight instead of starting a second one', (tester) async {
    final repos = openTestRepositories();
    final gate = Completer<String>();
    var fetches = 0;
    await _pumpShell(
      tester,
      repos,
      _online(
        json: (_) {
          fetches++;
          return gate.future;
        },
      ),
      size: const Size(500, 900),
    );
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('online-preview-cancel')));
    await tester.pumpAndSettle();
    expect(fetches, 1);

    // The first fetch has not answered; tap the same result again.
    await tester.tap(find.byType(OnlineResultTile));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('online-preview-loading')),
      findsOneWidget,
    );
    expect(fetches, 1, reason: 'a second fetch started while one was running');

    // The one fetch answers and the second tap's loader resolves to a preview.
    gate.complete(_danceJson());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-dance')), findsOneWidget);
    expect(fetches, 1);
  });

  testWidgets('a finished fetch is not reused by a later tap', (tester) async {
    final repos = openTestRepositories();
    var fetches = 0;
    await _pumpShell(
      tester,
      repos,
      _online(
        json: (_) async {
          fetches++;
          return _danceJson();
        },
      ),
      size: const Size(500, 900),
    );
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-dance')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(OnlineResultTile));
    await tester.pumpAndSettle();
    expect(fetches, 2);
  });

  testWidgets('the loader can be dismissed with Back, and a late failure is '
      'swallowed', (tester) async {
    final repos = openTestRepositories();
    final gate = Completer<String>();
    await _pumpShell(
      tester,
      repos,
      _online(json: (_) => gate.future),
      size: const Size(500, 900),
    );
    await _enableOnline(tester);
    await _search(tester, 'Money Musk');
    await tester.tap(find.byType(OnlineResultTile));
    await tester.pump();

    await tester.tapAt(const Offset(5, 5)); // the modal barrier
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('online-preview-loading')), findsNothing);

    gate.completeError(StateError('late'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
