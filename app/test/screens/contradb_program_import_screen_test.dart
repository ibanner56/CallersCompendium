import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/collection_refresh_scope.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/contradb_program_search.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/contradb_program_import_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

/// A minimal, but real-shaped, ContraDB program page: two linked dances with a
/// note between them.
const String _programHtml = '''
<html><body>
<div class="programs-show-content"><div class="container"><h1>Barn Dance</h1></div></div>
<div id="activity-1" class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title"><a href="/dances/185">Courageous Soul</a></h2>
</div>
<div id="activity-2" class="activity-breakdown">
  <h2 class="activity-breakdown-text"><div class='contra-markdown-block'><p>Waltz</p></div></h2>
</div>
<div id="activity-3" class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title"><a href="/dances/173">Boys From Urbana</a></h2>
</div>
</body></html>
''';

/// A minimal ContraDB dance page the `ContraDbHtmlAdapter` can parse. The title
/// is derived from the id so each imported dance is distinct.
String _danceHtml(String id) =>
    '<html><body>'
    '<h1 class="dance-show-title">ContraDB Dance $id</h1>'
    '<p class="dance-show-formation">formation: improper</p>'
    '<table class="contra-table-nonfluid">'
    '<tr><td>A1</td><td class="dance-show-beats">16</td>'
    '<td><div class="show-figure">neighbors balance &amp; swing</div></td></tr>'
    '</table>'
    '</body></html>';

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required Future<String> Function(String) programFetcher,
  required ContraDbOnline contraDb,
  CallersBoxOnline? callersBox,
  ContraDbProgramSearch? programSearch,
  ValueNotifier<int>? revision,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) {
        final scoped = revision == null
            ? child!
            : CollectionRefreshScope(revision: revision, child: child!);
        return RepositoriesScope(repositories: repos, child: scoped);
      },
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => ContraDbProgramImportScreen(
                    programFetcher: programFetcher,
                    contraDbOnline: contraDb,
                    callersBoxOnline: callersBox,
                    programSearch: programSearch,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('fetches, previews, and imports a ContraDB program in order', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ContraDB per-dance scrape is seam-backed: return a page keyed on the id.
    final contraDb = ContraDbOnline(
      htmlFetcher: (url) async {
        final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
        return _danceHtml(id);
      },
    );

    await _pump(
      tester,
      repos,
      programFetcher: (_) async => _programHtml,
      contraDb: contraDb,
    );

    // Before fetching, the empty-preview hint shows and Import is disabled.
    expect(
      find.byKey(const ValueKey('contradb-program-empty-preview')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('contradb-program-url')),
      'https://contradb.com/programs/33',
    );
    await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
    await tester.pumpAndSettle();

    // Title pre-filled from the page; preview lists 3 activities in order.
    expect(find.text('Barn Dance'), findsWidgets);
    expect(find.text('3 activities (2 dances, 1 note)'), findsOneWidget);
    expect(find.text('Courageous Soul'), findsOneWidget);
    expect(find.text('Waltz'), findsOneWidget);
    expect(find.text('Boys From Urbana'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
    await tester.pumpAndSettle();

    final programs = await repos.programs.listAll();
    expect(programs, hasLength(1));
    final program = programs.single;
    expect(program.title, 'Barn Dance');
    // Order preserved: dance, note, dance.
    expect(program.slots.map((s) => s.position).toList(), [0, 1, 2]);
    expect(program.slots[0].danceId, isNotNull);
    expect(program.slots[1].danceId, isNull);
    expect(program.slots[1].text, 'Waltz');
    expect(program.slots[2].danceId, isNotNull);

    // Two distinct ContraDB dances were actually imported.
    final dances = await repos.dances.listAll();
    expect(dances, hasLength(2));

    expect(
      find.byKey(const ValueKey('contradb-program-committed-snackbar')),
      findsOneWidget,
    );
  });

  testWidgets(
    'issue #340: committing a ContraDB program signals the collection to '
    'refresh (imported dances must appear live)',
    (tester) async {
      final repos = openTestRepositories();
      final contraDb = ContraDbOnline(
        htmlFetcher: (url) async {
          final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
          return _danceHtml(id);
        },
      );
      final revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);

      await _pump(
        tester,
        repos,
        programFetcher: (_) async => _programHtml,
        contraDb: contraDb,
        revision: revision,
      );

      await tester.enterText(
        find.byKey(const ValueKey('contradb-program-url')),
        'https://contradb.com/programs/33',
      );
      await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
      await tester.pumpAndSettle();

      expect(revision.value, 0);

      await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
      await tester.pumpAndSettle();

      // Two dances were imported into the collection, so the live Collection
      // view must be told to reload.
      expect((await repos.dances.listAll()), hasLength(2));
      expect(revision.value, greaterThan(0));
    },
  );

  testWidgets('a fetch failure surfaces an error and keeps Import disabled', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      programFetcher: (_) async => throw Exception('offline'),
      contraDb: ContraDbOnline(htmlFetcher: (_) async => ''),
    );

    await tester.enterText(
      find.byKey(const ValueKey('contradb-program-url')),
      '33',
    );
    await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('contradb-program-fetch-error')),
      findsOneWidget,
    );
    expect(await repos.programs.listAll(), isEmpty);
  });

  testWidgets('searches by name and imports the picked program', (
    tester,
  ) async {
    const indexHtml = '''
<html><body>
  <a href="/programs/33">Barn Dance Night</a>
  <a href="/programs/99">Spring Fling</a>
</body></html>
''';
    final repos = openTestRepositories();
    final contraDb = ContraDbOnline(
      htmlFetcher: (url) async {
        final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
        return _danceHtml(id);
      },
    );

    await _pump(
      tester,
      repos,
      // The program page is fetched by id ('33') through the existing seam.
      programFetcher: (_) async => _programHtml,
      contraDb: contraDb,
      programSearch: ContraDbProgramSearch(fetch: (_) async => indexHtml),
    );

    // Switch to search mode; the index loads and the prompt shows.
    await tester.tap(find.text('Search by name'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('contradb-program-search-prompt')),
      findsOneWidget,
    );

    // Type a name → only the matching program is listed.
    await tester.enterText(
      find.byKey(const ValueKey('contradb-program-search-field')),
      'barn',
    );
    await tester.pumpAndSettle();
    expect(find.text('Barn Dance Night'), findsOneWidget);
    expect(find.text('Spring Fling'), findsNothing);

    // Pick it → reuses the existing fetch+preview pipeline for /programs/33.
    await tester.tap(find.text('Barn Dance Night'));
    await tester.pumpAndSettle();
    expect(find.text('3 activities (2 dances, 1 note)'), findsOneWidget);
    expect(find.text('Courageous Soul'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
    await tester.pumpAndSettle();

    final programs = await repos.programs.listAll();
    expect(programs, hasLength(1));
    expect(programs.single.title, 'Barn Dance');
    expect(await repos.dances.listAll(), hasLength(2));
  });

  testWidgets('refining the query after a pick returns to the results list', (
    tester,
  ) async {
    const indexHtml = '''
<html><body>
  <a href="/programs/33">Barn Dance Night</a>
  <a href="/programs/99">Spring Fling</a>
</body></html>
''';
    final repos = openTestRepositories();
    final contraDb = ContraDbOnline(
      htmlFetcher: (url) async {
        final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
        return _danceHtml(id);
      },
    );

    await _pump(
      tester,
      repos,
      programFetcher: (_) async => _programHtml,
      contraDb: contraDb,
      programSearch: ContraDbProgramSearch(fetch: (_) async => indexHtml),
    );

    await tester.tap(find.text('Search by name'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contradb-program-search-field')),
      'barn',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barn Dance Night'));
    await tester.pumpAndSettle();

    // Preview is showing after the pick.
    expect(
      find.byKey(const ValueKey('contradb-program-preview')),
      findsOneWidget,
    );

    // Editing the query clears the preview and shows results again.
    await tester.enterText(
      find.byKey(const ValueKey('contradb-program-search-field')),
      'spring',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('contradb-program-preview')),
      findsNothing,
    );
    expect(find.text('Spring Fling'), findsOneWidget);
  });

  testWidgets('switching to search after a URL fetch reveals the results UI', (
    tester,
  ) async {
    const indexHtml =
        '<html><body><a href="/programs/33">Barn Dance Night</a></body></html>';
    final repos = openTestRepositories();
    final contraDb = ContraDbOnline(
      htmlFetcher: (url) async {
        final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
        return _danceHtml(id);
      },
    );

    await _pump(
      tester,
      repos,
      programFetcher: (_) async => _programHtml,
      contraDb: contraDb,
      programSearch: ContraDbProgramSearch(fetch: (_) async => indexHtml),
    );

    // Fetch a program via the URL flow first.
    await tester.enterText(
      find.byKey(const ValueKey('contradb-program-url')),
      '33',
    );
    await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('contradb-program-preview')),
      findsOneWidget,
    );

    // Switching to search mode clears the preview so the results UI is reachable.
    await tester.tap(find.text('Search by name'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('contradb-program-preview')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('contradb-program-search-prompt')),
      findsOneWidget,
    );
  });

  testWidgets('a program-index load failure shows an error with retry', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pump(
      tester,
      repos,
      programFetcher: (_) async => _programHtml,
      contraDb: ContraDbOnline(htmlFetcher: (_) async => ''),
      programSearch: ContraDbProgramSearch(
        fetch: (_) async => throw const UrlFetchException('offline'),
      ),
    );

    await tester.tap(find.text('Search by name'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('contradb-program-search-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('contradb-program-search-retry')),
      findsOneWidget,
    );
  });

  group('caller precedence (#350/#351)', () {
    ContraDbOnline danceSeam() => ContraDbOnline(
      htmlFetcher: (url) async {
        final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
        return _danceHtml(id);
      },
    );

    Future<Program> importAndRead(
      WidgetTester tester, {
      required String html,
      String? defaultCaller,
    }) async {
      final repos = openTestRepositories();
      if (defaultCaller != null) {
        await repos.settings.set(kDefaultProgramCallerKey, defaultCaller);
      }
      await _pump(
        tester,
        repos,
        programFetcher: (_) async => html,
        contraDb: danceSeam(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contradb-program-url')),
        'https://contradb.com/programs/33',
      );
      await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
      await tester.pumpAndSettle();
      return (await repos.programs.listAll()).single;
    }

    testWidgets('contributor wins over the user default caller', (
      tester,
    ) async {
      final program = await importAndRead(
        tester,
        html: _programWith(
          contributorHref: '/users/67',
          contributor: 'Karl Senseman',
        ),
        defaultCaller: 'My Default',
      );
      expect(program.caller, 'Karl Senseman');
    });

    testWidgets('falls back to the default caller when no contributor', (
      tester,
    ) async {
      final program = await importAndRead(
        tester,
        html: _programWith(),
        defaultCaller: 'My Default',
      );
      expect(program.caller, 'My Default');
    });

    testWidgets('leaves the caller blank when neither is present', (
      tester,
    ) async {
      final program = await importAndRead(tester, html: _programWith());
      expect(program.caller, isNull);
    });
  });

  group('event-date auto-detect (#351)', () {
    ContraDbOnline danceSeam() => ContraDbOnline(
      htmlFetcher: (url) async {
        final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
        return _danceHtml(id);
      },
    );

    testWidgets('high-confidence ISO title populates the date + hint', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        programFetcher: (_) async =>
            _programWith(title: '2024-03-15 Barn Dance'),
        contraDb: danceSeam(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contradb-program-url')),
        'https://contradb.com/programs/33',
      );
      await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
      await tester.pumpAndSettle();

      // The detection hint is shown so the guess is transparent.
      expect(
        find.byKey(const ValueKey('contradb-program-date-detected-hint')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
      await tester.pumpAndSettle();
      final program = (await repos.programs.listAll()).single;
      expect(program.eventDate, DateTime.utc(2024, 3, 15));
    });

    testWidgets('a free-form title leaves the date unset (no over-match)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        programFetcher: (_) async => _programWith(title: "Spring Fling '24"),
        contraDb: danceSeam(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contradb-program-url')),
        'https://contradb.com/programs/33',
      );
      await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contradb-program-date-detected-hint')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
      await tester.pumpAndSettle();
      expect((await repos.programs.listAll()).single.eventDate, isNull);
    });

    testWidgets('a detected date is clearable before commit', (tester) async {
      final repos = openTestRepositories();
      await _pump(
        tester,
        repos,
        programFetcher: (_) async =>
            _programWith(title: '2024-03-15 Barn Dance'),
        contraDb: danceSeam(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contradb-program-url')),
        'https://contradb.com/programs/33',
      );
      await tester.tap(find.byKey(const ValueKey('contradb-program-fetch')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('contradb-program-clear-date')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('contradb-program-date-detected-hint')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('contradb-program-commit')));
      await tester.pumpAndSettle();
      expect((await repos.programs.listAll()).single.eventDate, isNull);
    });
  });

  testWidgets(
    'issue #343: initialUrl pre-fills the URL field and auto-fetches the '
    'program preview without any manual entry',
    (tester) async {
      final repos = openTestRepositories();
      final contraDb = ContraDbOnline(
        htmlFetcher: (url) async {
          final id = RegExp(r'/dances/(\d+)').firstMatch(url)!.group(1)!;
          return _danceHtml(id);
        },
      );

      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) =>
              RepositoriesScope(repositories: repos, child: child!),
          home: ContraDbProgramImportScreen(
            initialUrl: 'https://contradb.com/programs/33',
            programFetcher: (_) async => _programHtml,
            contraDbOnline: contraDb,
          ),
        ),
      );
      // No manual enterText / fetch tap: the shared URL drives the fetch on the
      // first frame, dropping the user straight onto the preview.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('contradb-program-url')),
        findsOneWidget,
      );
      // The shared URL was pre-filled into the field (shown as its text).
      expect(find.text('https://contradb.com/programs/33'), findsOneWidget);
      // The preview populated from the auto-fetch.
      expect(find.text('3 activities (2 dances, 1 note)'), findsOneWidget);
      expect(find.text('Courageous Soul'), findsOneWidget);
    },
  );
}

/// Builds a minimal ContraDB program page with a configurable [title] and an
/// optional contributor `user:` link.
String _programWith({
  String title = 'Barn Dance',
  String? contributorHref,
  String? contributor,
}) {
  final userLine = (contributorHref != null && contributor != null)
      ? '<p>user: <strong><a href="$contributorHref">$contributor</a></strong></p>'
      : '';
  return '''
<html><body>
<div class="programs-show-content"><div class="container">
  <h1>$title</h1>
  $userLine
</div></div>
<div id="activity-1" class="activity-breakdown">
  <h2 class="activity-breakdown-dance-title"><a href="/dances/185">Courageous Soul</a></h2>
</div>
</body></html>
''';
}
