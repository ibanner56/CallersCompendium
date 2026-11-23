import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_program_pay_scope.dart';
import 'package:compendium_app/src/export/csv_export.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:compendium_app/src/screens/app_shell_search_scope.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'export/rfc4180_test_reader.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

/// Programs list ⋮ ▸ Export programs as CSV (#2333): the programs in the
/// current view, archived ones only while Show archived is on.
final _now = DateTime.utc(2026, 1, 1);

Program _program(String id, String title, {DateTime? archivedAt, int? pay}) =>
    Program(
      id: id,
      title: title,
      archivedAt: archivedAt,
      payMinorUnits: pay,
      payCurrency: pay == null ? null : 'USD',
      createdAt: _now,
      updatedAt: _now,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final compact in [false, true]) {
    final layout = compact ? 'compact' : 'wide';

    testWidgets('$layout: exports the listed programs, with pay, and the '
        'archived ones only while Show archived is on', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Alpha', pay: 10000));
      await repos.programs.create(
        _program('p2', 'Bravo', archivedAt: DateTime.utc(2026, 2, 1)),
      );
      await repos.programs.create(_program('p3', 'Charlie'));
      await repos.programs.softDelete('p3', at: DateTime.utc(2026, 3, 1));

      final exported = <String>[];
      final delivery = CsvExportDelivery(
        choicePicker: (context, {notice}) async => CsvExportChoice.save,
        saveInvoker: (csv, name) async {
          exported.add(csv);
          return JsonSaveResult(path: '', fileName: name);
        },
      );
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) {
            final scoped = RepositoriesScope(
              repositories: repos,
              child: child!,
            );
            return compact
                ? AppShellSearchScope(
                    searchPrograms: () async {},
                    child: scoped,
                  )
                : scoped;
          },
          home: ProgramsListScreen(csvExportDelivery: delivery),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> export() async {
        await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('programs-export-csv')));
        await tester.pumpAndSettle();
      }

      await export();
      expect(exported, hasLength(1));
      var rows = csvRecords(exported.last);
      expect(rows.map((r) => r['Title']), ['Alpha']);
      expect(rows.single['Pay'], '100.00');
      expect(rows.single['Currency'], 'USD');

      await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-toggle-archived')));
      await tester.pumpAndSettle();

      await export();
      rows = csvRecords(exported.last);
      expect(rows.map((r) => r['Title']), [
        'Alpha',
        'Bravo',
      ], reason: 'in the list\'s own order (title, ascending)');

      await tester.tap(find.byKey(const ValueKey('programs-sort-direction')));
      await tester.pumpAndSettle();
      await export();
      expect(csvRecords(exported.last).map((r) => r['Title']), [
        'Bravo',
        'Alpha',
      ], reason: 'the export follows the list when its order changes');
    });
  }

  for (final showPay in [true, false]) {
    testWidgets('with Show pay ${showPay ? 'on' : 'off'}, the dialog '
        '${showPay ? 'has no notice and the file has' : 'says pay is hidden and the file has no'} '
        'pay columns', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program('p1', 'Alpha', pay: 12345));
      String? saved;
      final showPayNotifier = ValueNotifier<bool>(showPay);
      addTearDown(showPayNotifier.dispose);
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ShowProgramPayScope(
              notifier: showPayNotifier,
              child: child!,
            ),
          ),
          home: ProgramsListScreen(
            // The real choice dialog, so its notice is what a caller sees.
            csvExportDelivery: CsvExportDelivery(
              saveInvoker: (csv, name) async {
                saved = csv;
                return JsonSaveResult(path: '', fileName: name);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programs-export-csv')));
      await tester.pumpAndSettle();

      final notice = find.byKey(const ValueKey('csv-export-notice'));
      if (showPay) {
        expect(notice, findsNothing);
      } else {
        expect(
          tester.widget<Text>(notice).data,
          startsWith('Pay is hidden in Settings'),
        );
      }
      await tester.tap(find.byKey(const ValueKey('csv-export-save')));
      await tester.pumpAndSettle();

      final header = readRfc4180(saved!).first;
      expect(header.contains('Pay'), showPay);
      expect(header.contains('Currency'), showPay);
      expect(saved!.contains('123.45'), showPay);
    });
  }

  testWidgets('the item is off while the list shows no program', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(
      _program('p1', 'Archived', archivedAt: DateTime.utc(2026, 2, 1)),
    );
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) =>
            RepositoriesScope(repositories: repos, child: child!),
        home: const ProgramsListScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('programs-more-actions')));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const ValueKey('programs-export-csv')),
    );
    expect(item.enabled, isFalse);
  });
}
