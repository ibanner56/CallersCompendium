import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/contradb_program_import_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

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
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          RepositoriesScope(repositories: repos, child: child!),
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
}
