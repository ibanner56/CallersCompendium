import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart'
    show wakelockPlusPlatformInstance;

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';

import 'support/fake_wakelock.dart';
import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);
final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance({String id = 'd1', String title = 'Test Dance'}) => Dance(
  id: id,
  title: title,
  figures: [
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
  ],
  status: DanceStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps [screen] behind a launcher button that pushes it onto a real
/// [Navigator], so the Perform screen's close button can pop it just like in
/// the app. Returns after the push settles.
Future<void> _pushPerform(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final repos = openTestRepositories();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('launch-perform'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('Perform'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('launch-perform')));
  await tester.pumpAndSettle();
}

/// Simulates the app going to the background and returning to the foreground,
/// stepping through the valid [AppLifecycleState] transitions so the
/// `WidgetsBindingObserver` fires `didChangeAppLifecycleState` for each — ending
/// on [AppLifecycleState.resumed].
Future<void> _backgroundThenResume(WidgetTester tester) async {
  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];
  for (final state in [...toBackground, ...toForeground]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWakelockPlus wakelock;
  setUp(() => wakelock = installFakeWakelock());

  testWidgets(
    'single-dance Perform enables the wake-lock and releases it on exit',
    (tester) async {
      await _pushPerform(
        tester,
        PerformDanceScreen(dance: _dance(), renderer: _renderer),
      );

      expect(find.byType(PerformDanceScreen), findsOneWidget);
      expect(wakelock.isEnabled, isTrue);

      await tester.tap(find.byKey(const ValueKey('exit-perform')));
      await tester.pumpAndSettle();
      // Exit is guarded (#612, sibling of #434): confirm to actually leave.
      await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(PerformDanceScreen), findsNothing);
      expect(wakelock.isEnabled, isFalse);
    },
  );

  testWidgets('program Perform enables the wake-lock and releases it on exit', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Program Dance'));
    final data = await CollectionData.load(repos);
    final program = Program(
      id: 'p1',
      title: 'Spring Dance',
      slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      createdAt: _now,
      updatedAt: _now,
    );

    await _pushPerform(
      tester,
      PerformProgramScreen(program: program, data: data, renderer: _renderer),
    );

    expect(find.byType(PerformProgramScreen), findsOneWidget);
    expect(wakelock.isEnabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    // Exit is guarded (#434): confirm to actually leave.
    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformProgramScreen), findsNothing);
    expect(wakelock.isEnabled, isFalse);
  });

  testWidgets(
    'single-dance Perform re-asserts the wake-lock after backgrounding',
    (tester) async {
      await _pushPerform(
        tester,
        PerformDanceScreen(dance: _dance(), renderer: _renderer),
      );
      expect(wakelock.isEnabled, isTrue);

      // The OS releases the wake-lock while the app is backgrounded.
      wakelock.isEnabled = false;
      wakelock.toggles.clear();

      await _backgroundThenResume(tester);

      expect(
        wakelock.isEnabled,
        isTrue,
        reason: 'resuming the app must re-assert the wake-lock',
      );
      expect(
        wakelock.toggles,
        contains(true),
        reason: 'resume should issue a fresh enable toggle',
      );
    },
  );

  testWidgets('program Perform re-asserts the wake-lock after backgrounding', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Program Dance'));
    final data = await CollectionData.load(repos);
    final program = Program(
      id: 'p1',
      title: 'Spring Dance',
      slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      createdAt: _now,
      updatedAt: _now,
    );

    await _pushPerform(
      tester,
      PerformProgramScreen(program: program, data: data, renderer: _renderer),
    );
    expect(wakelock.isEnabled, isTrue);

    wakelock.isEnabled = false;
    wakelock.toggles.clear();

    await _backgroundThenResume(tester);

    expect(
      wakelock.isEnabled,
      isTrue,
      reason: 'resuming the app must re-assert the wake-lock',
    );
    expect(wakelock.toggles, contains(true));
  });

  Program programFor(String danceId) => Program(
    id: 'p1',
    title: 'Spring Dance',
    slots: [ProgramSlot(id: 's1', position: 0, danceId: danceId)],
    createdAt: _now,
    updatedAt: _now,
  );

  Future<void> exitProgramPerform(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'program Perform leaves zero inhibits outstanding after N resume cycles '
    'and exit',
    (tester) async {
      final counting = installCountingWakelock();
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Program Dance'));
      final data = await CollectionData.load(repos);

      await _pushPerform(
        tester,
        PerformProgramScreen(
          program: programFor('d1'),
          data: data,
          renderer: _renderer,
        ),
      );
      expect(counting.outstanding, 1);

      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      expect(
        counting.outstanding,
        1,
        reason: 'a resume while the lock is held must not stack another',
      );
      expect(counting.toggles, [true], reason: 'no second enable while held');

      await exitProgramPerform(tester);

      expect(counting.outstanding, 0);
    },
  );

  testWidgets(
    'program Perform releases the inhibit after repeated background/resume '
    'cycles',
    (tester) async {
      final counting = installCountingWakelock();
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Program Dance'));
      final data = await CollectionData.load(repos);

      await _pushPerform(
        tester,
        PerformProgramScreen(
          program: programFor('d1'),
          data: data,
          renderer: _renderer,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await _backgroundThenResume(tester);
      }
      expect(counting.outstanding, 1);

      await exitProgramPerform(tester);

      expect(counting.outstanding, 0);
    },
  );

  testWidgets(
    'an enable still in flight when Perform is disposed is released',
    (tester) async {
      final counting = installCountingWakelock();
      final gate = Completer<void>();
      counting.enableGate = gate;
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Program Dance'));
      final data = await CollectionData.load(repos);

      await _pushPerform(
        tester,
        PerformProgramScreen(
          program: programFor('d1'),
          data: data,
          renderer: _renderer,
        ),
      );
      expect(counting.outstanding, 0, reason: 'enable is still in flight');

      await exitProgramPerform(tester);
      expect(find.byType(PerformProgramScreen), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(counting.outstanding, 0);
    },
  );

  testWidgets(
    'a Dart Error from the first enable does not stop the disable on exit',
    (tester) async {
      // flows-4: the wake-lock chain was `_wakelockOp.then(...)`, and only
      // `Exception`s were caught. A plugin `Error` left `_wakelockOp` failed,
      // so every later operation — including the disable on exit — was
      // skipped and the lock stayed held after leaving Perform.
      final throwing = _ThrowingFirstEnableWakelock();
      final previous = wakelockPlusPlatformInstance;
      wakelockPlusPlatformInstance = throwing;
      addTearDown(() => wakelockPlusPlatformInstance = previous);

      await _pushPerform(
        tester,
        PerformDanceScreen(dance: _dance(), renderer: _renderer),
      );
      expect(throwing.toggles, [true]);
      // The Error is still surfaced, through `FlutterError.reportError` (the
      // crash log in the app; `takeException` here), rather than swallowed.
      expect(tester.takeException(), isA<StateError>());

      await tester.tap(find.byKey(const ValueKey('exit-perform')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(PerformDanceScreen), findsNothing);
      expect(throwing.toggles, [
        true,
        false,
      ], reason: 'leaving Perform must still issue the disable');
      expect(
        tester.takeException(),
        isNull,
        reason: 'the Error is reported once, not once per later operation',
      );
    },
  );
}

/// Throws a [StateError] (a Dart `Error`, not an `Exception`) from its first
/// `toggle(enable: true)`, then behaves.
class _ThrowingFirstEnableWakelock extends FakeWakelockPlus {
  bool _thrown = false;

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
    if (enable && !_thrown) {
      _thrown = true;
      throw StateError('wake-lock plugin bug');
    }
    isEnabled = enable;
  }
}
