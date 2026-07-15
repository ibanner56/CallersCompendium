import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';

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

Program _program(List<ProgramSlot> slots) => Program(
  id: 'p1',
  title: 'Spring Dance',
  slots: slots,
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the program Perform view wired for in-event adjustments: a real
/// [RepositoriesScope] (so the adjust sheet's quick-search picker works) and an
/// `onProgramChanged` capture list. Returns the list of persisted programs.
Future<List<Program>> _pumpAdjustable(
  WidgetTester tester, {
  required List<Dance> dances,
  required Program program,
  int initialGroup = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repos = openTestRepositories();
  for (final d in dances) {
    await repos.dances.create(d);
  }
  final data = await CollectionData.load(repos);
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);

  final persisted = <Program>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: PerformProgramScreen(
        program: program,
        data: data,
        renderer: _renderer,
        initialGroup: initialGroup,
        onProgramChanged: (updated) async => persisted.add(updated),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return persisted;
}

Future<void> _openAdjust(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('perform-adjust')));
  await tester.pumpAndSettle();
}

Future<void> _tapDone(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('adjust-done')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(installFakeWakelock);

  testWidgets('adjust affordance is an enabled, AT-reachable button', (
    tester,
  ) async {
    await _pumpAdjustable(
      tester,
      dances: [_dance(id: 'd1', title: 'First Dance')],
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    expect(
      tester.getSemantics(find.byKey(const ValueKey('perform-adjust'))),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        tooltip: 'Adjust program',
      ),
    );
  });

  testWidgets('mark performed sets performedAt and persists; undo restores', (
    tester,
  ) async {
    final persisted = await _pumpAdjustable(
      tester,
      dances: [_dance(id: 'd1', title: 'First Dance')],
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    await _openAdjust(tester);

    // The mark control exposes its performed STATE (not color/icon-only) to AT.
    final markFinder = find.byKey(const ValueKey('adjust-mark-performed'));
    expect(
      tester.getSemantics(markFinder),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasToggledState: true,
        hasTapAction: true,
        label: 'Mark performed',
      ),
    );

    await tester.tap(markFinder);
    await tester.pumpAndSettle();
    await _tapDone(tester);

    expect(persisted, hasLength(1));
    expect(persisted.single.slots.single.performedAt, isNotNull);
    expect(
      persisted.single.updatedAt.isAfter(_now),
      isTrue,
      reason: 'updatedAt bumped',
    );

    // Undo restores the un-performed program (also persisted).
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(persisted, hasLength(2));
    expect(persisted.last.slots.single.performedAt, isNull);
  });

  testWidgets('reorder remaining slots reflects live and persists', (
    tester,
  ) async {
    final persisted = await _pumpAdjustable(
      tester,
      dances: [
        _dance(id: 'd1', title: 'First Dance'),
        _dance(id: 'd2', title: 'Second Dance'),
        _dance(id: 'd3', title: 'Third Dance'),
      ],
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2'),
        _slot(id: 's3', position: 2, danceId: 'd3'),
      ]),
    );

    expect(find.text('First Dance'), findsOneWidget);
    expect(find.text('Slot 1 of 3'), findsOneWidget);

    await _openAdjust(tester);

    // Non-drag move alternative (WCAG 2.5.7) is an enabled button.
    final moveDown = find.byKey(const ValueKey('adjust-move-down-0'));
    expect(
      tester.getSemantics(moveDown),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        tooltip: 'Move "First Dance" down',
      ),
    );
    await tester.tap(moveDown);
    await tester.pumpAndSettle();
    await _tapDone(tester);

    // The reading view follows the same dance to its new position.
    expect(find.text('First Dance'), findsOneWidget);
    expect(find.text('Slot 2 of 3'), findsOneWidget);

    expect(persisted, hasLength(1));
    expect(persisted.single.slots.map((s) => s.danceId).toList(), [
      'd2',
      'd1',
      'd3',
    ]);
    expect(persisted.single.slots.map((s) => s.position).toList(), [0, 1, 2]);
  });

  testWidgets('insert a dance from quick-search lands after the current slot', (
    tester,
  ) async {
    final persisted = await _pumpAdjustable(
      tester,
      dances: [
        _dance(id: 'd1', title: 'First Dance'),
        _dance(id: 'd2', title: 'Inserted Dance'),
      ],
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    await _openAdjust(tester);
    await tester.tap(find.byKey(const ValueKey('adjust-insert-dance')));
    await tester.pumpAndSettle();

    // The quick-search picker opens; add the second dance.
    await tester.tap(find.byKey(const ValueKey('picker-add-d2')));
    await tester.pumpAndSettle();
    await _tapDone(tester);

    expect(persisted, hasLength(1));
    expect(persisted.single.slots.map((s) => s.danceId).toList(), ['d1', 'd2']);
    expect(find.text('Slot 1 of 2'), findsOneWidget);
  });

  testWidgets('add an ad-hoc note inserts a free-text slot after current', (
    tester,
  ) async {
    final persisted = await _pumpAdjustable(
      tester,
      dances: [_dance(id: 'd1', title: 'First Dance')],
      program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
    );

    await _openAdjust(tester);
    await tester.enterText(
      find.byKey(const ValueKey('adjust-note-field')),
      'Waltz break',
    );
    await tester.tap(find.byKey(const ValueKey('adjust-add-note')));
    await tester.pumpAndSettle();
    await _tapDone(tester);

    expect(persisted, hasLength(1));
    expect(persisted.single.slots, hasLength(2));
    expect(persisted.single.slots[1].text, 'Waltz break');
    expect(persisted.single.slots[1].danceId, isNull);
    expect(find.text('Slot 1 of 2'), findsOneWidget);
  });

  testWidgets('adjustments are in-view only when no persistence callback', (
    tester,
  ) async {
    // Defensive: with onProgramChanged null the sheet still edits the live view
    // without throwing (no owner to persist through).
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'First Dance'));
    final data = await CollectionData.load(repos);
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: PerformProgramScreen(
          program: _program([_slot(id: 's1', position: 0, danceId: 'd1')]),
          data: data,
          renderer: _renderer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openAdjust(tester);
    await tester.enterText(
      find.byKey(const ValueKey('adjust-note-field')),
      'Announcements',
    );
    await tester.tap(find.byKey(const ValueKey('adjust-add-note')));
    await tester.pumpAndSettle();
    await _tapDone(tester);

    // Live view updated (2 slots now) even without a persistence callback.
    expect(find.text('Slot 1 of 2'), findsOneWidget);
  });
}
