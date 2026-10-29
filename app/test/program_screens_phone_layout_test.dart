// The program summary and builder at a 360dp phone width (UX4-4, and the
// builder's slot rows under maintainer decision D-2; see docs/design/ux.md §4
// for the decision's wording and where it is recorded). Below the 600dp compact
// breakpoint the toolbars keep Perform and Export and fold Mark all performed,
// Duplicate and Delete into "⋮"; each slot row keeps only its drag handle and
// "⋮". Before this, the builder's title got 32dp, a slot title 8dp, and an
// alternate slot row overflowed by 24dp.
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

Future<CompendiumRepositories> _seed() async {
  final repos = openTestRepositories();
  await repos.dances.create(
    _dance(id: 'd1', title: 'Chase the Squirrel Around the Old Oak Tree'),
  );
  await repos.dances.create(
    _dance(id: 'd2', title: 'The Big Circle Mixer of the Long Winter Night'),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Barn Dance at the Grange Hall',
      status: ProgramStatus.draft,
      slots: [
        ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's1', position: 1, danceId: 'd2', isAlt: true),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return repos;
}

/// Pumps the Programs shell at a phone size and opens the program's summary.
Future<void> _openSummaryOnPhone(
  WidgetTester tester,
  CompendiumRepositories repos, {
  Size size = const Size(360, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final dialect = ValueNotifier<Dialect>(Dialect.canonical);
  addTearDown(dialect.dispose);
  final showToggles = ValueNotifier<bool>(true);
  addTearDown(showToggles.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => ShowPerformedTogglesScope(
        notifier: showToggles,
        child: RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: dialect, child: child!),
        ),
      ),
      home: const ProgramsShell(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Barn Dance at the Grange Hall'));
  await tester.pumpAndSettle();
}

Future<void> _openBuilderFromSummary(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-builder')));
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  group('summary at 360dp', () {
    testWidgets('keeps Perform and Export, and folds Mark all performed, '
        'Duplicate and Delete into ⋮', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);

      expect(tester.takeException(), isNull);
      expect(_key('summary-perform'), findsOneWidget);
      expect(_key('program-export-menu'), findsOneWidget);
      expect(_key('mark-all-performed'), findsNothing);
      expect(_key('summary-duplicate'), findsNothing);
      expect(_key('summary-delete'), findsNothing);
      // The program title keeps most of the row.
      final title = find.text('Barn Dance at the Grange Hall').last;
      expect(tester.getSize(title).width, greaterThan(180));

      await tester.tap(_key('summary-actions-overflow'));
      await tester.pumpAndSettle();
      expect(_key('mark-all-performed'), findsOneWidget);
      expect(_key('summary-duplicate'), findsOneWidget);
      expect(_key('summary-delete'), findsOneWidget);

      await tester.tap(_key('mark-all-performed'));
      await tester.pumpAndSettle();
      final saved = (await repos.programs.getById('p1'))!;
      expect(
        saved.slots.firstWhere((s) => s.id == 's0').performedAt,
        isNotNull,
      );
      // Alternates are skipped by Mark all performed.
      expect(saved.slots.firstWhere((s) => s.id == 's1').performedAt, isNull);
    });

    // A characterization guard rather than a regression test: this change
    // leaves summary rows alone, and the audit asked that F5b's per-row
    // performed toggle be checked at 360dp beside the new title row.
    testWidgets('slot rows leave room for the per-row performed toggle', (
      tester,
    ) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);

      expect(tester.takeException(), isNull);
      expect(_key('summary-slot-s0-performed-toggle'), findsOneWidget);
      expect(_key('summary-slot-s1-performed-toggle'), findsOneWidget);
      for (final title in [
        'Chase the Squirrel Around the Old Oak Tree',
        'The Big Circle Mixer of the Long Winter Night',
      ]) {
        expect(tester.getSize(find.text(title)).width, greaterThan(120));
      }
    });
  });

  group('summary ⋮ at 360dp', () {
    testWidgets('Duplicate runs from ⋮', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);
      await tester.tap(_key('summary-actions-overflow'));
      await tester.pumpAndSettle();
      await tester.tap(_key('summary-duplicate'));
      await tester.pumpAndSettle();
      expect(await repos.programs.listAll(), hasLength(2));
    });

    testWidgets('Delete runs from ⋮', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);
      await tester.tap(_key('summary-actions-overflow'));
      await tester.pumpAndSettle();
      await tester.tap(_key('summary-delete'));
      await tester.pumpAndSettle();
      expect(await repos.programs.getById('p1'), isNull);
    });
  });

  group('builder at 360dp', () {
    testWidgets('the app bar keeps Perform and Export, and folds Mark all '
        'performed, Duplicate and Delete into ⋮', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);
      await _openBuilderFromSummary(tester);

      expect(tester.takeException(), isNull);
      expect(_key('perform-program'), findsOneWidget);
      expect(_key('program-export-menu'), findsOneWidget);
      expect(_key('mark-all-performed'), findsNothing);
      expect(_key('duplicate-program'), findsNothing);
      expect(_key('delete-program'), findsNothing);
      // The full bar left "Build program" 32dp.
      expect(
        tester.getSize(find.text('Build program')).width,
        greaterThan(100),
      );

      await tester.tap(_key('program-actions-overflow'));
      await tester.pumpAndSettle();
      expect(_key('mark-all-performed'), findsOneWidget);
      expect(_key('duplicate-program'), findsOneWidget);
      expect(_key('delete-program'), findsOneWidget);
    });

    testWidgets('Mark all performed and Duplicate run from ⋮', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);
      await _openBuilderFromSummary(tester);

      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      await tester.tap(_key('program-actions-overflow'));
      await tester.pumpAndSettle();
      await tester.tap(_key('mark-all-performed'));
      await tester.pumpAndSettle();
      // The primary gets its performed check; the alternate is skipped.
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await tester.tap(_key('program-actions-overflow'));
      await tester.pumpAndSettle();
      await tester.tap(_key('duplicate-program'));
      await tester.pumpAndSettle();
      expect(await repos.programs.listAll(), hasLength(2));
    });

    testWidgets('Delete from ⋮ deletes the program', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);
      await _openBuilderFromSummary(tester);

      await tester.tap(_key('program-actions-overflow'));
      await tester.pumpAndSettle();
      await tester.tap(_key('delete-program'));
      await tester.pumpAndSettle();
      expect(await repos.programs.getById('p1'), isNull);
      expect(find.text('Build program'), findsNothing);
    });

    testWidgets('slot rows keep only the drag handle and ⋮, and do not '
        'overflow', (tester) async {
      final repos = await _seed();
      await _openSummaryOnPhone(tester, repos);
      await _openBuilderFromSummary(tester);

      expect(tester.takeException(), isNull);
      for (final i in [0, 1]) {
        expect(_key('slot-$i-menu'), findsOneWidget);
        expect(_key('slot-$i-move-up'), findsNothing);
        expect(_key('slot-$i-move-down'), findsNothing);
        expect(_key('slot-$i-remove'), findsNothing);
        expect(_key('slot-$i-view-details'), findsNothing);
      }
      // The primary's title had 8dp beside four inline buttons. The alternate
      // row is indented under its primary and badged "Alt", so its title is
      // the narrowest; before, it got none and the row overflowed.
      expect(tester.getSize(_key('slot-s0-title')).width, greaterThan(150));
      expect(tester.getSize(_key('slot-s1-title')).width, greaterThan(70));
    });
  });
}
