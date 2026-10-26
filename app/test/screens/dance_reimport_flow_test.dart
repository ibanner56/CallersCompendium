import 'dart:convert';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/callersbox_online.dart';
import 'package:compendium_app/src/data/contradb_online.dart';
import 'package:compendium_app/src/data/dance_reimport.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_reimport_flow.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Caller's Box dance JSON, trimmed to what [CallersBoxAdapter] reads.
String _tcbJson({String permission = 'full'}) => jsonEncode({
  'ID': '1605',
  'Name': 'A-1 Reel',
  'Authors': ['Chris Weiler'],
  'Permission': permission,
  'FormationBase': 'Duple Minor - Becket',
  'Progression': 'Single',
  'phrases': permission == 'full'
      ? [
          {
            'name': 'A1',
            'figures': ['(8) Long lines forward and back'],
          },
        ]
      : <Object>[],
});

/// A ContraDB dance page without a figures table: a metadata-only stub.
const String _contraDbNoFiguresHtml = '''
<!DOCTYPE html><html><head><title>x</title></head>
<body class="dances-show-body">
<h1 class="dance-show-title">The Rendezvous</h1>
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Adina Gordon</a></strong></p>
<p class="dance-show-formation">formation: improper </p>
</body></html>
''';

const String _contraDbHtml = '''
<!DOCTYPE html><html><head><title>x</title></head>
<body class="dances-show-body">
<h1 class="dance-show-title">The Rendezvous</h1>
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Adina Gordon</a></strong></p>
<p class="dance-show-formation">formation: improper </p>
<table class="table table-bordered table-condensed contra-table-nonfluid">
  <tr class="a1b1 dance-show-long-figure">
    <td>A1</td><td class=dance-show-beats>16</td>
    <td><div class="show-figure">neighbors balance &amp; swing</div></td>
  </tr>
</table>
</body></html>
''';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

class _Fetches {
  final tcb = <String>[];
  final contraDb = <String>[];
  final searches = <String>[];
}

void main() {
  late CompendiumRepositories repos;
  late Dance saved;
  late _Fetches fetches;

  setUp(() async {
    repos = openTestRepositories();
    fetches = _Fetches();
    final stamp = DateTime.utc(2026);
    saved = Dance(
      id: 'saved',
      title: 'A1 Reel',
      callingNotes: 'My notes',
      figures: [
        testFigure(move: customMove, params: {'text': 'old'}),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    );
    await repos.dances.create(saved);
  });

  Future<void> pumpHost(
    WidgetTester tester, {
    Future<String> Function(String url)? tcbJson,
    Future<String> Function(String url)? tcbSearch,
    String contraDbHtml = _contraDbHtml,
  }) async {
    final coordinator = DanceReimportCoordinator(
      repos: repos,
      callersBox: CallersBoxOnline(
        jsonFetcher: (url) async {
          fetches.tcb.add(url);
          return tcbJson == null ? _tcbJson() : tcbJson(url);
        },
        searchFetcher: (url) async {
          fetches.searches.add(url);
          if (tcbSearch == null) throw StateError('unexpected search');
          return tcbSearch(url);
        },
      ),
      contraDb: ContraDbOnline(
        htmlFetcher: (url) async {
          fetches.contraDb.add(url);
          return contraDbHtml;
        },
        searchFetcher: (_) async => throw StateError('unexpected search'),
      ),
    );
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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open-reimport'),
              onPressed: () =>
                  coordinator.open(context, reimportPreviewData(saved)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openLinkDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-reimport')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reimport-source-link')));
    await tester.pumpAndSettle();
  }

  Future<void> fetchLink(WidgetTester tester, String input) async {
    await tester.enterText(
      find.byKey(const ValueKey('reimport-link-field')),
      input,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reimport-link-fetch')));
    await tester.pumpAndSettle();
  }

  testWidgets('a Caller\'s Box link re-imports figures, formation and '
      'progression, and keeps the saved title and notes', (tester) async {
    await pumpHost(tester);
    await openLinkDialog(tester);
    await fetchLink(
      tester,
      'https://ibiblio.org/contradance/thecallersbox/dance.php?id=1605',
    );

    // The service rebuilt its own canonical endpoint from the validated id.
    expect(fetches.tcb, [
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1605&format=JSON',
    ]);
    expect(fetches.searches, isEmpty);

    await tester.tap(find.byKey(const ValueKey('import-dance')));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.danceReimported), findsOneWidget);

    final after = (await repos.dances.getById('saved'))!;
    expect(after.title, 'A1 Reel');
    expect(after.callingNotes, 'My notes');
    expect(
      after.formation.shape,
      anyOf(FormationShape.becketCw, FormationShape.becketCcw),
    );
    final figures = (after.figuresSource as DecodedFigures).figures;
    expect(figures, isNotEmpty);
    expect(figures.first.move, isNot(customMove));
  });

  testWidgets('a bare id uses the selected source', (tester) async {
    await pumpHost(tester);
    await openLinkDialog(tester);
    await tester.tap(
      find.byKey(const ValueKey('reimport-link-source-contraDb')),
    );
    await tester.pumpAndSettle();
    await fetchLink(tester, '7');

    expect(fetches.contraDb, ['https://contradb.com/dances/7']);
    expect(fetches.tcb, isEmpty);
    expect(find.byKey(const ValueKey('import-dance')), findsOneWidget);
  });

  testWidgets('a pasted ContraDB link selects ContraDB itself', (tester) async {
    await pumpHost(tester);
    await openLinkDialog(tester);
    await fetchLink(tester, 'https://contradb.com/dances/42?x=1#top');

    expect(fetches.contraDb, ['https://contradb.com/dances/42']);
    expect(fetches.tcb, isEmpty);
  });

  testWidgets('a pasted link wins over an earlier manual choice', (
    tester,
  ) async {
    await pumpHost(tester);
    await openLinkDialog(tester);
    await tester.tap(
      find.byKey(const ValueKey('reimport-link-source-contraDb')),
    );
    await tester.pumpAndSettle();
    await fetchLink(
      tester,
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1605',
    );

    expect(fetches.tcb, hasLength(1));
    expect(fetches.contraDb, isEmpty);
  });

  testWidgets('a ContraDB page without figures is refused too', (tester) async {
    await pumpHost(tester, contraDbHtml: _contraDbNoFiguresHtml);
    await openLinkDialog(tester);
    await fetchLink(tester, 'https://contradb.com/dances/7');

    expect(fetches.contraDb, hasLength(1));
    expect(find.text(_l10n.danceReimportFiguresUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('import-dance')), findsNothing);
  });

  testWidgets('a foreign host is reported inline and never fetched', (
    tester,
  ) async {
    await pumpHost(tester);
    await openLinkDialog(tester);
    await fetchLink(tester, 'https://example.com/dance.php?id=1605');

    expect(
      find.text(_l10n.importErrorCallersBoxUnsupportedHost),
      findsOneWidget,
    );
    expect(fetches.tcb, isEmpty);
    expect(fetches.contraDb, isEmpty);
    // Still open, so the user can correct it.
    expect(find.byKey(const ValueKey('reimport-link-field')), findsOneWidget);
  });

  testWidgets(
    'a missing Caller\'s Box id reads as that, not as a status code',
    (tester) async {
      await pumpHost(
        tester,
        tcbJson: (_) async => throw const UrlFetchException(
          UrlFetchFailureReason.httpStatus,
          statusCode: 404,
        ),
      );
      await openLinkDialog(tester);
      await fetchLink(tester, '99999999');

      expect(
        find.text(_l10n.importErrorCallersBoxHttpNotFound),
        findsOneWidget,
      );
      expect(find.text(_l10n.danceReimportSourceFailed), findsNothing);
    },
  );

  testWidgets('a title search that cannot reach the source says so', (
    tester,
  ) async {
    await pumpHost(
      tester,
      tcbSearch: (_) async =>
          throw const UrlFetchException(UrlFetchFailureReason.unreachable),
    );
    await tester.tap(find.byKey(const ValueKey('open-reimport')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reimport-source-callersBox')));
    await tester.pumpAndSettle();

    expect(fetches.searches, hasLength(1));
    expect(find.text(_l10n.importErrorCallersBoxUnreachable), findsOneWidget);
    expect(find.text(_l10n.danceReimportSourceFailed), findsNothing);
  });

  testWidgets('a dance whose figures the source withholds is refused and '
      'the saved figures are untouched', (tester) async {
    await pumpHost(
      tester,
      tcbJson: (_) async => _tcbJson(permission: 'search'),
    );
    await openLinkDialog(tester);
    await fetchLink(tester, '1605');

    expect(find.text(_l10n.danceReimportFiguresUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('import-dance')), findsNothing);
    final after = (await repos.dances.getById('saved'))!;
    expect(
      (after.figuresSource as DecodedFigures).figures.single.params['text'],
      'old',
    );
  });

  testWidgets('cancelling the link dialog fetches nothing', (tester) async {
    await pumpHost(tester);
    await openLinkDialog(tester);
    await tester.tap(find.text(_l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(fetches.tcb, isEmpty);
    expect(fetches.contraDb, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('dance id resolvers', () {
    test("Caller's Box: bare id, link, and the typed rejections", () {
      expect(callersBoxDanceIdFromInput(' 1605 '), '1605');
      expect(
        callersBoxDanceIdFromInput(
          'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1606&format=JSON',
        ),
        '1606',
      );
      for (final (input, reason) in [
        (
          'https://ibiblio.org/contradance/thecallersbox/dance.php?id=abc',
          UrlFetchFailureReason.callersBoxMissingId,
        ),
        // Another page's id would silently load whichever dance has it.
        (
          'https://ibiblio.org/contradance/thecallersbox/index.php?id=12',
          UrlFetchFailureReason.callersBoxMissingId,
        ),
        (
          'http://ibiblio.org/contradance/thecallersbox/dance.php?id=1',
          UrlFetchFailureReason.insecureScheme,
        ),
        (
          'https://ibiblio.org.evil.com/contradance/thecallersbox/dance.php?id=1',
          UrlFetchFailureReason.callersBoxUnsupportedHost,
        ),
        ('', UrlFetchFailureReason.callersBoxEmptyInput),
      ]) {
        expect(
          () => callersBoxDanceIdFromInput(input),
          throwsA(
            isA<UrlFetchException>().having((e) => e.reason, 'reason', reason),
          ),
          reason: input,
        );
      }
    });

    test('ContraDB: bare id, link, and the typed rejections', () {
      expect(contraDbDanceIdFromInput('7'), '7');
      expect(
        contraDbDanceIdFromInput('https://www.contradb.com/dances/7/?x=1'),
        '7',
      );
      expect(
        () => contraDbDanceIdFromInput('https://contradb.com/programs/33'),
        throwsA(
          isA<UrlFetchException>().having(
            (e) => e.reason,
            'reason',
            UrlFetchFailureReason.contraDbMissingDanceId,
          ),
        ),
      );
    });
  });
}
