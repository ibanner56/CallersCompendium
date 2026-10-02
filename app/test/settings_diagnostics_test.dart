import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/diagnostics/crash_log_store.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/sync/sync_controller.dart';
import 'package:compendium_app/src/sync/sync_coordinator.dart';
import 'package:compendium_app/src/sync/sync_scope.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/noop_sync_transport.dart';
import 'support/sync_test_network.dart';
import 'support/test_repositories.dart';

// Seeded values that MUST NOT appear in the default (scrubbed) export.
const _seededTerm = 'Chinquapin Reel';
const _seededEmail = 'jane.doe@example.com';
const _seededPhone = '555-123-4567';
const _seededPath = '/Users/jane/CallersCompendium/app/lib/main.dart';

CrashLogRecord _seededRecord() => CrashLogRecord(
  timestampUtc: DateTime.utc(2026, 3, 2, 1),
  appVersion: '0.1.0',
  platform: 'testos 1.0',
  source: 'FlutterError.onError',
  errorType: 'StateError',
  errorMessage:
      'Rendering "$_seededTerm" failed; reach $_seededEmail or $_seededPhone',
  // A real absolute app path plus a package: frame that should survive scrubbing.
  stack:
      '#0 render ($_seededPath:42:7)\n'
      '#1 build (package:compendium_app/main.dart:10:3)',
);

/// An in-memory [CrashLogStore] for widget tests. Widget tests run in a
/// fake-async zone where real `dart:io` file operations never complete, so the
/// on-disk store would deadlock `pumpAndSettle`. This override keeps the public
/// contract (newest-first reads, limit, clear) but resolves via microtasks.
class _InMemoryCrashLogStore extends CrashLogStore {
  _InMemoryCrashLogStore()
    : super(directoryProvider: () async => throw StateError('no I/O in test'));

  final List<CrashLogRecord> _records = [];

  @override
  Future<void> append(CrashLogRecord record) async => _records.add(record);

  @override
  Future<List<CrashLogRecord>> readRecords({
    int? limit,
    bool newestFirst = true,
  }) async {
    var result = newestFirst ? _records.reversed.toList() : List.of(_records);
    if (limit != null && result.length > limit) {
      result = result.sublist(0, limit);
    }
    return result;
  }

  @override
  Future<void> clear() async => _records.clear();
}

/// A store whose reads always fail, to exercise the Diagnostics load-failure
/// state (a null `snapshot.data` must not be treated as "healthy/empty").
class _FailingReadCrashLogStore extends CrashLogStore {
  _FailingReadCrashLogStore()
    : super(directoryProvider: () async => throw StateError('no I/O in test'));

  @override
  Future<void> append(CrashLogRecord record) async {}

  @override
  Future<List<CrashLogRecord>> readRecords({
    int? limit,
    bool newestFirst = true,
  }) async => throw StateError('cannot read log');

  @override
  Future<void> clear() async {}
}

/// Pumps [SettingsScreen] with the diagnostics seams wired to [store] and opens
/// the Diagnostics section. [onExport] captures the text handed to the saver.
Future<void> _pumpDiagnostics(
  WidgetTester tester, {
  required CrashLogStore store,
  required void Function(String contents) onExport,
  Set<String> terms = const {_seededTerm},
  SyncController? sync,
  CompendiumRepositories? repositories,
}) async {
  final repos = repositories ?? openTestRepositories();
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();

  await tester.binding.setSurfaceSize(const Size(1000, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          sync == null ? child! : SyncScope(controller: sync, child: child!),
      home: RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: theme,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(
              notifier: dialect,
              child: SettingsScreen(
                crashLogStore: store,
                sensitiveTermsProvider: () async => terms,
                diagnosticsLogSaver: (contents, name) async {
                  onExport(contents);
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-nav-diagnostics')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemoryCrashLogStore store;

  setUp(() {
    store = _InMemoryCrashLogStore();
  });

  // Most failed passes are results, not crashes, so they leave nothing in the
  // crash log; an export that refused to run without one could never carry
  // the sync section to whoever is helping.
  testWidgets('a sync failure is exported even with an empty crash log, with '
      'its section and nothing identifying', (tester) async {
    final repos = openTestRepositories();
    final coordinator = SyncCoordinator(
      syncId: 'configured',
      deviceId: 'device',
      store: CompendiumSyncCoordinatorStore(repos),
      transport: NoopSyncCoordinatorTransport(),
      passOperation: ({initialStore}) async => const SyncPassResult(
        SyncPassStatus.failed,
        failure: SyncFailure(
          SyncFailureCause.storeFull,
          step: SyncFailureStep.upload,
          statusCode: 507,
        ),
      ),
    );
    addTearDown(coordinator.dispose);
    final sync = SyncController(
      settings: repos.settings,
      syncLocal: repos.syncLocal,
      coordinator: () => coordinator,
      reconfigure: ({bool startPass = true}) async {},
      classifier: const UnmeteredSyncNetwork(),
    );
    addTearDown(sync.dispose);
    await repos.settings.set(kSyncEnabledKey, true);
    await repos.settings.set(kSyncIdKey, 'correct horse battery staple');
    await sync.load();
    await sync.syncNow();

    String? exported;
    await _pumpDiagnostics(
      tester,
      store: store,
      onExport: (contents) => exported = contents,
      sync: sync,
      repositories: repos,
    );
    await tester.tap(find.byKey(const ValueKey('diagnostics-export')));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    expect(exported, contains('Mode: scrubbed'));
    expect(exported, contains('Records: 0'));
    expect(
      exported,
      contains('Last attempt: failed (SYNC-STORE-FULL upload 507)'),
    );
    expect(exported, isNot(contains('horse')));
  });

  testWidgets('lists recorded entries', (tester) async {
    await store.append(_seededRecord());

    await _pumpDiagnostics(tester, store: store, onExport: (_) {});

    expect(find.byKey(const ValueKey('diagnostics-entry-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-empty')), findsNothing);
  });

  testWidgets('default export is scrubbed of PII and user content', (
    tester,
  ) async {
    await store.append(_seededRecord());

    String? exported;
    await _pumpDiagnostics(
      tester,
      store: store,
      onExport: (contents) => exported = contents,
    );

    await tester.tap(find.byKey(const ValueKey('diagnostics-export')));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    final text = exported!;
    expect(text, contains('Mode: scrubbed'));
    // None of the seeded PII / user content leaks into the default export.
    expect(text, isNot(contains(_seededTerm)));
    expect(text, isNot(contains(_seededEmail)));
    expect(text, isNot(contains(_seededPhone)));
    expect(text, isNot(contains('/Users/jane')));
    // The diagnostic skeleton is preserved: error type, collapsed path
    // basename, and app-symbol (package:) stack frames survive.
    expect(text, contains('StateError'));
    expect(text, contains('<path>/main.dart'));
    expect(text, contains('package:compendium_app/main.dart'));
    expect(find.text('Diagnostics log exported.'), findsOneWidget);
  });

  testWidgets('default export withholds a message whose value is in no term', (
    tester,
  ) async {
    // The value was never persisted (or was purged), so the provider's term
    // set does not contain it: only withholding the message protects it.
    const unsavedValue = 'Nonpersisted Jig';
    await store.append(
      CrashLogRecord(
        timestampUtc: DateTime.utc(2026, 3, 2, 1),
        appVersion: '0.1.0',
        platform: 'testos 1.0',
        source: 'dance_editor._save',
        errorType: 'StateError',
        errorMessage: 'Saving "$unsavedValue" failed',
        stack: '#0 save (package:compendium_app/main.dart:10:3)',
      ),
    );

    String? exported;
    await _pumpDiagnostics(
      tester,
      store: store,
      onExport: (contents) => exported = contents,
    );

    await tester.tap(find.byKey(const ValueKey('diagnostics-export')));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    final text = exported!;
    expect(text, contains('Mode: scrubbed'));
    expect(text, isNot(contains(unsavedValue)));
    expect(text, contains('StateError'));
    expect(text, contains('dance_editor._save'));
  });

  testWidgets('full-detail toggle exports the unredacted log', (tester) async {
    await store.append(_seededRecord());

    String? exported;
    await _pumpDiagnostics(
      tester,
      store: store,
      onExport: (contents) => exported = contents,
    );

    await tester.tap(
      find.byKey(const ValueKey('diagnostics-full-detail-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics-export')));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    final text = exported!;
    expect(text, contains('Mode: FULL DETAIL'));
    expect(text, contains(_seededTerm));
    expect(text, contains(_seededEmail));
    expect(text, contains(_seededPhone));
    expect(text, contains(_seededPath));
  });

  testWidgets('clear empties the log after confirmation', (tester) async {
    await store.append(_seededRecord());

    await _pumpDiagnostics(tester, store: store, onExport: (_) {});
    expect(find.byKey(const ValueKey('diagnostics-entry-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostics-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics-clear-confirm')));
    await tester.pumpAndSettle();

    expect(await store.readRecords(), isEmpty);
    expect(find.byKey(const ValueKey('diagnostics-empty')), findsOneWidget);
  });

  testWidgets('shows a load-failure state when the log cannot be read', (
    tester,
  ) async {
    await _pumpDiagnostics(
      tester,
      store: _FailingReadCrashLogStore(),
      onExport: (_) {},
    );

    // A read failure must surface, not masquerade as the healthy empty state.
    expect(find.byKey(const ValueKey('diagnostics-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-empty')), findsNothing);
  });
}
