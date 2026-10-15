// Post-audit integrity-6: the Perform clocks counted 1 s timer ticks, so any
// interval in which no tick fired (iOS backgrounding, desktop sleep, jank) was
// lost. These tests advance the time source *without* letting timers fire,
// which is what a suspended process looks like, then bring the app back.
import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/data/settings_keys.dart'
    show kAutoSizePerformKey;

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);
final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance(String id) => Dance(
  id: id,
  title: 'Dance $id',
  figures: [
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
  ],
  status: DanceStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

/// A time source that follows the test's fake clock plus [skew]. Raising
/// [skew] moves "now" forward without elapsing fake time, so no timer fires:
/// the gap a suspended or sleeping process sees.
class _SuspendableClock {
  _SuspendableClock(this._base);

  final Clock _base;
  Duration skew = Duration.zero;

  late final Clock clock = Clock(() => _base.now().add(skew));
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _SuspendableClock time,
  Widget screen,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final repos = openTestRepositories();
  await repos.settings.set(kAutoSizePerformKey, false);
  await withClock(
    time.clock,
    () => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<CollectionData> _dataWith(List<Dance> dances) async {
  final repos = openTestRepositories();
  for (final d in dances) {
    await repos.dances.create(d);
  }
  return CollectionData.load(repos);
}

Program _program(List<String> danceIds) => Program(
  id: 'p1',
  title: 'Spring Dance',
  slots: [
    for (var i = 0; i < danceIds.length; i++)
      ProgramSlot(id: 's$i', position: i, danceId: danceIds[i]),
  ],
  createdAt: _now,
  updatedAt: _now,
);

/// Backgrounds the app, lets [gap] pass with no timer firing, and resumes.
Future<void> _suspendFor(
  WidgetTester tester,
  _SuspendableClock time,
  Duration gap,
) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  time.skew += gap;
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

int _seconds(String display) {
  final parts = display.split(':').map(int.parse).toList();
  return parts.length == 3
      ? parts[0] * 3600 + parts[1] * 60 + parts[2]
      : parts[0] * 60 + parts[1];
}

int _clockSeconds(WidgetTester tester) =>
    _seconds(_textOf(tester, 'perform-clock'));

int _slotSeconds(WidgetTester tester) =>
    _seconds(_textOf(tester, 'perform-slot-elapsed'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFakeWakelock);

  group('program Perform', () {
    testWidgets('counts time the app spent suspended', (tester) async {
      final time = _SuspendableClock(clock);
      final data = await _dataWith([_dance('d1')]);
      await _pumpScreen(
        tester,
        time,
        PerformProgramScreen(
          program: _program(['d1']),
          data: data,
          renderer: _renderer,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      final before = _clockSeconds(tester);
      final slotBefore = _slotSeconds(tester);

      await _suspendFor(tester, time, const Duration(minutes: 5));

      expect(
        _clockSeconds(tester),
        before + 300,
        reason: 'the program clock must include the suspended interval',
      );
      expect(
        _slotSeconds(tester),
        slotBefore + 300,
        reason: 'the per-slot elapsed must include it too',
      );

      // And the clock carries on ticking from there.
      await tester.pump(const Duration(seconds: 3));
      expect(_clockSeconds(tester), before + 303);
    });

    testWidgets('per-slot elapsed restarts after a suspend, program clock '
        'does not', (tester) async {
      final time = _SuspendableClock(clock);
      final data = await _dataWith([_dance('d1'), _dance('d2')]);
      await _pumpScreen(
        tester,
        time,
        PerformProgramScreen(
          program: _program(['d1', 'd2']),
          data: data,
          renderer: _renderer,
        ),
      );
      await _suspendFor(tester, time, const Duration(minutes: 5));
      final clockAfterSuspend = _clockSeconds(tester);
      expect(clockAfterSuspend, greaterThanOrEqualTo(300));

      await tester.tap(find.byKey(const ValueKey('perform-next')));
      await tester.pump();
      expect(_textOf(tester, 'perform-slot-elapsed'), '0:00');

      await tester.pump(const Duration(seconds: 4));
      expect(_slotSeconds(tester), 4);
      expect(_clockSeconds(tester), clockAfterSuspend + 4);
    });

    testWidgets('paused timers stay paused across a suspend', (tester) async {
      final time = _SuspendableClock(clock);
      final data = await _dataWith([_dance('d1')]);
      await _pumpScreen(
        tester,
        time,
        PerformProgramScreen(
          program: _program(['d1']),
          data: data,
          renderer: _renderer,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byKey(const ValueKey('perform-timer-pause')));
      await tester.pump();
      final frozenClock = _clockSeconds(tester);
      final frozenSlot = _slotSeconds(tester);

      await _suspendFor(tester, time, const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(_clockSeconds(tester), frozenClock);
      expect(_slotSeconds(tester), frozenSlot);

      await tester.tap(find.byKey(const ValueKey('perform-timer-pause')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(
        _clockSeconds(tester),
        frozenClock + 3,
        reason: 'only time while running is counted',
      );
      expect(_slotSeconds(tester), frozenSlot + 3);
    });
  });

  group('single-dance Perform', () {
    testWidgets('counts time the app spent suspended', (tester) async {
      final time = _SuspendableClock(clock);
      await _pumpScreen(
        tester,
        time,
        PerformDanceScreen(dance: _dance('d1'), renderer: _renderer),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_textOf(tester, 'perform-individual-elapsed'), '0:01');

      await _suspendFor(tester, time, const Duration(minutes: 5));

      expect(_textOf(tester, 'perform-individual-elapsed'), '5:01');
    });

    testWidgets('paused timer stays paused across a suspend', (tester) async {
      final time = _SuspendableClock(clock);
      await _pumpScreen(
        tester,
        time,
        PerformDanceScreen(dance: _dance('d1'), renderer: _renderer),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(
        find.byKey(const ValueKey('perform-individual-timer-pause')),
      );
      await tester.pump();

      await _suspendFor(tester, time, const Duration(minutes: 5));
      expect(_textOf(tester, 'perform-individual-elapsed'), '0:01');

      await tester.tap(
        find.byKey(const ValueKey('perform-individual-timer-pause')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(_textOf(tester, 'perform-individual-elapsed'), '0:03');
    });
  });
}
