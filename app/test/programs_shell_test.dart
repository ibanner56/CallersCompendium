import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';

import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Program _program({required String id, required String title}) => Program(
  id: id,
  title: title,
  status: ProgramStatus.draft,
  slots: const [],
  createdAt: _now,
  updatedAt: _now,
);

Dance _dance({required String id, required String title, DanceLevel? level}) =>
    Dance(
      id: id,
      title: title,
      authorIds: const [],
      tagIds: const [],
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      level: level,
      figures: const [],
      customFields: const [],
      hook: '',
      createdAt: _now,
      updatedAt: _now,
    );

Future<void> _pumpWide(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: ValueNotifier<Dialect>(Dialect.canonical),
          child: child!,
        ),
      ),
      home: const ProgramsShell(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'wide split-pane list and summary FABs coexist and survive a route '
    'transition without a duplicate hero-tag crash',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Barn Dance'));

      await _pumpWide(tester, repos);

      // Select the program so the summary pane (and its "Open builder" FAB)
      // renders alongside the list pane's "New program" FAB.
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      // Both default-styled FABs are present in the same subtree. Before the
      // fix they shared the default Hero tag, which crashed on the next route
      // transition with "multiple heroes that share the same tag".
      expect(find.byKey(const ValueKey('new-program')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-builder')), findsOneWidget);

      // Opening the builder pushes a full-screen route, driving a Hero
      // transition that scans the outgoing subtree for heroes.
      await tester.tap(find.byKey(const ValueKey('open-builder')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ProgramEditorScreen), findsOneWidget);
    },
  );

  testWidgets(
    'summary pane renders the set list in order with ALT alternates indented '
    'under their primary and free-text slots as text',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(
          id: 'd1',
          title: 'Chase the Squirrel',
          level: DanceLevel.beginner,
        ),
      );
      await repos.dances.create(_dance(id: 'd2', title: 'Petronella'));
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [
            ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
            ProgramSlot(id: 's1', position: 1, danceId: 'd2', isAlt: true),
            ProgramSlot(id: 's2', position: 2, text: 'Break'),
          ],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      // Section header carries the slot count.
      expect(find.text('Set list (3)'), findsOneWidget);

      // All three slots render.
      expect(find.text('Chase the Squirrel'), findsOneWidget);
      expect(find.text('Petronella'), findsOneWidget);
      expect(find.text('Break'), findsOneWidget);

      // The dance rows are tappable; the free-text slot is not.
      expect(find.byKey(const ValueKey('summary-slot-s0')), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-slot-s1')), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-slot-s2')), findsNothing);

      // Primary secondary line surfaces formation + level.
      expect(find.text('Duple improper · Beginner'), findsOneWidget);

      // The alternate (s1) renders indented (extra left padding) relative to
      // its primary (s0) and shows an "Alt" label + icon, never colour alone.
      expect(find.text('Alt'), findsOneWidget);
      expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);
      final primaryLeft = tester
          .getTopLeft(find.byKey(const ValueKey('summary-slot-s0')))
          .dx;
      final altLeft = tester
          .getTopLeft(find.byKey(const ValueKey('summary-slot-s1')))
          .dx;
      expect(altLeft, greaterThan(primaryLeft));

      // Position order: primary dance sits above its alternate, which sits
      // above the trailing free-text slot.
      final primaryTop = tester.getTopLeft(find.text('Chase the Squirrel')).dy;
      final altTop = tester.getTopLeft(find.text('Petronella')).dy;
      final breakTop = tester.getTopLeft(find.text('Break')).dy;
      expect(primaryTop, lessThan(altTop));
      expect(altTop, lessThan(breakTop));
    },
  );

  testWidgets(
    'tapping a dance row in the summary set list opens DanceDetailScreen',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      expect(find.byType(DanceDetailScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('summary-slot-s0')));
      await tester.pumpAndSettle();

      expect(find.byType(DanceDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a dance row exposes a single button semantics node (role + label + '
    'focusable + tap action)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(const ValueKey('summary-slot-s0'))),
        isSemantics(
          label: 'Chase the Squirrel',
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'an unresolved dance id renders a non-tappable "Dance unavailable" fallback',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      // The dance is soft-deleted after the program references it, so the
      // slot's danceId no longer resolves to a title.
      await repos.dances.softDelete('d1', at: _now);

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      expect(find.text('Dance unavailable'), findsOneWidget);
      expect(find.byKey(const ValueKey('summary-slot-s0')), findsNothing);
    },
  );

  testWidgets('an empty program shows the teaching empty state', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.programs.create(_program(id: 'p1', title: 'Barn Dance'));

    await _pumpWide(tester, repos);
    await tester.tap(find.text('Barn Dance'));
    await tester.pumpAndSettle();

    expect(find.text('Set list (0)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('summary-set-list-empty')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the summary pane renders a reachable "Perform this program" action for a '
    'program with slots, and tapping it opens PerformProgramScreen',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('summary-perform')), findsOneWidget);
      expect(find.byType(PerformProgramScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('summary-perform')));
      await tester.pumpAndSettle();

      // The current saved program is handed to the Perform view.
      expect(find.byType(PerformProgramScreen), findsOneWidget);
      expect(find.text('Chase the Squirrel'), findsOneWidget);
    },
  );

  testWidgets(
    'the "Perform this program" action is disabled for a program with no slots',
    (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program(id: 'p1', title: 'Barn Dance'));

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      // The action is present but a dead-button guard is in place: the button
      // is disabled (no tap action exposed to AT), never absent-and-tappable.
      final finder = find.byKey(const ValueKey('summary-perform'));
      expect(finder, findsOneWidget);

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(finder),
        isSemantics(
          label: 'Perform this program',
          isButton: true,
          isEnabled: false,
          hasEnabledState: true,
          hasTapAction: false,
        ),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'the enabled "Perform this program" action exposes a single button node '
    '(role + label + focusable + tap action)',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
      await repos.programs.create(
        Program(
          id: 'p1',
          title: 'Barn Dance',
          status: ProgramStatus.draft,
          slots: [ProgramSlot(id: 's0', position: 0, danceId: 'd1')],
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      await _pumpWide(tester, repos);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(const ValueKey('summary-perform'))),
        isSemantics(
          label: 'Perform this program',
          isButton: true,
          isFocusable: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    },
  );
}
