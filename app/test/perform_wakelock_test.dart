import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';

import 'support/fake_wakelock.dart';
import 'support/test_repositories.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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
}
