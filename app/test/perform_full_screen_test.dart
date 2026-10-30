import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_dance_screen.dart';
import 'package:compendium_app/src/screens/perform_full_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
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

/// Records every platform call the full-screen mixin makes, and plays the
/// window's part: [setWindowFullScreen] reports through the watcher the way
/// `window_manager`'s events do, and [osChange] stands in for the OS's own
/// full-screen control.
class _FakeBackend extends PerformFullScreenBackend {
  _FakeBackend(this.support, {this.windowFullScreen = false});

  @override
  final PerformFullScreenSupport support;

  bool windowFullScreen;
  final List<String> calls = <String>[];
  final List<ValueChanged<bool>> _watchers = <ValueChanged<bool>>[];

  int get watcherCount => _watchers.length;

  @override
  Future<void> setImmersive(bool on) async => calls.add('immersive:$on');

  @override
  Future<bool> isWindowFullScreen() async => windowFullScreen;

  @override
  Future<void> setWindowFullScreen(bool on) async {
    calls.add('window:$on');
    osChange(on);
  }

  void osChange(bool on) {
    if (windowFullScreen == on) return;
    windowFullScreen = on;
    for (final watcher in List.of(_watchers)) {
      watcher(on);
    }
  }

  @override
  VoidCallback watchWindowFullScreen(ValueChanged<bool> onChanged) {
    _watchers.add(onChanged);
    return () => _watchers.remove(onChanged);
  }
}

_FakeBackend _install(_FakeBackend backend) {
  final previous = performFullScreenBackend;
  performFullScreenBackend = backend;
  addTearDown(() => performFullScreenBackend = previous);
  return backend;
}

Future<void> _pushPerform(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(1400, 2400),
}) async {
  await tester.binding.setSurfaceSize(size);
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

Future<void> _exitPerform(WidgetTester tester, String exitKey) async {
  await tester.tap(find.byKey(ValueKey(exitKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
  await tester.pumpAndSettle();
}

Future<PerformProgramScreen> _programScreen() async {
  final repos = openTestRepositories();
  await repos.dances.create(_dance());
  final data = await CollectionData.load(repos);
  return PerformProgramScreen(
    program: Program(
      id: 'p1',
      title: 'Spring Dance',
      slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      createdAt: _now,
      updatedAt: _now,
    ),
    data: data,
    renderer: _renderer,
  );
}

bool _toggleSelected(WidgetTester tester) => tester
    .widget<IconButton>(find.byKey(const ValueKey('perform-full-screen')))
    .isSelected!;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installFakeWakelock);

  group('phones go immersive', () {
    testWidgets('program Perform hides the system bars until it exits', (
      tester,
    ) async {
      final backend = _install(
        _FakeBackend(PerformFullScreenSupport.immersive),
      );
      await _pushPerform(tester, await _programScreen());

      expect(backend.calls, ['immersive:true']);
      // Immersive is not a toggle, so there is no button for it.
      expect(find.byKey(const ValueKey('perform-full-screen')), findsNothing);

      await _exitPerform(tester, 'perform-program-exit');
      expect(backend.calls, ['immersive:true', 'immersive:false']);
    });

    testWidgets('single-dance Perform hides the system bars until it exits', (
      tester,
    ) async {
      final backend = _install(
        _FakeBackend(PerformFullScreenSupport.immersive),
      );
      await _pushPerform(
        tester,
        PerformDanceScreen(dance: _dance(), renderer: _renderer),
      );
      expect(backend.calls, ['immersive:true']);

      await _exitPerform(tester, 'exit-perform');
      expect(backend.calls, ['immersive:true', 'immersive:false']);
    });
  });

  group('desktop toggles window full screen', () {
    testWidgets('the toolbar toggle enters full screen, and exit restores', (
      tester,
    ) async {
      final backend = _install(_FakeBackend(PerformFullScreenSupport.window));
      await _pushPerform(tester, await _programScreen());

      // Desktop Perform does not take the window over by itself.
      expect(backend.calls, isEmpty);
      expect(_toggleSelected(tester), isFalse);

      await tester.tap(find.byKey(const ValueKey('perform-full-screen')));
      await tester.pumpAndSettle();
      expect(backend.calls, ['window:true']);
      expect(_toggleSelected(tester), isTrue);

      await _exitPerform(tester, 'perform-program-exit');
      expect(backend.calls, ['window:true', 'window:false']);
      expect(backend.watcherCount, 0);
    });

    testWidgets('F11 toggles, and Escape leaves without leaving Perform', (
      tester,
    ) async {
      final backend = _install(_FakeBackend(PerformFullScreenSupport.window));
      await _pushPerform(
        tester,
        PerformDanceScreen(dance: _dance(), renderer: _renderer),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(backend.windowFullScreen, isTrue);
      expect(_toggleSelected(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(backend.windowFullScreen, isFalse);
      expect(find.byKey(const ValueKey('perform-exit-dialog')), findsNothing);
      expect(find.byType(PerformDanceScreen), findsOneWidget);

      // Escape outside full screen is still Perform's, and does nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(backend.calls, ['window:true', 'window:false']);
      expect(find.byType(PerformDanceScreen), findsOneWidget);
    });

    testWidgets('Escape does not reach an ancestor binding', (tester) async {
      _install(_FakeBackend(PerformFullScreenSupport.window));
      var ancestorEscapes = 0;
      final screen = PerformDanceScreen(dance: _dance(), renderer: _renderer);
      await _pushPerform(
        tester,
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                ancestorEscapes++,
          },
          child: screen,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(ancestorEscapes, 0);
    });

    testWidgets('macOS uses Ctrl-Cmd-F', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final backend = _install(_FakeBackend(PerformFullScreenSupport.window));
      await _pushPerform(tester, await _programScreen());

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(backend.calls, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(backend.calls, ['window:true']);

      await _exitPerform(tester, 'perform-program-exit');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a window already full screen stays full screen after exit', (
      tester,
    ) async {
      final backend = _install(
        _FakeBackend(PerformFullScreenSupport.window, windowFullScreen: true),
      );
      await _pushPerform(tester, await _programScreen());
      expect(_toggleSelected(tester), isTrue);

      await _exitPerform(tester, 'perform-program-exit');
      expect(backend.calls, isEmpty);
      expect(backend.windowFullScreen, isTrue);
    });

    testWidgets('the toggle follows the OS, and exit restores the entry state', (
      tester,
    ) async {
      final backend = _install(_FakeBackend(PerformFullScreenSupport.window));
      await _pushPerform(tester, await _programScreen());

      backend.osChange(true);
      await tester.pumpAndSettle();
      expect(_toggleSelected(tester), isTrue);

      backend.osChange(false);
      await tester.pumpAndSettle();
      expect(_toggleSelected(tester), isFalse);

      // Left as it was found: nothing to undo.
      await _exitPerform(tester, 'perform-program-exit');
      expect(backend.calls, isEmpty);
    });

    testWidgets('narrow windows offer the toggle in the overflow menu', (
      tester,
    ) async {
      final backend = _install(_FakeBackend(PerformFullScreenSupport.window));
      await _pushPerform(
        tester,
        await _programScreen(),
        size: const Size(400, 800),
      );
      expect(find.byKey(const ValueKey('perform-full-screen')), findsNothing);

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('perform-full-screen-menu')));
      await tester.pumpAndSettle();
      expect(backend.calls, ['window:true']);
    });

    testWidgets('a failed platform call does not stop the restore on exit', (
      tester,
    ) async {
      final backend = _FailingEntryBackend();
      _install(backend);
      await _pushPerform(tester, await _programScreen());

      await tester.tap(find.byKey(const ValueKey('perform-full-screen')));
      await tester.pumpAndSettle();
      expect(backend.windowFullScreen, isTrue);

      await _exitPerform(tester, 'perform-program-exit');
      expect(backend.windowFullScreen, isFalse);
    });
  });
}

/// A window whose state cannot be read on entry: the mixin must still take
/// the window out of the full screen it put it in.
class _FailingEntryBackend extends _FakeBackend {
  _FailingEntryBackend() : super(PerformFullScreenSupport.window);

  @override
  Future<bool> isWindowFullScreen() async =>
      throw PlatformException(code: 'unavailable');
}
