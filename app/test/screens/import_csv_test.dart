import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// Import ▸ Your own spreadsheet (CSV) (#2329), end to end in the review
/// screen.
void main() {
  Future<CompendiumRepositories> pump(
    WidgetTester tester,
    Uint8List bytes,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
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
        home: ImportReviewScreen(
          sources: [
            ImportSource(
              kind: ImportSourceKind.csv,
              adapterFactory: CsvAdapter.new,
              bytePicker: () async => bytes,
            ),
          ],
          picker: () async => '',
          bytePicker: () async => bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-continue')));
    await tester.pumpAndSettle();
    return repos;
  }

  CsvColumnMapping? columnValue(WidgetTester tester, int i) => tester
      .widget<DropdownButton<CsvColumnMapping>>(
        find.byKey(ValueKey('csv-column-$i')),
      )
      .value;

  testWidgets('maps the columns, lets one be ignored, and imports what the '
      'review confirms, with no provenance', (tester) async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '\uFEFFTitle;Authors;Calling notes;Mystery\r\n'
        '"Rory O\'More";Pat Shaw;"Keep this out";42\r\n',
      ),
    );
    final repos = await pump(tester, bytes);

    expect(find.byKey(const ValueKey('csv-mapping')), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('csv-separator')),
          )
          .initialValue,
      ';',
      reason: 'the separator is detected from the header line',
    );
    expect(
      columnValue(tester, 0),
      const CsvColumnMapping(CsvColumnTarget.title),
    );
    expect(
      columnValue(tester, 1),
      const CsvColumnMapping(CsvColumnTarget.authors),
    );
    expect(
      columnValue(tester, 2),
      const CsvColumnMapping(CsvColumnTarget.callingNotes),
    );
    expect(columnValue(tester, 3), CsvColumnMapping.ignore);

    // Ignore the notes column.
    await tester.tap(find.byKey(const ValueKey('csv-column-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignore').last);
    await tester.pumpAndSettle();
    expect(columnValue(tester, 2), CsvColumnMapping.ignore);

    await tester.tap(find.byKey(const ValueKey('csv-continue')));
    await tester.pumpAndSettle();
    expect(find.text("Rory O'More"), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final dances = await tester.runAsync(repos.dances.listAll);
    expect(dances!, hasLength(1));
    final dance = dances.single;
    expect(dance.title, "Rory O'More");
    expect(dance.callingNotes, isEmpty, reason: 'the column was ignored');
    expect(dance.provenance, isNull);
    final people = await tester.runAsync(repos.choreographers.listAll);
    expect(
      people!.where((c) => dance.authorIds.contains(c.id)).map((c) => c.name),
      ['Pat Shaw'],
    );
  });

  testWidgets('Continue waits for a Title column', (tester) async {
    await pump(
      tester,
      Uint8List.fromList(utf8.encode('Petronella,Swing\r\nRory,Balance\r\n')),
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('csv-has-header')))
          .value,
      isFalse,
      reason: 'a first row of values is not a header',
    );
    expect(find.byKey(const ValueKey('csv-needs-title')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('csv-continue')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a file that is not UTF-8 is refused with a message, and '
      'nothing is planned', (tester) async {
    // "Café" in Windows-1252.
    await pump(tester, Uint8List.fromList([0x43, 0x61, 0x66, 0xE9]));
    expect(find.byKey(const ValueKey('import-csv-unreadable')), findsOneWidget);
    expect(find.textContaining('CSV UTF-8'), findsWidgets);
    expect(find.byKey(const ValueKey('csv-mapping')), findsNothing);
  });

  testWidgets('a file with too many rows says so, and offers no Continue', (
    tester,
  ) async {
    final text = 'Title\r\n${List.filled(kMaxCsvImportRows, 'x').join('\r\n')}';
    await pump(tester, Uint8List.fromList(utf8.encode(text)));
    expect(find.byKey(const ValueKey('csv-read-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('csv-continue')), findsNothing);
  });

  testWidgets('nothing is written before commit, and a dance you already '
      'have defaults to Skip', (tester) async {
    final bytes = Uint8List.fromList(
      utf8.encode('Title,Authors\r\nPetronella,Pat Shaw\r\nNew One,\r\n'),
    );
    late CompendiumRepositories repos;
    // Seed the library through a first import of the same row.
    repos = await pump(
      tester,
      Uint8List.fromList(
        utf8.encode('Title,Authors\r\nPetronella,Pat Shaw\r\n'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('csv-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(repos.dances.listAll))!, hasLength(1));

    // The same library, the bigger sheet: planned, then reviewed.
    await tester.pumpWidget(const SizedBox());
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
        home: ImportReviewScreen(
          sources: [
            ImportSource(
              kind: ImportSourceKind.csv,
              adapterFactory: CsvAdapter.new,
              bytePicker: () async => bytes,
            ),
          ],
          picker: () async => '',
          bytePicker: () async => bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('csv-continue')));
    await tester.pumpAndSettle();
    expect(
      (await tester.runAsync(repos.dances.listAll))!,
      hasLength(1),
      reason: 'planning writes nothing',
    );
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    final titles = (await tester.runAsync(
      repos.dances.listAll,
    ))!.map((d) => d.title).toList();
    expect(titles..sort(), [
      'New One',
      'Petronella',
    ], reason: 'the possible match was skipped by default, not duplicated');
  });

  testWidgets('Import and edit on a row with tags resolves them as the batch '
      'import does', (tester) async {
    final repos = await pump(
      tester,
      Uint8List.fromList(
        utf8.encode('Title,Tags\r\nPetronella,"Jig, Favourite"\r\n'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('csv-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-row-0-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-edit-error')), findsNothing);
    final dance = (await tester.runAsync(repos.dances.listAll))!.single;
    final tags = (await tester.runAsync(repos.tags.listAll))!;
    expect(
      tags.where((t) => dance.tagIds.contains(t.id)).map((t) => t.name).toSet(),
      {'Jig', 'Favourite'},
    );
  });

  testWidgets('Back on the map-columns step returns to choosing a file', (
    tester,
  ) async {
    await pump(
      tester,
      Uint8List.fromList(utf8.encode('Title\r\nPetronella\r\n')),
    );
    await tester.tap(find.byKey(const ValueKey('csv-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('csv-mapping')), findsNothing);
    expect(
      find.byKey(const ValueKey('import-choose-usr-file')),
      findsOneWidget,
    );
  });

  testWidgets('too many columns, or a cell over the limit, says so', (
    tester,
  ) async {
    await pump(
      tester,
      Uint8List.fromList(
        utf8.encode(List.filled(kMaxCsvImportColumns + 1, 'c').join(',')),
      ),
    );
    expect(find.byKey(const ValueKey('csv-read-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('csv-back')));
    await tester.pumpAndSettle();
  });

  testWidgets('a cell over the limit says so', (tester) async {
    await pump(
      tester,
      Uint8List.fromList(
        utf8.encode('Title\r\n${'x' * (kMaxCsvImportCellChars + 1)}\r\n'),
      ),
    );
    expect(find.byKey(const ValueKey('csv-read-error')), findsOneWidget);
  });

  testWidgets('a file with only its column names says so', (tester) async {
    await pump(tester, Uint8List.fromList(utf8.encode('Title,Authors\r\n')));
    expect(find.byKey(const ValueKey('csv-no-rows')), findsOneWidget);
  });
}
