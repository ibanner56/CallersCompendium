import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/perform_walkthrough_overlay.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/settings_screen.dart'
    show
        kAutoSizePerformKey,
        kPerformCanonicalViewKey,
        kPerformStageModeKey,
        kPerformTextScaleKey;
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/theme/color_schemes.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);
final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance({
  required String id,
  required String title,
  String walkthrough = '',
}) => Dance(
  id: id,
  title: title,
  figures: [
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
  ],
  status: DanceStatus.active,
  walkthrough: walkthrough,
  createdAt: _now,
  updatedAt: _now,
);

ProgramSlot _slot({
  required String id,
  required int position,
  String? danceId,
  String? text,
  bool isAlt = false,
  int? plannedMinutes,
}) => ProgramSlot(
  id: id,
  position: position,
  danceId: danceId,
  text: text,
  isAlt: isAlt,
  plannedMinutes: plannedMinutes,
);

Program _program(List<ProgramSlot> slots, {String title = 'Spring Dance'}) =>
    Program(
      id: 'p1',
      title: title,
      slots: slots,
      createdAt: _now,
      updatedAt: _now,
    );

/// Loads a [CollectionData] backed by the given dances so slots resolve to
/// real [Dance]s the way the program editor does.
Future<CollectionData> _dataWith(List<Dance> dances) async {
  final repos = openTestRepositories();
  for (final d in dances) {
    await repos.dances.create(d);
  }
  return CollectionData.load(repos);
}

Future<void> _pumpProgram(
  WidgetTester tester, {
  required Program program,
  required CollectionData data,
  int initialGroup = 0,
  Dialect? activeDialect,
  bool autoSize = false,
  Size surfaceSize = const Size(1400, 2400),
  DialectLibraryController? dialectLibrary,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final repos = openTestRepositories();
  await repos.settings.set(kAutoSizePerformKey, autoSize);
  Widget withLibrary(Widget child) => dialectLibrary == null
      ? child
      : DialectLibraryScope(controller: dialectLibrary, child: child);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: withLibrary(
          ActiveDialectScope(notifier: notifier, child: child!),
        ),
      ),
      home: PerformProgramScreen(
        program: program,
        data: data,
        renderer: _renderer,
        initialGroup: initialGroup,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Reads the current text of a keyed [Text] widget (e.g. the running clock or
/// per-slot elapsed readout), which live inside an [ExcludeSemantics] wrapper
/// but are still present in the widget tree.
String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// Parses a `MM:SS` / `H:MM:SS` readout back into whole seconds.
int _seconds(String display) {
  final parts = display.split(':').map(int.parse).toList();
  return parts.length == 3
      ? parts[0] * 3600 + parts[1] * 60 + parts[2]
      : parts[0] * 60 + parts[1];
}

/// Mirrors the screen's `H:MM:SS` / `MM:SS` formatting for assertions.
String _fmt(int totalSeconds) {
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(installFakeWakelock);

  testWidgets('next/prev moves between groups', (tester) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'First Dance'),
      _dance(id: 'd2', title: 'Second Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
      ]),
    );

    expect(find.text('First Dance'), findsOneWidget);
    expect(find.text('Slot 1 of 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-next')));
    await tester.pumpAndSettle();
    expect(find.text('Second Dance'), findsOneWidget);
    expect(find.text('Slot 2 of 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-prev')));
    await tester.pumpAndSettle();
    expect(find.text('First Dance'), findsOneWidget);
  });

  group('AppBar responsive overflow (issue #433)', () {
    // The full Perform toolbar is ~10 controls; on phones narrower than ~430px
    // it used to RenderFlex-overflow, clipping the stage-mode toggle. Secondary
    // actions now collapse into a "More actions" overflow while the stage toggle
    // (and the per-gig dialect quick-switch) stay inline. These tests mount the
    // FULL action set — DialectLibraryScope so the quick-switch renders, a group
    // with alternates so alt-swap shows, and a non-canonical dialect so the
    // canonical toggle shows — so the no-overflow assertions are meaningful.

    Future<DialectLibraryController> loadedLibrary() async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();
      final controller = DialectLibraryController(repos.settings);
      await controller.load();
      addTearDown(controller.dispose);
      return controller;
    }

    Future<void> pumpFullSet(WidgetTester tester, Size size) async {
      final data = await _dataWith([
        _dance(id: 'd1', title: 'Primary Dance'),
        _dance(id: 'd2', title: 'Alternate Dance'),
      ]);
      await _pumpProgram(
        tester,
        data: data,
        // Primary + alt collapse into one navigable group, so `hasAlternates`
        // is true and the swap control is part of the action set.
        program: _program([
          // s1 (the current slot) carries a non-null planned length so the
          // timing readout renders its LONGER "planned N min" form — the widest
          // content the FittedBox scale-down is there to protect at 360–430px.
          // Without it the readout is short and the scale-down path (and thus
          // this regression guard) would never be exercised (issue #433).
          _slot(id: 's1', position: 0, danceId: 'd1', plannedMinutes: 45),
          _slot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
        ]),
        surfaceSize: size,
        dialectLibrary: await loadedLibrary(),
      );
    }

    const inlineSecondaryKeys = [
      'perform-adjust',
      'perform-jump',
      'perform-metronome',
      'perform-alt-swap',
      'decrease-text-size',
      'increase-text-size',
      'perform-autosize-toggle',
      'perform-dialect-toggle',
    ];
    const overflowItemKeys = [
      'perform-adjust-menu',
      'perform-jump-menu',
      'perform-metronome-menu',
      'perform-alt-swap-menu',
      'decrease-text-size-menu',
      'increase-text-size-menu',
      'perform-autosize-toggle-menu',
      'perform-dialect-toggle-menu',
    ];

    for (final width in const [360.0, 430.0]) {
      testWidgets(
        'collapses secondary actions with no overflow at ${width.toInt()}px',
        (tester) async {
          await pumpFullSet(tester, Size(width, 900));

          // No RenderFlex overflow (or any other exception) during layout.
          expect(tester.takeException(), isNull);

          // The current slot renders the longer "planned N min" readout that the
          // FittedBox scale-down protects; assert it's actually present so this
          // setup can't silently regress to the short readout and let a future
          // overflow slip through unnoticed.
          expect(find.byKey(const ValueKey('perform-planned')), findsOneWidget);

          // Primary actions stay inline and reachable.
          expect(
            find.byKey(const ValueKey('perform-stage-toggle')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('dialect-quick-switch')),
            findsOneWidget,
          );
          // The overflow control is present...
          expect(
            find.byKey(const ValueKey('perform-overflow-menu')),
            findsOneWidget,
          );
          // ...and secondary actions are NOT inline (they moved to overflow).
          for (final key in inlineSecondaryKeys) {
            expect(
              find.byKey(ValueKey(key)),
              findsNothing,
              reason: '$key should be collapsed into the overflow menu',
            );
          }

          // Opening the overflow menu makes every secondary action reachable.
          await tester.tap(find.byKey(const ValueKey('perform-overflow-menu')));
          await tester.pumpAndSettle();
          for (final key in overflowItemKeys) {
            expect(
              find.byKey(ValueKey(key)),
              findsOneWidget,
              reason: '$key should be reachable via the overflow menu',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('a secondary action in the overflow menu stays functional', (
      tester,
    ) async {
      await pumpFullSet(tester, const Size(360, 900));

      await tester.tap(find.byKey(const ValueKey('perform-overflow-menu')));
      await tester.pumpAndSettle();
      // "Jump to slot" opens the jump sheet just as the inline button did.
      await tester.tap(find.byKey(const ValueKey('perform-jump-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perform-jump-list')), findsOneWidget);
    });

    testWidgets('stage-mode toggle stays inline and works on a narrow phone', (
      tester,
    ) async {
      await pumpFullSet(tester, const Size(360, 900));

      // Stage mode defaults on (high-contrast scheme).
      expect(
        Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
        AppColorSchemes.highContrast,
      );
      // The inline toggle (not the overflow menu) flips it — no menu needed.
      await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
        isNot(AppColorSchemes.highContrast),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the full action set inline on a wide tablet', (
      tester,
    ) async {
      await pumpFullSet(tester, const Size(1024, 1366));

      expect(tester.takeException(), isNull);
      // No overflow control on wide layouts.
      expect(find.byKey(const ValueKey('perform-overflow-menu')), findsNothing);
      // Every action renders inline.
      expect(
        find.byKey(const ValueKey('dialect-quick-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('perform-stage-toggle')),
        findsOneWidget,
      );
      for (final key in inlineSecondaryKeys) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });
  });

  testWidgets('keyboard arrows navigate between groups', (tester) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'First Dance'),
      _dance(id: 'd2', title: 'Second Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
      ]),
    );

    expect(find.text('First Dance'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Second Dance'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('First Dance'), findsOneWidget);

    // Page keys work too.
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(find.text('Second Dance'), findsOneWidget);
  });

  testWidgets('jump-to-slot jumps to a chosen slot', (tester) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'First Dance'),
      _dance(id: 'd2', title: 'Second Dance'),
      _dance(id: 'd3', title: 'Third Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
        _slot(id: 's3', position: 2, danceId: 'd3'),
      ]),
    );

    await tester.tap(find.byKey(const ValueKey('perform-jump')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-jump-slot-2')));
    await tester.pumpAndSettle();

    expect(find.text('Third Dance'), findsOneWidget);
    expect(find.text('Slot 3 of 3'), findsOneWidget);
  });

  testWidgets('ALT swap changes the shown dance within a group', (
    tester,
  ) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'Primary Dance'),
      _dance(id: 'd2', title: 'Alternate Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
      ]),
    );

    // Primary + its alt collapse into a single navigable group.
    expect(find.text('Slot 1 of 1'), findsOneWidget);
    expect(find.text('Primary Dance'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-alt-swap')));
    await tester.pumpAndSettle();

    expect(find.text('Alternate Dance'), findsOneWidget);
    // Still one navigable position — swapping does not advance.
    expect(find.text('Slot 1 of 1'), findsOneWidget);
  });

  testWidgets('free-text-only slot renders as a text card (no figures)', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'A Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, text: 'Waltz break')]),
    );

    expect(find.byKey(const ValueKey('perform-text')), findsOneWidget);
    expect(find.text('Waltz break'), findsOneWidget);
    // No dance header/figures on a text-only slot.
    expect(find.byKey(const ValueKey('perform-title')), findsNothing);
    expect(find.byType(PerformCard), findsNothing);
    // No alternates here, so the swap control is hidden.
    expect(find.byKey(const ValueKey('perform-alt-swap')), findsNothing);
  });

  testWidgets('entry from program editor opens the program Perform view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Editor Dance'));
    await repos.programs.create(
      _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const ProgramEditorScreen(programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformProgramScreen), findsOneWidget);
    expect(find.text('Editor Dance'), findsOneWidget);
  });

  testWidgets('exit control returns to the editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Editor Dance'));
    await repos.programs.create(
      _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const ProgramEditorScreen(programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsOneWidget);

    // Exit is guarded (#434): the close control asks to confirm first.
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('perform-exit-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformProgramScreen), findsNothing);
    expect(find.byType(ProgramEditorScreen), findsOneWidget);
  });

  testWidgets('a stray single tap on the exit control does not leave Perform', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Editor Dance'));
    await repos.dances.create(_dance(id: 'd2', title: 'Second Dance'));
    await repos.programs.create(
      _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
      ]),
    );
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const ProgramEditorScreen(programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsOneWidget);

    // A single tap surfaces the confirmation instead of dropping out.
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('perform-exit-dialog')), findsOneWidget);
    expect(find.byType(PerformProgramScreen), findsOneWidget);

    // Choosing "Keep performing" dismisses the guard and stays in Perform.
    await tester.tap(find.byKey(const ValueKey('perform-exit-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('perform-exit-dialog')), findsNothing);
    expect(find.byType(PerformProgramScreen), findsOneWidget);
  });

  testWidgets('re-entry resumes at the last slot with the clock preserved', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'First Dance'));
    await repos.dances.create(_dance(id: 'd2', title: 'Second Dance'));
    await repos.dances.create(_dance(id: 'd3', title: 'Third Dance'));
    await repos.programs.create(
      _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
        _slot(id: 's3', position: 2, danceId: 'd3'),
      ]),
    );
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const ProgramEditorScreen(programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsOneWidget);

    // Advance to slot 2 and let the program clock run.
    await tester.tap(find.byKey(const ValueKey('perform-next')));
    await tester.pump();
    expect(_textOf(tester, 'perform-position'), 'Slot 2 of 3');
    await tester.pump(const Duration(seconds: 7));
    final clockBefore = _seconds(_textOf(tester, 'perform-clock'));
    expect(clockBefore, greaterThanOrEqualTo(7));

    // Guarded exit back to the editor.
    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsNothing);

    // Re-enter: back at slot 2 with the clock preserved, not reset to slot 1.
    await tester.tap(find.byKey(const ValueKey('perform-program')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsOneWidget);
    expect(_textOf(tester, 'perform-position'), 'Slot 2 of 3');
    expect(
      _seconds(_textOf(tester, 'perform-clock')),
      greaterThanOrEqualTo(clockBefore),
    );
  });

  testWidgets(
    're-entry preserves the per-slot timer and a paused (frozen) session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'First Dance'));
      await repos.dances.create(_dance(id: 'd2', title: 'Second Dance'));
      await repos.programs.create(
        _program([
          _slot(id: 's1', position: 0, danceId: 'd1'),
          _slot(id: 's2', position: 1, danceId: 'd2'),
        ]),
      );
      final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
          home: const ProgramEditorScreen(programId: 'p1'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('perform-program')));
      await tester.pumpAndSettle();

      // Move to slot 2 so the resumed group is not the default slot 1, accrue
      // per-slot time, then pause so the whole session is frozen on exit.
      await tester.tap(find.byKey(const ValueKey('perform-next')));
      await tester.pump();
      expect(_textOf(tester, 'perform-position'), 'Slot 2 of 2');
      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.byKey(const ValueKey('perform-timer-pause')));
      await tester.pump();

      final slotBefore = _textOf(tester, 'perform-slot-elapsed');
      final clockBefore = _textOf(tester, 'perform-clock');
      expect(_seconds(slotBefore), greaterThanOrEqualTo(6));
      // Paused reflected in the toggle state before we leave.
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('perform-timer-pause')),
            )
            .isSelected,
        isTrue,
      );

      // Guarded exit and re-entry.
      await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('perform-exit-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(PerformProgramScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('perform-program')));
      await tester.pumpAndSettle();
      expect(find.byType(PerformProgramScreen), findsOneWidget);

      // The per-slot timer resumes where it was (slotStartSeconds preserved),
      // not reset to 0:00, and the session is still paused.
      expect(_textOf(tester, 'perform-position'), 'Slot 2 of 2');
      expect(_textOf(tester, 'perform-slot-elapsed'), slotBefore);
      expect(_textOf(tester, 'perform-clock'), clockBefore);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('perform-timer-pause')),
            )
            .isSelected,
        isTrue,
      );

      // Still frozen after re-entry: advancing time changes nothing.
      await tester.pump(const Duration(seconds: 5));
      expect(_textOf(tester, 'perform-slot-elapsed'), slotBefore);
      expect(_textOf(tester, 'perform-clock'), clockBefore);
    },
  );

  testWidgets('the perform-program affordance is hidden for an empty program', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.programs.create(_program(const []));
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const ProgramEditorScreen(programId: 'p1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('perform-program')), findsNothing);
  });

  testWidgets('opens in the dark-stage high-contrast theme by default', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    final scheme = Theme.of(
      tester.element(find.byType(PerformCard)),
    ).colorScheme;
    expect(scheme, AppColorSchemes.highContrast);
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface, AppColorSchemes.highContrast.surface);
  });

  testWidgets('position label resolves under the stage theme when on', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    // The BottomAppBar position label must read its text style from a context
    // below PerformStageTheme, so on the dark stage BottomAppBar it uses the
    // stage theme's on-surface color rather than the ambient (light) theme.
    final positionContext = tester.element(
      find.byKey(const ValueKey('perform-position')),
    );
    expect(Theme.of(positionContext).colorScheme, AppColorSchemes.highContrast);
  });

  testWidgets('stage toggle falls back to the ambient theme and back', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    expect(
      Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
      AppColorSchemes.highContrast,
    );

    await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
      isNot(AppColorSchemes.highContrast),
    );

    await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
      AppColorSchemes.highContrast,
    );
  });

  testWidgets('stage toggle is keyboard/AT-reachable with on/off state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    final toggle = find.byKey(const ValueKey('perform-stage-toggle'));
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: true,
      ),
      reason: 'stage toggle must announce its on state',
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: false,
      ),
      reason: 'stage toggle must announce its off state after tapping',
    );

    handle.dispose();
  });

  testWidgets('new Perform controls are keyboard- and AT-reachable', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final data = await _dataWith([
      _dance(id: 'd1', title: 'Primary Dance'),
      _dance(id: 'd2', title: 'Alternate Dance'),
      _dance(id: 'd3', title: 'Third Dance'),
    ]);
    // Open at the middle group so both prev and next are enabled, and give the
    // first group an alternate so the swap control is present.
    await _pumpProgram(
      tester,
      data: data,
      initialGroup: 1,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
        _slot(id: 's3', position: 2, danceId: 'd3'),
      ]),
    );

    // The middle group (index 1) has no alternates, so swap is hidden there.
    // Navigate back to the first group, which does carry an alternate.
    await tester.tap(find.byKey(const ValueKey('perform-prev')));
    await tester.pumpAndSettle();

    for (final (key, label) in const [
      ('perform-program-exit', 'Exit performance view'),
      ('perform-jump', 'Jump to slot'),
      ('perform-alt-swap', 'Show alternate'),
      ('perform-next', 'Next slot'),
    ]) {
      expect(
        tester.getSemantics(find.byKey(ValueKey(key))),
        isSemantics(
          tooltip: label,
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
        ),
        reason: '$key must be labelled, focusable, and tappable',
      );
    }

    // Prev is enabled once we are on the last group again.
    await tester.tap(find.byKey(const ValueKey('perform-next')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const ValueKey('perform-prev'))),
      isSemantics(
        tooltip: 'Previous slot',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );

    handle.dispose();
  });

  testWidgets('the running program clock advances with wall time', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    final baseline = _seconds(_textOf(tester, 'perform-clock'));

    await tester.pump(const Duration(seconds: 65));
    expect(_textOf(tester, 'perform-clock'), _fmt(baseline + 65));

    // Past an hour it switches to the H:MM:SS form.
    await tester.pump(const Duration(seconds: 3600));
    final past = _textOf(tester, 'perform-clock');
    expect(past, _fmt(baseline + 3665));
    expect(past.split(':').length, 3);
  });

  testWidgets('per-slot elapsed advances and resets on navigation', (
    tester,
  ) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'First Dance'),
      _dance(id: 'd2', title: 'Second Dance'),
      _dance(id: 'd3', title: 'Third Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
        _slot(id: 's3', position: 2, danceId: 'd3'),
      ]),
    );

    // Next resets the per-slot timer (to an exact zero) but keeps the program
    // clock running.
    await tester.tap(find.byKey(const ValueKey('perform-next')));
    await tester.pump();
    expect(_textOf(tester, 'perform-slot-elapsed'), '0:00');

    final clockAfterReset = _seconds(_textOf(tester, 'perform-clock'));
    await tester.pump(const Duration(seconds: 2));
    expect(_textOf(tester, 'perform-slot-elapsed'), '0:02');
    expect(_seconds(_textOf(tester, 'perform-clock')), clockAfterReset + 2);

    // Prev also resets.
    await tester.tap(find.byKey(const ValueKey('perform-prev')));
    await tester.pump();
    expect(_textOf(tester, 'perform-slot-elapsed'), '0:00');

    await tester.pump(const Duration(seconds: 3));
    expect(_textOf(tester, 'perform-slot-elapsed'), '0:03');

    // Jump resets. (pumpAndSettle advances the clock slightly after the reset,
    // so assert the per-slot timer dropped rather than an exact zero.)
    await tester.tap(find.byKey(const ValueKey('perform-jump')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perform-jump-slot-2')));
    await tester.pumpAndSettle();
    expect(_seconds(_textOf(tester, 'perform-slot-elapsed')), lessThan(3));
  });

  testWidgets('alt-swap resets the per-slot elapsed', (tester) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'Primary Dance'),
      _dance(id: 'd2', title: 'Alternate Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
      ]),
    );

    await tester.pump(const Duration(seconds: 5));
    expect(
      _seconds(_textOf(tester, 'perform-slot-elapsed')),
      greaterThanOrEqualTo(5),
    );
    final clockBefore = _seconds(_textOf(tester, 'perform-clock'));

    await tester.tap(find.byKey(const ValueKey('perform-alt-swap')));
    await tester.pump();
    expect(_textOf(tester, 'perform-slot-elapsed'), '0:00');
    // Program clock keeps running across the swap.
    expect(_seconds(_textOf(tester, 'perform-clock')), clockBefore);
  });

  testWidgets('planned minutes render when present and are absent when null', (
    tester,
  ) async {
    final data = await _dataWith([
      _dance(id: 'd1', title: 'Timed Dance'),
      _dance(id: 'd2', title: 'Untimed Dance'),
    ]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1', plannedMinutes: 8),
        _slot(id: 's2', position: 1, danceId: 'd2'),
      ]),
    );

    expect(find.byKey(const ValueKey('perform-planned')), findsOneWidget);
    expect(find.text('planned 8 min'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perform-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('perform-planned')), findsNothing);
  });

  testWidgets('an over-run cue appears once elapsed passes planned', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'Timed Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1', plannedMinutes: 1),
      ]),
    );

    expect(find.byKey(const ValueKey('perform-over')), findsNothing);
    // Push past the 1-minute plan.
    await tester.pump(const Duration(seconds: 61));
    expect(find.byKey(const ValueKey('perform-over')), findsOneWidget);
  });

  testWidgets('pause stops the timers and resume continues them', (
    tester,
  ) async {
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    final start = _seconds(_textOf(tester, 'perform-clock'));
    await tester.pump(const Duration(seconds: 2));
    expect(_seconds(_textOf(tester, 'perform-clock')), start + 2);

    await tester.tap(find.byKey(const ValueKey('perform-timer-pause')));
    await tester.pump();
    final frozenClock = _textOf(tester, 'perform-clock');
    final frozenSlot = _textOf(tester, 'perform-slot-elapsed');
    await tester.pump(const Duration(seconds: 5));
    // Frozen while paused.
    expect(_textOf(tester, 'perform-clock'), frozenClock);
    expect(_textOf(tester, 'perform-slot-elapsed'), frozenSlot);

    await tester.tap(find.byKey(const ValueKey('perform-timer-pause')));
    await tester.pump();
    final resumed = _seconds(_textOf(tester, 'perform-clock'));
    await tester.pump(const Duration(seconds: 3));
    expect(_seconds(_textOf(tester, 'perform-clock')), resumed + 3);
  });

  testWidgets('pause/resume toggle is keyboard/AT-reachable with state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
    await _pumpProgram(
      tester,
      data: data,
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    final pause = find.byKey(const ValueKey('perform-timer-pause'));
    expect(
      tester.getSemantics(pause),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: false,
      ),
      reason: 'pause toggle starts in the running (un-paused) state',
    );

    await tester.tap(pause);
    await tester.pump();
    expect(
      tester.getSemantics(pause),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: true,
      ),
      reason: 'pause toggle announces its paused state after tapping',
    );

    handle.dispose();
  });

  testWidgets(
    'a per-second tick rebuilds only the clock, not the card/figures',
    (tester) async {
      final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
      await _pumpProgram(
        tester,
        data: data,
        program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
      );

      // Capture the exact PerformCard widget instance and the clock reading.
      final cardBefore = tester.widget<PerformCard>(find.byType(PerformCard));
      final clockBefore = _seconds(_textOf(tester, 'perform-clock'));

      await tester.pump(const Duration(seconds: 1));

      // The clock advanced (the tick fired)...
      expect(_seconds(_textOf(tester, 'perform-clock')), clockBefore + 1);
      // ...but the screen did not rebuild: the card is the same widget
      // instance, so `deriveSections`/`renderSummary` are not re-run each
      // second (that full-rebuild storm was the bug).
      final cardAfter = tester.widget<PerformCard>(find.byType(PerformCard));
      expect(identical(cardBefore, cardAfter), isTrue);
    },
  );

  group('auto-size (ROADMAP G.1)', () {
    testWidgets('recomputes the fit when navigating to another slot', (
      tester,
    ) async {
      final data = await _dataWith([
        _dance(id: 'd1', title: 'Short'),
        _dance(id: 'd2', title: 'Short'),
      ]);
      final program = _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, text: 'Break — grab water and rest up'),
      ]);

      await _pumpProgram(tester, program: program, data: data, autoSize: true);

      // First slot is a dance card; auto-size settled without overflow.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('perform-title')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('perform-next')));
      await tester.pumpAndSettle();

      // Second slot is a text-only card; the fit recomputes cleanly.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('perform-text')), findsOneWidget);
    });

    testWidgets(
      'revisiting a fitted slot keeps its scale (no auto-size grow-in flash)',
      (tester) async {
        final data = await _dataWith([
          _dance(id: 'd1', title: 'First Dance'),
          _dance(id: 'd2', title: 'Second Dance'),
        ]);
        await _pumpProgram(
          tester,
          data: data,
          autoSize: true,
          program: _program([
            _slot(id: 's1', position: 0, danceId: 'd1'),
            _slot(id: 's2', position: 1, danceId: 'd2'),
          ]),
        );

        // Slot 1 has settled at its fitted scale.
        final fitted = tester.getSize(
          find.byKey(const ValueKey('perform-title')),
        );

        // Visit slot 2 (settles at its own fit), then return to slot 1.
        await tester.tap(find.byKey(const ValueKey('perform-next')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('perform-prev')));
        // Exactly one frame after returning: the cached per-slot scale means
        // slot 1 renders at its remembered fit immediately. Without the cache
        // the fit restarts at minScale, so the title would be visibly smaller
        // for this frame (the "grow-in" flash) before growing back.
        await tester.pump();

        final revisitFirstFrame = tester.getSize(
          find.byKey(const ValueKey('perform-title')),
        );
        expect(revisitFirstFrame.height, closeTo(fitted.height, 1.0));
      },
    );

    testWidgets(
      'revisiting a dance across a free-text slot keeps its scale (mixed '
      'program)',
      (tester) async {
        final data = await _dataWith([_dance(id: 'd1', title: 'First Dance')]);
        await _pumpProgram(
          tester,
          data: data,
          autoSize: true,
          // Mixed program: a dance card then a free-text card. Navigating
          // between them swaps card types, which disposes the dance card's
          // `_FitToHeight` state — so only a cache held above that switch keeps
          // the dance's fitted scale for the return visit.
          program: _program([
            _slot(id: 's1', position: 0, danceId: 'd1'),
            _slot(id: 's2', position: 1, text: 'Break — grab water and rest'),
          ]),
        );

        // Dance slot settled at its fitted scale.
        final fitted = tester.getSize(
          find.byKey(const ValueKey('perform-title')),
        );

        // Go to the free-text slot (a different card type replaces the dance
        // subtree), then back to the dance.
        await tester.tap(find.byKey(const ValueKey('perform-next')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('perform-text')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('perform-prev')));
        // One frame after returning: the parent-owned scale cache means the
        // dance renders at its remembered fit immediately — no grow-in flash,
        // even though its own fit state was disposed while on the text slot.
        await tester.pump();

        final revisitFirstFrame = tester.getSize(
          find.byKey(const ValueKey('perform-title')),
        );
        expect(revisitFirstFrame.height, closeTo(fitted.height, 1.0));
      },
    );

    testWidgets('auto-size toggle is AT-reachable and reflects its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final data = await _dataWith([_dance(id: 'd1', title: 'Short')]);
      final program = _program([_slot(id: 's1', position: 0, danceId: 'd1')]);

      await _pumpProgram(tester, program: program, data: data, autoSize: true);

      final toggle = find.byKey(const ValueKey('perform-autosize-toggle'));
      expect(
        tester.getSemantics(toggle),
        isSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasToggledState: true,
          isToggled: true,
        ),
      );

      // Using A- hands control back to manual sizing.
      await tester.tap(find.byKey(const ValueKey('decrease-text-size')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(toggle), isSemantics(isToggled: false));

      handle.dispose();
    });
  });

  group('a11y prefs persistence (issue #449)', () {
    // Builds the program Perform view against a caller-supplied repositories so
    // a test can seed the settings store (restore) or read it back after
    // interacting (write-through). Mirrors [_pumpProgram] but shares one store.
    Future<void> pumpWith(
      WidgetTester tester,
      CompendiumRepositories repos, {
      required Program program,
      required CollectionData data,
      Dialect? activeDialect,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<Dialect>(
        activeDialect ?? Dialect.larksRobins,
      );
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
          home: PerformProgramScreen(
            program: program,
            data: data,
            renderer: _renderer,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<CollectionData> singleDanceData() =>
        _dataWith([_dance(id: 'd1', title: 'First Dance')]);

    Program singleDanceProgram() =>
        _program([_slot(id: 's1', position: 0, danceId: 'd1')]);

    testWidgets('restores persisted stage mode and canonical view on entry', (
      tester,
    ) async {
      final data = await singleDanceData();
      final repos = openTestRepositories();
      await repos.settings.set(kAutoSizePerformKey, false);
      await repos.settings.set(kPerformStageModeKey, false);
      await repos.settings.set(kPerformCanonicalViewKey, true);

      await pumpWith(tester, repos, program: singleDanceProgram(), data: data);

      // Stage mode restored OFF -> the ambient (non-stage) theme applies.
      expect(
        Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
        isNot(AppColorSchemes.highContrast),
      );
      // Canonical view restored ON -> figures show canonical tokens.
      expect(find.text('role2s chain'), findsOneWidget);
      expect(find.text('robins chain'), findsNothing);
    });

    testWidgets('restores a persisted manual text scale on entry', (
      tester,
    ) async {
      final data = await singleDanceData();
      final repos = openTestRepositories();
      await repos.settings.set(kAutoSizePerformKey, false);
      await repos.settings.set(
        kPerformTextScaleKey,
        kPerformDefaultScale + 2 * kPerformScaleStep,
      );

      await pumpWith(tester, repos, program: singleDanceProgram(), data: data);

      // Manual mode with an empty store renders at exactly the default scale,
      // so a restored larger scale must read above the default.
      final restoredScale = MediaQuery.of(
        tester.element(find.byKey(const ValueKey('perform-title'))),
      ).textScaler.scale(1);
      expect(restoredScale, greaterThan(kPerformDefaultScale));
    });

    testWidgets('applies defaults and does not crash when the store is empty', (
      tester,
    ) async {
      final data = await singleDanceData();
      final repos = openTestRepositories();

      await pumpWith(tester, repos, program: singleDanceProgram(), data: data);

      expect(tester.takeException(), isNull);
      expect(
        Theme.of(tester.element(find.byType(PerformCard))).colorScheme,
        AppColorSchemes.highContrast,
      );
      expect(find.text('robins chain'), findsOneWidget);
      expect(find.text('role2s chain'), findsNothing);
    });

    testWidgets('writes each pref through to the settings store on change', (
      tester,
    ) async {
      final data = await singleDanceData();
      final repos = openTestRepositories();
      await repos.settings.set(kAutoSizePerformKey, false);

      await pumpWith(tester, repos, program: singleDanceProgram(), data: data);

      await tester.tap(find.byKey(const ValueKey('perform-stage-toggle')));
      await tester.pumpAndSettle();
      expect(await repos.settings.get(kPerformStageModeKey), isFalse);

      await tester.tap(find.byKey(const ValueKey('perform-dialect-toggle')));
      await tester.pumpAndSettle();
      expect(await repos.settings.get(kPerformCanonicalViewKey), isTrue);

      await tester.tap(find.byKey(const ValueKey('increase-text-size')));
      await tester.pumpAndSettle();
      final storedScale = await repos.settings.get(kPerformTextScaleKey);
      expect(storedScale, isA<num>());
      expect(
        (storedScale as num).toDouble(),
        greaterThan(kPerformDefaultScale),
      );
    });
  });

  group('walkthrough overlay (issue #370)', () {
    testWidgets('shows the active dance-slot walkthrough on toggle', (
      tester,
    ) async {
      final dance = _dance(
        id: 'd1',
        title: 'Sarahs Journey',
        walkthrough: 'A1: neighbours balance and swing.',
      );
      final data = await _dataWith([dance]);
      await _pumpProgram(
        tester,
        program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
        data: data,
      );

      final toggle = find.byKey(const ValueKey('perform-walkthrough-toggle'));
      expect(toggle, findsOneWidget);
      expect(find.byType(PerformWalkthroughOverlay), findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(PerformWalkthroughOverlay), findsOneWidget);
      expect(find.text('A1: neighbours balance and swing.'), findsOneWidget);
    });

    testWidgets('no toggle for a free-text-only slot', (tester) async {
      final data = await _dataWith(const []);
      await _pumpProgram(
        tester,
        program: _program([_slot(id: 's1', position: 0, text: 'Waltz break')]),
        data: data,
      );
      expect(
        find.byKey(const ValueKey('perform-walkthrough-toggle')),
        findsNothing,
      );
    });
  });
}
