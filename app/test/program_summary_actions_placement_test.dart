import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// UX6-2 / D-11 "(B) Actions to top bar": on the full-screen program summary
/// the top bar keeps the word "Program" and takes the record actions; the
/// program's own name keeps its line in the body. The wide master-detail pane
/// has no top bar and keeps its in-body action row (a separate maintainer
/// call).
void main() {
  const name = 'Barn Dance Evening';

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required Widget Function() home,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'A Dance',
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await repos.programs.create(
      Program(
        id: 'p1',
        title: name,
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(dialect.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(notifier: dialect, child: child!),
          ),
        ),
        home: home(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inAppBar(Finder f) =>
      find.descendant(of: find.byType(AppBar), matching: f);

  const iconKeys = [
    'program-export-menu',
    'mark-all-performed',
    'summary-duplicate',
    'summary-delete',
  ];

  // [width, textScale, expectsInlineIcons]: inline at 600 dp and up.
  for (final c in <(double, double, bool)>[
    (800, 1.0, true),
    (800, 2.0, true),
    (600, 2.0, true),
    (360, 1.0, false),
    (360, 2.0, false),
  ]) {
    testWidgets(
      'standalone summary at ${c.$1} dp, text x${c.$2}: record actions in the '
      'top bar, name in the body',
      (tester) async {
        await pump(
          tester,
          size: Size(c.$1, 900),
          textScale: c.$2,
          home: () => const ProgramSummaryScreen(programId: 'p1'),
        );
        final l10n = AppLocalizations.of(tester.element(find.byType(AppBar)));

        expect(inAppBar(find.text(l10n.programsSummaryTitle)), findsOneWidget);
        expect(inAppBar(find.text(name)), findsNothing);
        expect(find.text(name), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byKey(const ValueKey('program-export-menu')),
          ),
          findsOneWidget,
        );
        if (c.$3) {
          for (final k in iconKeys) {
            expect(
              inAppBar(find.byKey(ValueKey(k))),
              findsOneWidget,
              reason: k,
            );
          }
          expect(
            inAppBar(find.byTooltip(l10n.commonDuplicate)),
            findsOneWidget,
          );
          expect(inAppBar(find.byTooltip(l10n.commonDelete)), findsOneWidget);
          expect(
            inAppBar(find.byTooltip(l10n.programsMarkAllPerformedTooltip)),
            findsOneWidget,
          );
        } else {
          expect(
            inAppBar(find.byKey(const ValueKey('summary-actions-overflow'))),
            findsOneWidget,
          );
          expect(
            inAppBar(find.byKey(const ValueKey('summary-delete'))),
            findsNothing,
          );
        }
        // Perform stays the full-width body button.
        expect(
          inAppBar(find.byKey(const ValueKey('summary-perform'))),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('summary-perform')), findsOneWidget);
        // Nothing but the name sits in the body's title row.
        for (final k in iconKeys) {
          final body = find.byKey(ValueKey(k)).hitTestable();
          expect(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byKey(ValueKey(k)),
            ),
            findsNothing,
            reason: '$k must not stay in the body ($body)',
          );
        }
        expect(tester.takeException(), isNull, reason: 'no overflow');
      },
    );
  }

  testWidgets('the overflow menu reaches Duplicate and Delete from the top bar '
      'at 360 dp', (tester) async {
    await pump(
      tester,
      size: const Size(360, 800),
      textScale: 2.0,
      home: () => const ProgramSummaryScreen(programId: 'p1'),
    );
    await tester.tap(find.byKey(const ValueKey('summary-actions-overflow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('summary-duplicate')), findsOneWidget);
    expect(find.byKey(const ValueKey('summary-delete')), findsOneWidget);
    expect(find.byKey(const ValueKey('mark-all-performed')), findsOneWidget);
  });

  testWidgets('the wide master-detail pane (no top bar) keeps its in-body '
      'action row', (tester) async {
    await pump(
      tester,
      size: const Size(1000, 900),
      textScale: 1.0,
      home: () => Scaffold(
        body: ProgramSummaryPane(
          programId: 'p1',
          onOpenBuilder: () {},
          onDeleted: () {},
          onNavigateTo: (_) {},
        ),
      ),
    );
    expect(find.byType(AppBar), findsNothing);
    for (final k in [...iconKeys, 'summary-perform']) {
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byKey(ValueKey(k)),
        ),
        findsOneWidget,
        reason: k,
      );
    }
  });
}
