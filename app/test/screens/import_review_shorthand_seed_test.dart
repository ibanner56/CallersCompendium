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
/// contra phrasing; column names copied from the real schema), plus any
/// [extraButtons] as `(label, text, beats)`.
Uint8List _usrWithCallButtons({
  List<(String, String, String)> extraButtons = const [],
}) => buildFmp12Fixture([
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
      for (final (i, (label, text, beats)) in extraButtons.indexed)
        MapEntry(910 + i, {1: label, 2: text, 3: '1', 4: beats}),
    ],
  ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Opens [ImportReviewScreen] over [usr], imports it, and taps Done on the
  /// result dialog, which brings up the shorthand seeding screen (#1819).
  Future<void> importToSeedScreen(
    WidgetTester tester, {
    required CompendiumRepositories repos,
    required ShorthandMappingsController controller,
    required Uint8List usr,
  }) async {
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
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
                        bytePicker: () async => usr,
                      ),
                    ],
                    picker: () async => '',
                    bytePicker: () async => usr,
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
  }

  testWidgets('seeding shorthands after Done on the result dialog saves them '
      'and shows the completion snackbar (#1819)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    expect(controller.mappings, isEmpty);

    await importToSeedScreen(
      tester,
      repos: repos,
      controller: controller,
      usr: _usrWithCallButtons(),
    );
    expect(find.byKey(const ValueKey('seed-confirm')), findsOneWidget);
    // Everything read cleanly and there is room: no notes on the screen.
    expect(find.byKey(const ValueKey('seed-unreadable-note')), findsNothing);
    expect(find.byKey(const ValueKey('seed-room-hint')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('seed-confirm')));
    await tester.pumpAndSettle();

    expect(controller.mappings, hasLength(2));
    expect(
      find.byKey(const ValueKey('shorthand-seed-complete')),
      findsOneWidget,
    );
  });

  // #1830: buttons that do not read as figures were left out without a word.
  testWidgets('the seeding screen says how many buttons were left out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    final controller = ShorthandMappingsController(repos.settings);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);

    await importToSeedScreen(
      tester,
      repos: repos,
      controller: controller,
      usr: _usrWithCallButtons(
        extraButtons: [
          ('Zork', 'frobnicate the quux', '8'),
          ('Blarg', 'wibble the wobble', '8'),
        ],
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('seed-unreadable-note')),
        matching: find.textContaining('2 call buttons'),
      ),
      findsOneWidget,
    );
  });

  // #1830 (leftovers of #1839): seeding past the 500-shorthand cap.
  group('at the shorthand cap', () {
    Future<(CompendiumRepositories, ShorthandMappingsController)> nearlyFull(
      WidgetTester tester,
      int saved,
    ) async {
      final repos = openTestRepositories();
      final controller = ShorthandMappingsController(repos.settings);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.load();
        for (var i = 0; i < saved; i++) {
          await controller.upsert(
            ShorthandMapping(
              token: 'saved$i',
              figures: [
                Figure(move: 'swing', params: const {'beats': 16}),
              ],
            ),
          );
        }
      });
      return (repos, controller);
    }

    testWidgets('the screen hints at the free slots, and one message reports '
        'what was seeded and what was skipped', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Room for exactly one of the two call buttons.
      final (repos, controller) = await nearlyFull(
        tester,
        maxShorthandMappings - 1,
      );

      await importToSeedScreen(
        tester,
        repos: repos,
        controller: controller,
        usr: _usrWithCallButtons(),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('seed-room-hint')),
          matching: find.textContaining('room for 1 more'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('seed-confirm')));
      await tester.pumpAndSettle();

      expect(controller.mappings, hasLength(maxShorthandMappings));
      // One snackbar, not a limit message followed by a "Seeded N" one.
      expect(find.byType(SnackBar), findsOneWidget);
      final message = find.byKey(
        const ValueKey('shorthand-seed-limit-reached'),
      );
      expect(message, findsOneWidget);
      expect(
        find.descendant(of: message, matching: find.textContaining('Seeded 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: message,
          matching: find.textContaining('1 shorthand was not added'),
        ),
        findsOneWidget,
      );
    });
  });
}
