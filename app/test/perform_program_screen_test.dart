import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_card.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/theme/color_schemes.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';

final _now = DateTime.utc(2026, 1, 1);
final _renderer = FigureRenderer(contraTaxonomy);

Dance _dance({required String id, required String title}) => Dance(
  id: id,
  title: title,
  figures: [
    Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
  ],
  status: DanceStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

ProgramSlot _slot({
  required String id,
  required int position,
  String? danceId,
  String? text,
  bool isAlt = false,
}) => ProgramSlot(
  id: id,
  position: position,
  danceId: danceId,
  text: text,
  isAlt: isAlt,
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
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(activeDialect ?? Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          ActiveDialectScope(notifier: notifier, child: child!),
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

    await tester.tap(find.byKey(const ValueKey('perform-program-exit')));
    await tester.pumpAndSettle();

    expect(find.byType(PerformProgramScreen), findsNothing);
    expect(find.byType(ProgramEditorScreen), findsOneWidget);
  });

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
}
