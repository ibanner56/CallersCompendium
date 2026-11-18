// Leaving Perform and the dialogs and sheets it opens: the exit confirmation
// can be turned off in Settings, and every Perform dialog and sheet renders in
// the stage theme the caller is looking at rather than the app theme behind it.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart'
    show kConfirmPerformExitKey, kPerformStageModeKey;
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/theme/app_theme.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);
final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  figures: [
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
  ],
  status: DanceStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

Program _program() => Program(
  id: 'p1',
  title: 'Spring Dance',
  slots: [
    ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
    ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
  ],
  createdAt: _now,
  updatedAt: _now,
);

/// The two Perform surfaces, each with the key of its close control.
enum _Surface {
  dance('exit-perform'),
  program('perform-program-exit');

  const _Surface(this.exitKey);
  final String exitKey;
}

/// A settings store whose read of the exit setting waits for [gate], when one
/// is given, and then fails when [fail] is set. Other keys read normally.
class _ExitSettings extends SettingsRepository {
  _ExitSettings(super.db, {this.gate, this.fail = false});

  final Completer<void>? gate;
  final bool fail;

  @override
  Future<Object?> get(String key) async {
    if (key == kConfirmPerformExitKey) {
      if (gate != null) await gate!.future;
      if (fail) throw StateError('settings store unavailable');
    }
    return super.get(key);
  }
}

/// Pushes [surface] over a home route under a *light* app theme, so a dialog
/// that escaped the stage theme would show as light.
Future<void> _pushPerform(
  WidgetTester tester,
  _Surface surface, {
  bool? confirmExit,
  bool stageMode = true,
  Completer<void>? exitReadGate,
  bool exitReadFails = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = openWidgetTestDatabase();
  final repos = CompendiumRepositories(
    db,
    contraTaxonomy,
    settings: _ExitSettings(db, gate: exitReadGate, fail: exitReadFails),
  );
  final dances = [_dance('d1', 'First Dance'), _dance('d2', 'Second Dance')];
  for (final d in dances) {
    await repos.dances.create(d);
  }
  if (confirmExit != null) {
    await repos.settings.set(kConfirmPerformExitKey, confirmExit);
  }
  await repos.settings.set(kPerformStageModeKey, stageMode);
  final data = await CollectionData.load(repos);
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-perform'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => switch (surface) {
                  _Surface.dance => PerformDanceScreen(
                    dance: dances.first,
                    renderer: _renderer,
                  ),
                  _Surface.program => PerformProgramScreen(
                    program: _program(),
                    data: data,
                    renderer: _renderer,
                  ),
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-perform')));
  await tester.pumpAndSettle();
}

bool _performShowing() =>
    find.byType(PerformDanceScreen).evaluate().isNotEmpty ||
    find.byType(PerformProgramScreen).evaluate().isNotEmpty;

final _exitDialog = find.byKey(const ValueKey('perform-exit-dialog'));

/// The theme the widget found by [finder] is drawn with.
ThemeData _themeOf(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFakeWakelock);

  for (final surface in _Surface.values) {
    group('${surface.name} Perform exit', () {
      testWidgets('asks before leaving by default', (tester) async {
        await _pushPerform(tester, surface);

        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();
        expect(_exitDialog, findsOneWidget);
        expect(_performShowing(), isTrue);

        await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
        await tester.pumpAndSettle();
        expect(_performShowing(), isFalse);
      });

      testWidgets('leaves at once from the close control when the setting is '
          'off', (tester) async {
        await _pushPerform(tester, surface, confirmExit: false);

        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();
        expect(_exitDialog, findsNothing);
        expect(_performShowing(), isFalse);
        expect(find.byKey(const ValueKey('open-perform')), findsOneWidget);
      });

      testWidgets('leaves at once on system Back when the setting is off', (
        tester,
      ) async {
        await _pushPerform(tester, surface, confirmExit: false);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(_exitDialog, findsNothing);
        expect(_performShowing(), isFalse);
      });

      testWidgets('the route is poppable, so gesture back works, only when '
          'the setting is off', (tester) async {
        await _pushPerform(tester, surface, confirmExit: false);
        final route = ModalRoute.of(
          tester.element(find.byKey(ValueKey(surface.exitKey))),
        )!;
        expect(route.popDisposition, RoutePopDisposition.pop);
      });

      testWidgets('the route blocks a gesture pop while the setting is on', (
        tester,
      ) async {
        await _pushPerform(tester, surface, confirmExit: true);
        final route = ModalRoute.of(
          tester.element(find.byKey(ValueKey(surface.exitKey))),
        )!;
        expect(route.popDisposition, RoutePopDisposition.doNotPop);
      });

      testWidgets('still asks on system Back when the setting is on', (
        tester,
      ) async {
        await _pushPerform(tester, surface, confirmExit: true);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(_exitDialog, findsOneWidget);
        expect(_performShowing(), isTrue);
      });

      testWidgets('asks first while the setting has not been read yet, then '
          'follows it', (tester) async {
        final gate = Completer<void>();
        await _pushPerform(
          tester,
          surface,
          confirmExit: false,
          exitReadGate: gate,
        );
        final route = ModalRoute.of(
          tester.element(find.byKey(ValueKey(surface.exitKey))),
        )!;
        expect(route.popDisposition, RoutePopDisposition.doNotPop);

        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();
        expect(_exitDialog, findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('perform-exit-cancel')));
        await tester.pumpAndSettle();
        expect(_performShowing(), isTrue);

        // Once the stored "off" arrives, the close control leaves at once.
        gate.complete();
        await tester.pumpAndSettle();
        expect(route.popDisposition, RoutePopDisposition.pop);
        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();
        expect(_exitDialog, findsNothing);
        expect(_performShowing(), isFalse);
      });

      testWidgets('keeps asking when the setting cannot be read', (
        tester,
      ) async {
        await _pushPerform(
          tester,
          surface,
          confirmExit: false,
          exitReadFails: true,
        );

        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();
        expect(_exitDialog, findsOneWidget);
        expect(_performShowing(), isTrue);
      });

      testWidgets('the exit dialog is drawn in the stage theme over a light '
          'app theme', (tester) async {
        await _pushPerform(tester, surface);
        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();

        final theme = _themeOf(tester, _exitDialog);
        expect(theme.brightness, Brightness.dark);
        expect(
          theme.colorScheme.surface,
          AppTheme.highContrast.colorScheme.surface,
        );
      });

      testWidgets('with stage mode off the exit dialog follows the app theme', (
        tester,
      ) async {
        await _pushPerform(tester, surface, stageMode: false);
        await tester.tap(find.byKey(ValueKey(surface.exitKey)));
        await tester.pumpAndSettle();

        expect(_themeOf(tester, _exitDialog).brightness, Brightness.light);
      });

      testWidgets('the metronome sheet is drawn in the stage theme', (
        tester,
      ) async {
        await _pushPerform(tester, surface);
        await tester.tap(find.byKey(const ValueKey('perform-metronome')));
        await tester.pumpAndSettle();

        expect(
          _themeOf(tester, find.byType(BottomSheet)).brightness,
          Brightness.dark,
        );
      });
    });
  }

  for (final (name, key) in const [
    ('jump', 'perform-jump'),
    ('adjust', 'perform-adjust'),
  ]) {
    testWidgets('the program $name sheet is drawn in the stage theme', (
      tester,
    ) async {
      await _pushPerform(tester, _Surface.program);
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();

      expect(
        _themeOf(tester, find.byType(BottomSheet)).brightness,
        Brightness.dark,
      );
    });
  }

  testWidgets("the adjust sheet's insert picker is drawn in the stage theme", (
    tester,
  ) async {
    await _pushPerform(tester, _Surface.program);
    await tester.tap(find.byKey(const ValueKey('perform-adjust')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust-insert-dance')));
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('adjust-picker'));
    expect(picker, findsOneWidget);
    final theme = _themeOf(tester, picker);
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.colorScheme.surface,
      AppTheme.highContrast.colorScheme.surface,
    );
  });
}
