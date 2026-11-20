import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title, DanceForm form) => Dance(
  id: id,
  title: title,
  form: form,
  formation: Formation(
    form == DanceForm.ecd
        ? FormationShape.dupleMinor
        : FormationShape.dupleImproper,
  ),
  createdAt: _now,
  updatedAt: _now,
);

/// Opens the program of [dances] in the wide programs shell's summary.
Future<void> _pumpSummary(
  WidgetTester tester,
  List<Dance> dances, {
  Set<String> deleted = const {},
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final repos = openTestRepositories();
  for (final dance in dances) {
    await repos.dances.create(dance);
  }
  for (final id in deleted) {
    await repos.dances.softDelete(id, at: _now);
  }
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Friday Dance',
      status: ProgramStatus.draft,
      slots: [
        for (var i = 0; i < dances.length; i++)
          ProgramSlot(id: 's$i', position: i, danceId: dances[i].id),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
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
  await tester.tap(find.text('Friday Dance'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a program that mixes forms names each dance\'s form '
      '(ADR-006 S5)', (tester) async {
    await _pumpSummary(tester, [
      _dance('e', 'Hole in the Wall', DanceForm.ecd),
      _dance('c', 'Contra One', DanceForm.contra),
    ]);
    expect(find.text('English (ECD) · Duple minor'), findsOneWidget);
    expect(find.text('Contra · Improper'), findsOneWidget);
    // Read out too, so the form is not shown only to sighted users.
    expect(
      find.bySemanticsLabel(RegExp(r'Hole in the Wall\. English \(ECD\)\.')),
      findsOneWidget,
    );
  });

  testWidgets('a program of one form names none', (tester) async {
    await _pumpSummary(tester, [
      _dance('a', 'One', DanceForm.contra),
      _dance('b', 'Two', DanceForm.contra),
    ]);
    // The slot rows name no form (the program's own forms line and its list
    // row say "Contra" once for all of them).
    expect(find.text('Contra · Improper'), findsNothing);
    expect(find.text('Improper'), findsNWidgets(2));
  });

  testWidgets('the program names its forms at the top and in the list '
      '(ADR-006)', (tester) async {
    await _pumpSummary(tester, [
      _dance('e', 'Hole in the Wall', DanceForm.ecd),
      _dance('c', 'Contra One', DanceForm.contra),
    ]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('program-summary-forms')),
        matching: find.text('Contra + English (ECD)'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r'^Contra \+ English \(ECD\) · ')),
      findsOneWidget,
      reason: 'the programs list row leads with the forms',
    );
  });

  testWidgets('a deleted dance does not count toward the forms', (
    tester,
  ) async {
    await _pumpSummary(
      tester,
      [
        _dance('e', 'Hole in the Wall', DanceForm.ecd),
        _dance('c', 'Contra One', DanceForm.contra),
      ],
      deleted: {'e'},
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('program-summary-forms')),
        matching: find.text('Contra'),
      ),
      findsOneWidget,
    );
    // Nor does any row name its form, as the program no longer mixes them.
    expect(find.text('Contra · Improper'), findsNothing);
  });

  testWidgets('a program with no dances names no form', (tester) async {
    await _pumpSummary(tester, const []);
    expect(find.byKey(const ValueKey('program-summary-forms')), findsNothing);
  });
}
