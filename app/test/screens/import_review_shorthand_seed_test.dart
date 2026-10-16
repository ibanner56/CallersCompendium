import 'dart:typed_data';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fmp_fixture_builder.dart';
import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A `.USR` with one dance and two parseable Insert Call buttons (own generic
/// contra phrasing; column names copied from the real schema).
Uint8List _usrWithCallButtons() => buildFmp12Fixture([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['zk_Dance_ID', 'Name', 'Author1'],
    rows: [
      MapEntry(10, {1: '4', 2: 'Simplicity Swing', 3: 'Becky Hill'}),
    ],
  ),
  FmpFixtureTable(
    index: 2,
    name: 'InsertCall',
    columnNames: [
      'InsertButtonLabel',
      'InsertButtonText',
      'zk_Constant',
      'InsertButtonBeats',
    ],
    rows: [
      MapEntry(900, {
        1: 'B&S-N',
        2: 'neighbor balance and swing',
        3: '1',
        4: '16',
      }),
      MapEntry(903, {1: 'Circle', 2: 'circle left 3/4', 3: '1', 4: '8'}),
    ],
  ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seeding shorthands after Done on the result dialog saves them '
      'and shows the completion snackbar (#1819)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    expect(controller.mappings, isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: dialect,
            child: ShorthandMappingsScope(
              controller: controller,
              child: child!,
            ),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('launch'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImportReviewScreen(
                    sources: [
                      ImportSource(
                        kind: ImportSourceKind.callersCompanionUsr,
                        adapterFactory: CallersCompanionUsrAdapter.new,
                        bytePicker: () async => _usrWithCallButtons(),
                      ),
                    ],
                    picker: () async => '',
                    bytePicker: () async => _usrWithCallButtons(),
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('import-choose-usr-file')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-commit-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-result-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-done-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('seed-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('seed-confirm')));
    await tester.pumpAndSettle();

    expect(controller.mappings, hasLength(2));
    expect(
      find.byKey(const ValueKey('shorthand-seed-complete')),
      findsOneWidget,
    );
  });
}
