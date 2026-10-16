import 'dart:async';

import 'package:compendium_app/src/sync/synced_settings_reload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one request runs the reload, then the fence, once', () async {
    final calls = <String>[];
    final reload = SyncedSettingsReload(
      reload: () async => calls.add('reload'),
      fence: () async => calls.add('fence'),
    );

    await reload.request();

    expect(calls, ['reload', 'fence']);
    expect(reload.running, isFalse);
  });

  test('a settings write landing during the reload runs it again, so a '
      'racing local edit is re-read rather than overwritten', () async {
    var runs = 0;
    late SyncedSettingsReload reload;
    reload = SyncedSettingsReload(
      reload: () async {
        runs++;
        // The user's edit lands between this run's read and its assignment.
        if (runs == 1) reload.noteSettingsWrite();
      },
      fence: () async {},
    );

    await reload.request();

    expect(runs, 2);
  });

  test('a write that completes during the fence also runs it again', () async {
    var runs = 0;
    var fences = 0;
    late SyncedSettingsReload reload;
    reload = SyncedSettingsReload(
      reload: () async => runs++,
      fence: () async {
        fences++;
        if (fences == 1) reload.noteSettingsWrite();
      },
    );

    await reload.request();

    expect(runs, 2);
  });

  test('a write outside a run asks for nothing', () async {
    var runs = 0;
    final reload = SyncedSettingsReload(
      reload: () async => runs++,
      fence: () async {},
    );

    reload.noteSettingsWrite();
    await reload.request();
    reload.noteSettingsWrite();
    await pumpEventQueue();

    expect(runs, 1);
  });

  test('requests during a run coalesce into one more run', () async {
    var runs = 0;
    final gate = Completer<void>();
    final reload = SyncedSettingsReload(
      reload: () async {
        runs++;
        if (runs == 1) await gate.future;
      },
      fence: () async {},
    );

    final first = reload.request();
    await pumpEventQueue();
    await reload.request();
    await reload.request();
    gate.complete();
    await first;

    expect(runs, 2);
  });

  test('re-runs for races stop at maxRacedRuns', () async {
    var runs = 0;
    late SyncedSettingsReload reload;
    reload = SyncedSettingsReload(
      reload: () async {
        runs++;
        reload.noteSettingsWrite();
      },
      fence: () async {},
      maxRacedRuns: 3,
    );

    await reload.request();

    expect(runs, 3);
    expect(reload.running, isFalse);
  });

  test('a request is honoured even once the race bound is spent', () async {
    var runs = 0;
    late SyncedSettingsReload reload;
    reload = SyncedSettingsReload(
      reload: () async {
        runs++;
        reload.noteSettingsWrite();
        // A pass asks for a reload during the last run the bound allows.
        if (runs == 2) unawaited(reload.request());
      },
      fence: () async {},
      maxRacedRuns: 2,
    );

    await reload.request();

    // Run 3, which the request forced, starts the race count again: runs 3
    // and 4 are the two the bound allows.
    expect(runs, 4);
  });

  test('runs a request forced do not spend the race bound', () async {
    var runs = 0;
    late SyncedSettingsReload reload;
    reload = SyncedSettingsReload(
      reload: () async {
        runs++;
        // Two passes apply settings during runs 1 and 2; the user's edit
        // races run 3, the last run the requests forced.
        if (runs <= 2) unawaited(reload.request());
        if (runs == 3) reload.noteSettingsWrite();
      },
      fence: () async {},
      maxRacedRuns: 3,
    );

    await reload.request();

    expect(runs, 4, reason: 'the raced run 3 is read again');
  });

  test('a failing reload still ends the run', () async {
    final reload = SyncedSettingsReload(
      reload: () async => throw StateError('boom'),
      fence: () async {},
    );

    await expectLater(reload.request(), throwsStateError);
    expect(reload.running, isFalse);
  });
}
