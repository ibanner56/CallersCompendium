// Guards the toolbar "Sync now" glyph on Collection and Programs (#1421): a
// second entry to the manual trigger Settings already has.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/app_shell_search_scope.dart';
import 'package:compendium_app/src/screens/collection_shell.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_network.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';

import '../support/l10n_harness.dart';
import '../support/noop_sync_transport.dart';
import '../support/test_repositories.dart';

final class _Network implements SyncNetworkClassifier {
  SyncNetworkKind kind = SyncNetworkKind.unmetered;

  /// When non-null, [current] waits on it. The controller consults the
  /// classifier *before* it marks a pass in flight, so holding it open keeps a
  /// test inside the window in which the controller's own `running` is still
  /// false.
  Completer<void>? hold;

  @override
  Future<SyncNetworkKind> current() async {
    await hold?.future;
    return kind;
  }
}

const _glyph = ValueKey('sync-now-action');

/// What a screen under test is hosted in: the controller, the network the
/// controller consults, and the passes the coordinator has been asked to run.
class _Host {
  _Host(this.controller, this.network, this.passes, this.gate);

  final SyncController controller;
  final _Network network;

  /// One entry per pass the coordinator actually ran.
  final List<int> passes;

  /// When non-null, a pass waits on it, so a test can hold one in flight.
  Completer<void>? gate;
}

/// Pumps [home] with a real [SyncController] whose settings are seeded as
/// requested. [paired] seeds a sync phrase; [enabled] switches sync on;
/// [scoped] false omits the [SyncScope] entirely.
Future<_Host> _pump(
  WidgetTester tester,
  Widget home, {
  bool enabled = true,
  bool paired = true,
  bool scoped = true,
  bool hasCoordinator = true,
  bool compact = false,
  Size size = const Size(600, 1200),
}) async {
  final repos = openTestRepositories();
  if (paired) {
    await repos.settings.set('sync_id', 'alpha-bravo-charlie-delta');
  }
  final network = _Network();
  final passes = <int>[];
  late final _Host host;
  final coordinator = SyncCoordinator(
    syncId: 'configured',
    deviceId: 'device',
    store: CompendiumSyncCoordinatorStore(repos),
    transport: NoopSyncCoordinatorTransport(),
    passOperation: ({initialStore}) async {
      passes.add(1);
      final gate = host.gate;
      if (gate != null) await gate.future;
      return const SyncPassResult(SyncPassStatus.completed);
    },
  );
  addTearDown(coordinator.dispose);
  final controller = SyncController(
    settings: repos.settings,
    syncLocal: repos.syncLocal,
    coordinator: () => hasCoordinator ? coordinator : null,
    reconfigure: ({bool startPass = true}) async {},
    classifier: network,
  );
  addTearDown(controller.dispose);
  await controller.load();
  if (enabled) await controller.setEnabled(true);
  host = _Host(controller, network, passes, null);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) {
        Widget wrapped = RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: dialect, child: child!),
        );
        if (scoped) {
          wrapped = SyncScope(controller: controller, child: wrapped);
        }
        if (compact) {
          wrapped = AppShellSearchScope(
            openSearch: () async {},
            child: wrapped,
          );
        }
        return wrapped;
      },
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // The same behaviour is required of both pages, so each case runs against
  // both rather than being asserted once for whichever page came first.
  final pages = <String, Widget Function()>{
    'Collection': () => const DanceListScreen(),
    'Programs': () => const ProgramsListScreen(),
  };

  for (final MapEntry(key: name, value: build) in pages.entries) {
    group('$name toolbar', () {
      testWidgets('shows a glyph tooltipped "Sync now" when sync is on and '
          'paired', (tester) async {
        await _pump(tester, build());

        expect(find.byKey(_glyph), findsOneWidget);
        expect(find.byTooltip('Sync now'), findsOneWidget);
      });

      testWidgets('is hidden while Device Sync is off', (tester) async {
        await _pump(tester, build(), enabled: false);

        expect(find.byKey(_glyph), findsNothing);
      });

      testWidgets('is hidden when sync is on but no store is paired', (
        tester,
      ) async {
        await _pump(tester, build(), paired: false);

        expect(find.byKey(_glyph), findsNothing);
      });

      testWidgets('is hidden when the tree has no SyncScope', (tester) async {
        await _pump(tester, build(), scoped: false);

        expect(find.byKey(_glyph), findsNothing);
      });

      testWidgets('appears and disappears as sync is switched on and off', (
        tester,
      ) async {
        final host = await _pump(tester, build(), enabled: false);
        expect(find.byKey(_glyph), findsNothing);

        await host.controller.setEnabled(true);
        await tester.pumpAndSettle();
        expect(find.byKey(_glyph), findsOneWidget);

        await host.controller.setEnabled(false);
        await tester.pumpAndSettle();
        expect(find.byKey(_glyph), findsNothing);
      });

      testWidgets('a tap runs exactly one pass', (tester) async {
        final host = await _pump(tester, build());

        await tester.tap(find.byKey(_glyph));
        await tester.pumpAndSettle();

        expect(host.passes, hasLength(1));
        expect(find.byType(SnackBar), findsNothing, reason: 'a pass ran');
      });

      testWidgets('shows a spinner and ignores taps while a pass is running', (
        tester,
      ) async {
        final host = await _pump(tester, build());
        host.gate = Completer<void>();

        await tester.tap(find.byKey(_glyph));
        await tester.pump();

        expect(host.controller.running, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<IconButton>(find.byKey(_glyph));
        expect(button.onPressed, isNull);

        await tester.tap(find.byKey(_glyph), warnIfMissed: false);
        await tester.pump();
        expect(host.passes, hasLength(1));

        host.gate!.complete();
        await tester.pumpAndSettle();

        expect(host.controller.running, isFalse);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          tester.widget<IconButton>(find.byKey(_glyph)).onPressed,
          isNotNull,
        );
        expect(host.passes, hasLength(1));
      });

      testWidgets('on a metered connection it explains, without pointing '
          '"below", and runs nothing', (tester) async {
        final host = await _pump(tester, build());
        host.network.kind = SyncNetworkKind.metered;

        await tester.tap(find.byKey(_glyph));
        await tester.pumpAndSettle();

        expect(host.passes, isEmpty);
        expect(
          find.text(
            'You are on a mobile-data connection and Sync only on WiFi is '
            'on. Turn that setting off in Settings to sync now.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('below'), findsNothing);
        // Only a *manual* attempt asks the setting to be surfaced, so this
        // fails if the glyph ever calls an automatic trigger instead.
        expect(host.controller.wifiSettingRequests.value, 1);
      });

      testWidgets('offline it says so and runs nothing', (tester) async {
        final host = await _pump(tester, build());
        host.network.kind = SyncNetworkKind.offline;

        await tester.tap(find.byKey(_glyph));
        await tester.pumpAndSettle();

        expect(host.passes, isEmpty);
        expect(
          find.text(
            'No connection right now. Sync will run at the next opportunity.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('with no coordinator it asks to connect a store', (
        tester,
      ) async {
        await _pump(tester, build(), hasCoordinator: false);

        await tester.tap(find.byKey(_glyph));
        await tester.pumpAndSettle();

        expect(find.text('Connect a store before syncing.'), findsOneWidget);
      });

      testWidgets('a second tap during the connectivity check does not queue '
          'a second pass', (tester) async {
        final host = await _pump(tester, build());
        host.network.hold = Completer<void>();

        await tester.tap(find.byKey(_glyph));
        await tester.pump();
        // The controller has not yet marked a pass in flight, so only the
        // widget's own guard can stop this one.
        expect(host.controller.running, isFalse);
        await tester.tap(find.byKey(_glyph), warnIfMissed: false);
        await tester.pump();

        host.network.hold!.complete();
        await tester.pumpAndSettle();

        expect(host.passes, hasLength(1));
      });

      testWidgets('is usable again once a gated attempt has been explained', (
        tester,
      ) async {
        final host = await _pump(tester, build());
        host.network.kind = SyncNetworkKind.offline;
        await tester.tap(find.byKey(_glyph));
        await tester.pumpAndSettle();
        expect(host.passes, isEmpty);

        host.network.kind = SyncNetworkKind.unmetered;
        await tester.tap(find.byKey(_glyph));
        await tester.pumpAndSettle();

        expect(host.passes, hasLength(1));
      });

      for (final (label, kind, text) in [
        (
          'offline',
          SyncNetworkKind.offline,
          'No connection right now. Sync will run at the next opportunity.',
        ),
        (
          'metered',
          SyncNetworkKind.metered,
          'You are on a mobile-data connection and Sync only on WiFi is on. '
              'Turn that setting off in Settings to sync now.',
        ),
      ]) {
        testWidgets('a $label outcome arriving after the app tree is gone '
            'does not throw', (tester) async {
          final host = await _pump(tester, build());
          host.network.kind = kind;
          host.network.hold = Completer<void>();
          await tester.tap(find.byKey(_glyph));
          await tester.pump();

          // Tearing the whole tree down disposes the ScaffoldMessenger the tap
          // captured; the outcome then arrives wanting a snackbar.
          await tester.pumpWidget(const SizedBox());
          host.network.hold!.complete();
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text(text), findsNothing);
        });
      }

      testWidgets('leaving the page mid-pass does not throw', (tester) async {
        final host = await _pump(tester, build());
        host.gate = Completer<void>();
        await tester.tap(find.byKey(_glyph));
        await tester.pump();

        await tester.pumpWidget(const SizedBox());
        host.gate!.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('sits beside search on a narrow layout without overflow', (
        tester,
      ) async {
        await _pump(tester, build(), compact: true, size: const Size(360, 800));

        expect(find.byKey(_glyph), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('wide layout', () {
    // The list pane is a fixed 400 px and the Collection bar already carries
    // about six icon buttons when no tags exist, so one more is the case most
    // likely to squeeze the title or overflow.
    testWidgets('Collection list pane holds the glyph without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        const CollectionShell(),
        size: const Size(CollectionShell.splitBreakpoint, 900),
      );

      expect(find.byKey(_glyph), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Programs list pane holds the glyph without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        const ProgramsShell(),
        size: const Size(ProgramsShell.splitBreakpoint, 900),
      );

      expect(find.byKey(_glyph), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
