import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

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
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,

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
  testWidgets('summary set list shows a performed indicator only on slots '
      'stamped performed', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Chase the Squirrel'));
    await repos.dances.create(_dance(id: 'd2', title: 'Big Circle'));
    await repos.programs.create(
      Program(
        id: 'p1',
        title: 'Barn Dance',
        status: ProgramStatus.draft,
        slots: [
          // s0 is marked performed; s1 is not.
          ProgramSlot(id: 's0', position: 0, danceId: 'd1', performedAt: _now),
          ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
        ],
        createdAt: _now,
        updatedAt: _now,
      ),
    );

    await _pumpWide(tester, repos);
    await tester.tap(find.text('Barn Dance'));
    await tester.pumpAndSettle();

    // Exactly one row carries the visual performed indicator.
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // The performed row's accessible name announces it; the non-performed row
    // does not (screen-reader parity with the visual cue).
    expect(
      find.bySemanticsLabel(RegExp(r'Chase the Squirrel.*Performed')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Big Circle.*Performed')),
      findsNothing,
    );
  });
}
