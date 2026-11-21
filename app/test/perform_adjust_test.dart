import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/search/collection_data.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';

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
  List<Dance>? snapshotDances,
  Map<String, Dance> danceOverrides = const {},
  Map<String, String> authorNameOverrides = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repos = openTestRepositories();
  final initialDances = snapshotDances ?? dances;
  for (final d in initialDances) {
    await repos.dances.create(d);
  }
  final data = await CollectionData.load(repos);
  for (final d in dances) {
    if (!initialDances.any((initial) => initial.id == d.id)) {
      await repos.dances.create(d);
    }
  }
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);

  final persisted = <Program>[];
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
        danceOverrides: danceOverrides,
        authorNameOverrides: authorNameOverrides,
        initialGroup: initialGroup,
        onProgramChanged: (_, updated) async {
          persisted.add(updated);
          return null;
        },
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

  testWidgets('adjust sheet and picker resolve fresh program dance overrides', (
    tester,
  ) async {
    final fresh = _dance(id: 'fresh', title: 'Fresh Dance');
    await _pumpAdjustable(
      tester,
      dances: [fresh],
      snapshotDances: const [],
      danceOverrides: {fresh.id: fresh},
      program: _program([_slot(id: 's1', position: 0, danceId: fresh.id)]),
    );

    await _openAdjust(tester);
    expect(find.text('Fresh Dance'), findsAtLeastNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('adjust-insert-dance')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('adjust-picker')),
        matching: find.text('Fresh Dance'),
      ),
      findsOneWidget,
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

  // Only Done used to return the edits, so a swipe down or
  // a tap on the barrier silently threw away reorders and performed-marks made
  // mid-gig. Every way of closing the sheet now keeps them.
  group('closing the sheet without Done keeps the edits', () {
    final dances = [
      _dance(id: 'd1', title: 'First Dance'),
      _dance(id: 'd2', title: 'Second Dance'),
    ];
    Program twoSlots() => _program([
      _slot(id: 's1', position: 0, danceId: 'd1'),
      _slot(id: 's2', position: 1, danceId: 'd2'),
    ]);

    final dismissals = <String, Future<void> Function(WidgetTester)>{
      'swipe down': (tester) => tester.fling(
        find.byKey(const ValueKey('adjust-done')),
        const Offset(0, 1500),
        3000,
      ),
      'barrier tap': (tester) => tester.tapAt(const Offset(700, 20)),
      'system Back': (tester) => tester.binding.handlePopRoute(),
    };

    for (final MapEntry(key: how, value: dismiss) in dismissals.entries) {
      testWidgets('a reorder and a performed-mark survive $how', (
        tester,
      ) async {
        final persisted = await _pumpAdjustable(
          tester,
          dances: dances,
          program: twoSlots(),
        );
        await _openAdjust(tester);
        await tester.tap(find.byKey(const ValueKey('adjust-mark-performed')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('adjust-move-down-0')));
        await tester.pumpAndSettle();

        await dismiss(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('adjust-done')), findsNothing);
        expect(persisted, hasLength(1));
        expect(persisted.single.slots.map((s) => s.danceId).toList(), [
          'd2',
          'd1',
        ]);
        expect(
          persisted.single.slots.firstWhere((s) => s.id == 's1').performedAt,
          isNotNull,
        );
        // The reading view follows the moved dance, and the change is
        // offered for undo exactly as after Done.
        expect(find.text('Slot 2 of 2'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
      });
    }

    testWidgets('edits that cancel out change nothing when the sheet closes', (
      tester,
    ) async {
      final persisted = await _pumpAdjustable(
        tester,
        dances: dances,
        program: twoSlots(),
      );
      await _openAdjust(tester);
      final mark = find.byKey(const ValueKey('adjust-mark-performed'));
      await tester.tap(mark);
      await tester.pumpAndSettle();
      await tester.tap(mark);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-move-down-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adjust-move-up-1')));
      await tester.pumpAndSettle();

      await dismissals['swipe down']!(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('adjust-done')), findsNothing);
      expect(persisted, isEmpty);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('closing the sheet with no edits changes nothing', (
      tester,
    ) async {
      final persisted = await _pumpAdjustable(
        tester,
        dances: dances,
        program: twoSlots(),
      );
      await _openAdjust(tester);
      await dismissals['barrier tap']!(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('adjust-done')), findsNothing);
      expect(persisted, isEmpty);
      expect(find.text('Undo'), findsNothing);
    });
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
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
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

  testWidgets('adjustments keep the view on the selected alternate', (
    tester,
  ) async {
    final persisted = await _pumpAdjustable(
      tester,
      dances: [
        _dance(id: 'd1', title: 'Primary Dance'),
        _dance(id: 'd2', title: 'Alternate Dance'),
      ],
      program: _program([
        _slot(id: 's1', position: 0, danceId: 'd1'),
        _slot(id: 's2', position: 1, danceId: 'd2', isAlt: true),
      ]),
    );

    // Swap to the alternate, then make an unrelated adjustment.
    await tester.tap(find.byKey(const ValueKey('perform-alt-swap')));
    await tester.pumpAndSettle();
    expect(find.text('Alternate Dance'), findsOneWidget);

    await _openAdjust(tester);
    await tester.enterText(
      find.byKey(const ValueKey('adjust-note-field')),
      'Break',
    );
    await tester.tap(find.byKey(const ValueKey('adjust-add-note')));
    await tester.pumpAndSettle();
    await _tapDone(tester);

    // The reading view stays on the selected alternate, not its primary.
    expect(find.text('Alternate Dance'), findsOneWidget);
    expect(find.text('Primary Dance'), findsNothing);
    expect(persisted, hasLength(1));
  });
}
