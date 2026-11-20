import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/ecd_migration_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';
import 'figures_support.dart';

/// Settings → Convert English dances (ADR-006 §12.1 F5).

Dance _dance(
  String id, {
  DanceForm form = DanceForm.ecd,
  FormationShape shape = FormationShape.dupleProper,
  List<Figure>? figures,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Dance(
    id: id,
    title: id,
    form: form,
    formation: Formation(shape),
    figures:
        figures ??
        [
          Figure(move: 'circle', params: const {'direction': 'left'}),
        ],
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(WidgetTester tester, CompendiumRepositories repos) async {
  await tester.pumpWidget(
    RepositoriesScope(
      repositories: repos,
      child: const MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: EcdMigrationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the empty state when no English dance needs it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('contra', form: DanceForm.contra));
    await _pump(tester, repos);
    expect(find.byKey(const ValueKey('ecd-migration-empty')), findsOneWidget);
  });

  testWidgets('converts only the English dances left ticked', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('Alpha'));
    await repos.dances.create(_dance('Bravo'));
    await repos.dances.create(_dance('Contra', form: DanceForm.contra));
    await _pump(tester, repos);

    expect(find.byKey(const ValueKey('ecd-migration-dance-Alpha')), findsOne);
    expect(find.byKey(const ValueKey('ecd-migration-dance-Bravo')), findsOne);
    expect(
      find.byKey(const ValueKey('ecd-migration-dance-Contra')),
      findsNothing,
    );
    expect(find.text('1 move to convert\nEnglish formation'), findsNWidgets(2));

    // Untick Bravo: only Alpha is converted.
    await tester.tap(find.byKey(const ValueKey('ecd-migration-dance-Bravo')));
    await tester.pumpAndSettle();
    expect(find.text('Convert 1 dance'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ecd-migration-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ecd-migration-confirm')));
    await tester.pumpAndSettle();

    final alpha = (await repos.dances.getById('Alpha'))!;
    final bravo = (await repos.dances.getById('Bravo'))!;
    expect(figuresOf(alpha).single.move, 'ecd_circle');
    expect(alpha.formation.shape, FormationShape.dupleMinor);
    expect(figuresOf(bravo).single.move, 'circle');
    expect(bravo.formation.shape, FormationShape.dupleProper);
  });

  testWidgets('nothing ticked: the convert button is off', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('Alpha'));
    await _pump(tester, repos);
    await tester.tap(find.byKey(const ValueKey('ecd-migration-dance-Alpha')));
    await tester.pumpAndSettle();
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('ecd-migration-apply')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('cancelling the confirmation writes nothing', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('Alpha'));
    await _pump(tester, repos);
    await tester.tap(find.byKey(const ValueKey('ecd-migration-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      figuresOf((await repos.dances.getById('Alpha'))!).single.move,
      'circle',
    );
  });
}
