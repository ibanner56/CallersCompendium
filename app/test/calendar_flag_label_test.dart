import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/screens/programs_list_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2030, 1, 1);

Program _program(String flag) => Program(
  id: 'p1',
  title: 'Gig',
  calendarEventKey: calendarEventKey('a', ''),
  calendarFlag: flag,
  createdAt: _now,
  updatedAt: _now,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<CompendiumRepositories> pump(
    WidgetTester tester,
    String flag,
    Widget home,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.programs.create(_program(flag));
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: dialect, child: child!),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    return repos;
  }

  for (final (flag, text) in [
    (calendarFlagCancelled, 'Canceled in your calendar'),
    (calendarFlagMissing, 'No longer in your calendar'),
    ('postponed', 'Flagged by your calendar'),
  ]) {
    testWidgets('the Programs list row shows "$text" with an icon', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, flag, const ProgramsListScreen());
      final label = find.byKey(const ValueKey('calendar-flag-p1'));
      expect(label, findsOneWidget);
      expect(
        find.descendant(
          of: label,
          matching: find.byIcon(Icons.event_busy_outlined),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: label, matching: find.text(text)), findsOne);
      expect(find.bySemanticsLabel(text), findsOneWidget);
      semantics.dispose();
    });
  }

  testWidgets('the summary shows the flag, and Clear calendar flag removes it '
      'and nothing else', (tester) async {
    final semantics = tester.ensureSemantics();
    final repos = await pump(
      tester,
      calendarFlagCancelled,
      const ProgramSummaryScreen(programId: 'p1'),
    );
    expect(find.bySemanticsLabel('Canceled in your calendar'), findsOneWidget);
    expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-calendar-flag')));
    await tester.pumpAndSettle();
    final stored = (await repos.programs.getById('p1'))!;
    expect(stored.calendarFlag, isNull);
    expect(stored.title, 'Gig');
    expect(stored.calendarEventKey, calendarEventKey('a', ''));
    expect(find.byKey(const ValueKey('clear-calendar-flag')), findsNothing);
    semantics.dispose();
  });
}
