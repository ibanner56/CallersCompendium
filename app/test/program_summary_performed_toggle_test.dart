import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_performed_toggles_scope.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);
final _stamp = DateTime.utc(2026, 1, 1, 20);

Dance _dance({required String id, required String title}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

Finder _toggle(String slotId) =>
    find.byKey(ValueKey('summary-slot-$slotId-performed-toggle'));

Future<void> _pumpWide(
  WidgetTester tester,
  CompendiumRepositories repos, {
  ValueNotifier<bool>? showToggles,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) {
        Widget tree = RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(
            notifier: ValueNotifier<Dialect>(Dialect.canonical),
            child: child!,
          ),
        );
        if (showToggles != null) {
          tree = ShowPerformedTogglesScope(notifier: showToggles, child: tree);
        }
        return tree;
      },
      home: const ProgramsShell(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<CompendiumRepositories> _seed({List<ProgramSlot>? slots}) async {
  final repos = openTestRepositories();
  await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
  await repos.dances.create(_dance(id: 'd2', title: 'Big Circle'));
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Barn Dance',
      status: ProgramStatus.draft,
      slots:
          slots ??
          [
            ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's1', position: 1, danceId: 'd2', isAlt: true),
          ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return repos;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Barn Dance'));
  await tester.pumpAndSettle();
}

Future<ProgramSlot> _slot(CompendiumRepositories repos, String id) async {
  final saved = await repos.programs.getById('p1');
  return saved!.slots.firstWhere((s) => s.id == id);
}

void main() {
  testWidgets('a primary row toggles performed on and off, stamping and '
      'clearing', (tester) async {
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);

    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();
    final marked = (await _slot(repos, 's0')).performedAt;
    expect(marked, isNotNull);
    expect(find.text('Marked Chase the Squirrel performed.'), findsOneWidget);

    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();
    expect((await _slot(repos, 's0')).performedAt, isNull);
    expect(
      find.text('Cleared the performed mark on Chase the Squirrel.'),
      findsOneWidget,
    );
  });

  testWidgets('marking an alternate makes it count toward calling history', (
    tester,
  ) async {
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);
    expect((await _slot(repos, 's1')).countsTowardCallingHistory, isFalse);

    await tester.tap(_toggle('s1'));
    await tester.pumpAndSettle();

    final alt = await _slot(repos, 's1');
    expect(alt.performedAt, isNotNull);
    expect(alt.countsTowardCallingHistory, isTrue);
    // Only the tapped row changed.
    expect((await _slot(repos, 's0')).performedAt, isNull);
  });

  testWidgets('Undo after marking clears the mark', (tester) async {
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);

    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();
    expect((await _slot(repos, 's0')).performedAt, isNotNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await _slot(repos, 's0')).performedAt, isNull);
  });

  testWidgets('Undo after clearing restores the same stamp', (tester) async {
    final repos = await _seed(
      slots: [
        ProgramSlot(id: 's0', position: 0, danceId: 'd1', performedAt: _stamp),
      ],
    );
    await _pumpWide(tester, repos);
    await _open(tester);

    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();
    expect((await _slot(repos, 's0')).performedAt, isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await _slot(repos, 's0')).performedAt, _stamp);
  });

  testWidgets('Undo refuses, and says so, once the program has been edited '
      'since the toggle', (tester) async {
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);

    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();
    final edited = (await repos.programs.getById('p1'))!;
    await tester.runAsync(
      () => repos.programs.update(
        edited.copyWith(
          title: 'Barn Dance (edited)',
          updatedAt: edited.updatedAt.add(const Duration(minutes: 1)),
        ),
      ),
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not undo that change to the performed mark.'),
      findsOneWidget,
    );
    // The later edit and the mark both survive.
    final saved = (await repos.programs.getById('p1'))!;
    expect(saved.title, 'Barn Dance (edited)');
    expect(saved.slots.first.performedAt, isNotNull);
  });

  testWidgets('a toggle never overwrites an edit the pane has not loaded yet', (
    tester,
  ) async {
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);

    // A write lands behind the pane's back and the tap follows before the
    // pane's stream has delivered it, so the pane's loaded copy is stale.
    final stored = (await repos.programs.getById('p1'))!;
    await tester.runAsync(
      () => repos.programs.update(
        stored.copyWith(
          notes: 'Bring the speaker',
          updatedAt: stored.updatedAt.add(const Duration(minutes: 1)),
        ),
      ),
    );
    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();

    final saved = (await repos.programs.getById('p1'))!;
    expect(saved.notes, 'Bring the speaker');
    expect(saved.slots.first.performedAt, isNotNull);
  });

  testWidgets('a tap sets the state the row showed, flipped, even if the store '
      'already holds it', (tester) async {
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);

    // Another writer marks s0 before the pane has loaded it: the row still
    // shows "not performed", so the tap means "mark" and must not clear it.
    final stored = (await repos.programs.getById('p1'))!;
    await tester.runAsync(
      () => repos.programs.update(
        stored.copyWith(
          slots: [
            stored.slots.first.copyWith(performedAt: _stamp),
            ...stored.slots.skip(1),
          ],
          updatedAt: stored.updatedAt.add(const Duration(minutes: 1)),
        ),
      ),
    );
    await tester.tap(_toggle('s0'));
    await tester.pumpAndSettle();

    expect((await _slot(repos, 's0')).performedAt, _stamp);
  });

  testWidgets('the toggle names the dance and its state to screen readers and '
      'is reachable without a swipe', (tester) async {
    final handle = tester.ensureSemantics();
    final repos = await _seed();
    await _pumpWide(tester, repos);
    await _open(tester);

    expect(
      find.bySemanticsLabel('Chase the Squirrel: not performed'),
      findsOneWidget,
    );
    // A plain tap action: no swipe, long press or menu needed.
    tester.semantics.tap(
      find.semantics.byLabel('Chase the Squirrel: not performed'),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Chase the Squirrel: performed'),
      findsOneWidget,
    );
    expect((await _slot(repos, 's0')).performedAt, isNotNull);
    handle.dispose();
  });

  testWidgets('with the setting off rows show performed state and no toggle', (
    tester,
  ) async {
    final repos = await _seed(
      slots: [
        ProgramSlot(id: 's0', position: 0, danceId: 'd1', performedAt: _stamp),
        ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
      ],
    );
    await _pumpWide(tester, repos, showToggles: ValueNotifier<bool>(false));
    await _open(tester);

    expect(_toggle('s0'), findsNothing);
    expect(_toggle('s1'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('flipping the setting adds and removes toggles live', (
    tester,
  ) async {
    final repos = await _seed();
    final showToggles = ValueNotifier<bool>(true);
    await _pumpWide(tester, repos, showToggles: showToggles);
    await _open(tester);
    expect(_toggle('s0'), findsOneWidget);

    showToggles.value = false;
    await tester.pumpAndSettle();
    expect(_toggle('s0'), findsNothing);

    showToggles.value = true;
    await tester.pumpAndSettle();
    expect(_toggle('s0'), findsOneWidget);
  });
}
