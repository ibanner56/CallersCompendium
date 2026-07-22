import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/set_list_color_coding_scope.dart';
import 'package:compendium_app/src/screens/programs_shell.dart';
import 'package:compendium_app/src/theme/set_list_accents.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  required String title,
  required FormationShape shape,
}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: Formation(shape),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps the wide split-pane programs shell, optionally wrapping it in a
/// [SetListColorCodingScope] and/or forcing the OS high-contrast flag.
Future<void> _pumpWide(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool? colorCoding,
  bool highContrast = false,
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
        if (colorCoding != null) {
          tree = SetListColorCodingScope(
            notifier: ValueNotifier<bool>(colorCoding),
            child: tree,
          );
        }
        if (highContrast) {
          tree = MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: true),
            child: tree,
          );
        }
        return tree;
      },
      home: const ProgramsShell(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _seedProgram(CompendiumRepositories repos) async {
  await repos.dances.create(
    _dance(
      id: 'd1',
      title: 'Chase the Squirrel',
      shape: FormationShape.dupleImproper,
    ),
  );
  await repos.dances.create(
    _dance(id: 'd2', title: 'Big Circle', shape: FormationShape.sicilianCircle),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Barn Dance',
      status: ProgramStatus.draft,
      slots: [
        ProgramSlot(id: 's0', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's1', position: 1, danceId: 'd2'),
      ],
      createdAt: _now,
      updatedAt: _now,
    ),
  );
}

Color? _accentBorderColor(WidgetTester tester, String slotId) {
  final finder = find.byKey(ValueKey('summary-slot-$slotId-accent'));
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<Container>(finder);
  final border = (container.decoration as BoxDecoration?)?.border as Border?;
  return border?.left.color;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'set-list rows carry the formation-family accent when colour-coding is on',
    (tester) async {
      final repos = openTestRepositories();
      await _seedProgram(repos);
      await _pumpWide(tester, repos, colorCoding: true);
      await tester.tap(find.text('Barn Dance'));
      await tester.pumpAndSettle();

      // Both dance rows carry an accent keyed to their formation family, and
      // the colours differ because the two dances are in different families.
      final d1 = _accentBorderColor(tester, 's0');
      final d2 = _accentBorderColor(tester, 's1');
      expect(d1, isNotNull);
      expect(d2, isNotNull);
      expect(
        d1,
        setListAccentForShape(
          FormationShape.dupleImproper,
          highContrast: false,
        ),
      );
      expect(
        d2,
        setListAccentForShape(
          FormationShape.sicilianCircle,
          highContrast: false,
        ),
      );
      expect(d1, isNot(d2));
    },
  );

  testWidgets('disabling colour-coding removes the accent but keeps the '
      'formation text (row readable without colour)', (tester) async {
    final repos = openTestRepositories();
    await _seedProgram(repos);
    await _pumpWide(tester, repos, colorCoding: false);
    await tester.tap(find.text('Barn Dance'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('summary-slot-s0-accent')), findsNothing);
    expect(find.byKey(const ValueKey('summary-slot-s1-accent')), findsNothing);
    // Formation text is still shown, so the row's type/form is fully readable
    // without any colour.
    expect(find.textContaining('Duple improper'), findsOneWidget);
    expect(find.textContaining('Sicilian circle'), findsOneWidget);
  });

  testWidgets('semantics expose the formation as text (colour not required)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seedProgram(repos);
    await _pumpWide(tester, repos, colorCoding: true);
    await tester.tap(find.text('Barn Dance'));
    await tester.pumpAndSettle();

    // The row's accessible name includes both the title and the formation, so
    // a screen-reader user gets the type/form without relying on the accent.
    expect(
      find.bySemanticsLabel(RegExp(r'Chase the Squirrel\. Duple improper')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Big Circle\. Sicilian circle')),
      findsOneWidget,
    );
  });

  testWidgets('high-contrast uses the brighter high-contrast palette', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _seedProgram(repos);
    await _pumpWide(tester, repos, colorCoding: true, highContrast: true);
    await tester.tap(find.text('Barn Dance'));
    await tester.pumpAndSettle();

    final d1 = _accentBorderColor(tester, 's0');
    expect(d1, isNotNull);
    expect(
      d1,
      setListAccentForShape(FormationShape.dupleImproper, highContrast: true),
    );
    // And it is *not* the light-theme accent.
    expect(
      d1,
      isNot(
        setListAccentForShape(
          FormationShape.dupleImproper,
          highContrast: false,
        ),
      ),
    );
  });
}
