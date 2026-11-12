import 'dart:typed_data';

import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ImportFilePicker filePicker,
}) async {
  final repos = openTestRepositories();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: RepositoriesScope(
        repositories: repos,
        child: ImportReviewScreen(
          sources: defaultImportSources(),
          filePicker: filePicker,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);

DropdownButton<ImportSource> _dropdown(WidgetTester tester) =>
    tester.widget<DropdownButton<ImportSource>>(
      find.byKey(const ValueKey('import-source-select')),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('importSourceKindForFileName', () {
    test('recognizes .ccshare and .usr case-insensitively', () {
      expect(
        importSourceKindForFileName('x.ccshare'),
        ImportSourceKind.genericJson,
      );
      expect(
        importSourceKindForFileName('Library.CCSHARE'),
        ImportSourceKind.genericJson,
      );
      expect(
        importSourceKindForFileName('Backup.USR'),
        ImportSourceKind.callersCompanionUsr,
      );
    });

    test('does not claim plain json or unknown files', () {
      expect(importSourceKindForFileName('dance.json'), isNull);
      expect(importSourceKindForFileName('notes.txt'), isNull);
      expect(importSourceKindForFileName('ccshare'), isNull);
    });
  });

  testWidgets('picking a .ccshare while on The Caller\'s Box switches source', (
    tester,
  ) async {
    await _pump(
      tester,
      filePicker: () async =>
          PickedImportFile(name: 'x.ccshare', bytes: _bytes('{}')),
    );
    expect(_dropdown(tester).value!.kind, ImportSourceKind.callersBox);

    await tester.tap(find.byKey(const ValueKey('import-choose-file')));
    await tester.pumpAndSettle();

    expect(_dropdown(tester).value!.kind, ImportSourceKind.genericJson);
  });

  testWidgets('picking a .usr switches to the Companion source with bytes', (
    tester,
  ) async {
    await _pump(
      tester,
      filePicker: () async =>
          PickedImportFile(name: 'Lib.USR', bytes: _bytes('not really')),
    );
    await tester.tap(find.byKey(const ValueKey('import-choose-file')));
    await tester.pumpAndSettle();

    expect(_dropdown(tester).value!.kind, ImportSourceKind.callersCompanionUsr);
    expect(find.byKey(const ValueKey('import-usr-chosen')), findsOneWidget);
  });

  testWidgets('picking a plain .json leaves the selected source alone', (
    tester,
  ) async {
    await _pump(
      tester,
      filePicker: () async =>
          PickedImportFile(name: 'dance.json', bytes: _bytes('{}')),
    );
    await tester.tap(find.byKey(const ValueKey('import-choose-file')));
    await tester.pumpAndSettle();

    expect(_dropdown(tester).value!.kind, ImportSourceKind.callersBox);
  });
}
