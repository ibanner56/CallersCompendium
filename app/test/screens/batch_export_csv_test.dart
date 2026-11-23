import 'package:compendium_app/src/export/csv_export.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../export/rfc4180_test_reader.dart';
import '../support/batch_screen_harness.dart';
import '../support/test_repositories.dart';

Dance _dance(String id, String title, {int? rating}) => Dance(
  id: id,
  title: title,
  rating: rating,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Collection selection mode, More batch actions ▸ Export as CSV (#2332).
void main() {
  testWidgets('exports exactly the selected dances, including one the search '
      'hides, and keeps selection mode open', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Alpha', rating: 5));
    await repos.dances.create(_dance('d2', 'Bravo'));
    await repos.dances.create(_dance('d3', 'Charlie'));

    String? csv;
    final delivery = CsvExportDelivery(
      choicePicker: (context, {notice}) async => CsvExportChoice.save,
      saveInvoker: (content, name) async {
        csv = content;
        return JsonSaveResult(path: '', fileName: name);
      },
    );
    await pumpBatchScreen(tester, repos, csvExportDelivery: delivery);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-checkbox-d3')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('collection-search-field')),
      'Charlie',
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing, reason: 'the search hides Alpha');

    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-export-csv')));
    await tester.pumpAndSettle();

    expect(csv, isNotNull);
    final rows = csvRecords(csv!);
    expect(rows.map((r) => r['Title']), ['Alpha', 'Charlie']);
    expect(rows.first['Rating'], '5');
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('the dialog offers Save, Share and Cancel, and Cancel exports '
      'nothing', (tester) async {
    final previous = isBundleShareUnsupported;
    isBundleShareUnsupported = () => false;
    addTearDown(() => isBundleShareUnsupported = previous);
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Alpha'));
    var saved = false;
    await pumpBatchScreen(
      tester,
      repos,
      csvExportDelivery: CsvExportDelivery(
        saveInvoker: (content, name) async {
          saved = true;
          return null;
        },
      ),
    );

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-export-csv')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('csv-export-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('csv-export-share')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('csv-export-cancel')));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
  });

  testWidgets('on Linux the second button reads Save as… and saves', (
    tester,
  ) async {
    final previous = isBundleShareUnsupported;
    isBundleShareUnsupported = () => true;
    addTearDown(() => isBundleShareUnsupported = previous);
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Alpha'));
    String? saved;
    var shared = false;
    await pumpBatchScreen(
      tester,
      repos,
      csvExportDelivery: CsvExportDelivery(
        saveInvoker: (content, name) async {
          saved = name;
          return JsonSaveResult(path: '', fileName: name);
        },
        shareInvoker: (params) async => shared = true,
      ),
    );

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-export-csv')));
    await tester.pumpAndSettle();

    final second = find.byKey(const ValueKey('csv-export-share'));
    expect(
      find.descendant(of: second, matching: find.text('Save as…')),
      findsOneWidget,
    );
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(saved, endsWith('.csv'));
    expect(shared, isFalse);
  });

  testWidgets('a failing save is logged and shown, not swallowed', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('d1', 'Alpha'));
    await pumpBatchScreen(
      tester,
      repos,
      csvExportDelivery: CsvExportDelivery(
        choicePicker: (context, {notice}) async => CsvExportChoice.save,
        saveInvoker: (content, name) async => throw StateError('disk full'),
      ),
    );

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-export-csv')));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't save this spreadsheet. Try again."),
      findsOneWidget,
    );
  });
}
