import 'dart:convert';
import 'dart:typed_data';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../figures_support.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

const _markdown = '''
# My dances

## Rory's Reel

by Pat Example
Formation: Becket (CW)
Music: Any reel

- A1 (8) Neighbor balance & swing
- (8) Long lines forward and back

## Second Dance

Formation: Improper

1. A1 (16) Neighbor swing
''';

/// Import ▸ Your own text or Markdown file (#2330), end to end in the review
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
              kind: ImportSourceKind.textDocument,
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
      .widget<AppDropdownField<CsvColumnMapping>>(
        find.byKey(ValueKey('csv-column-$i')),
      )
      .initialValue;

  testWidgets('maps the labels, keeps an unmapped one in the notes with its '
      'label, and imports with no provenance', (tester) async {
    final repos = await pump(
      tester,
      Uint8List.fromList(utf8.encode(_markdown)),
    );

    expect(find.text('Map labels'), findsOneWidget);
    // The separator and header row are fixed for a text file.
    expect(find.byKey(const ValueKey('csv-separator')), findsNothing);
    expect(find.byKey(const ValueKey('csv-has-header')), findsNothing);
    // Title, Author, Formation, Music, Calling notes, Figures.
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
      const CsvColumnMapping(CsvColumnTarget.formation),
    );
    expect(columnValue(tester, 3), CsvColumnMapping.labelledNotes);
    expect(find.text('Calling notes, with the label'), findsOneWidget);
    expect(
      columnValue(tester, 5),
      const CsvColumnMapping(CsvColumnTarget.figures),
    );

    await tester.tap(find.byKey(const ValueKey('csv-continue')));
    await tester.pumpAndSettle();
    expect(find.text("Rory's Reel"), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();

    final dances = (await tester.runAsync(repos.dances.listAll))!;
    expect(
      dances.map((d) => d.title),
      unorderedEquals(["Rory's Reel", 'Second Dance']),
    );
    final rory = dances.firstWhere((d) => d.title == "Rory's Reel");
    expect(rory.formation.shape, FormationShape.becketCw);
    expect(rory.callingNotes, 'Music: Any reel');
    expect(rory.provenance, isNull);
    expect(figuresOf(rory), hasLength(2));
    expect(figuresOf(rory).where((f) => f.isCustom), isEmpty);
  });

  testWidgets('choosing where dances start reads the file again: one '
      'dance in ## parts comes in as that one dance', (tester) async {
    const parts =
        "# Rory's Reel\n\n## Figures\n(8) Neighbor swing\n\n"
        '## Variations\n(8) Long lines\n';
    final repos = await pump(tester, Uint8List.fromList(utf8.encode(parts)));
    AppDropdownField<int> start() => tester.widget<AppDropdownField<int>>(
      find.byKey(const ValueKey('text-dance-start')),
    );
    // The guess reads the parts as dances; the file's own choices are its
    // heading levels and blank lines.
    expect(start().initialValue, 2);
    expect(find.text('A ## heading'), findsOneWidget);

    start().onChanged!(1);
    await tester.pumpAndSettle();
    expect(start().initialValue, 1);

    await tester.tap(find.byKey(const ValueKey('csv-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    final dance = (await tester.runAsync(repos.dances.listAll))!.single;
    expect(dance.title, "Rory's Reel");
    expect(figuresOf(dance), hasLength(2));
  });

  testWidgets('a file with no headings offers no choice of where dances '
      'start', (tester) async {
    await pump(
      tester,
      Uint8List.fromList(utf8.encode('Chorus Jig\n(8) Swing\n')),
    );
    expect(find.byKey(const ValueKey('csv-mapping')), findsOneWidget);
    expect(find.byKey(const ValueKey('text-dance-start')), findsNothing);
  });

  testWidgets('a choice that reads past the dance cap is refused with a '
      'message, and the last reading stays', (tester) async {
    // Three # dances whose notes, read as titles after blank lines, would
    // be one dance more than the cap.
    const perDance = (kMaxTextDocumentDances + 1) ~/ 3 + 1;
    final text = [
      for (var d = 0; d < 3; d++) ...[
        '# Dance $d',
        for (var i = 0; i < perDance; i++) 'N$i\n',
      ],
    ].join('\n');
    await pump(tester, Uint8List.fromList(utf8.encode(text)));
    AppDropdownField<int> start() => tester.widget<AppDropdownField<int>>(
      find.byKey(const ValueKey('text-dance-start')),
    );
    expect(start().initialValue, 1);
    start().onChanged!(0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('import-text-unreadable')),
      findsOneWidget,
    );
    expect(start().initialValue, 1);
    expect(find.byKey(const ValueKey('csv-mapping')), findsOneWidget);
  });

  testWidgets('a file that is not UTF-8 is refused with a message, and '
      'nothing is mapped', (tester) async {
    await pump(
      tester,
      Uint8List.fromList([0x54, 0x0A, 0x63, 0x61, 0x66, 0xE9]),
    );
    expect(
      find.byKey(const ValueKey('import-text-unreadable')),
      findsOneWidget,
    );
    expect(find.textContaining('UTF-8 text'), findsOneWidget);
    expect(find.byKey(const ValueKey('csv-mapping')), findsNothing);
  });

  testWidgets('a file with too many dances is refused with a message', (
    tester,
  ) async {
    final text = List.generate(
      kMaxTextDocumentDances + 1,
      (i) => '## D$i',
    ).join('\n');
    await pump(tester, Uint8List.fromList(utf8.encode(text)));
    expect(
      find.byKey(const ValueKey('import-text-unreadable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('csv-mapping')), findsNothing);
  });

  test('the picker offers .txt and .md only, and the file names map to '
      'this source', () {
    final group = importTextDocumentTypeGroup(isLinux: false);
    expect(group.extensions, ['txt', 'md']);
    expect(
      importSourceKindForFileName('Dances.MD'),
      ImportSourceKind.textDocument,
    );
    expect(
      importSourceKindForFileName('notes.txt'),
      ImportSourceKind.textDocument,
    );
    expect(importSourceKindForFileName('notes.docx'), isNull);
  });
}
