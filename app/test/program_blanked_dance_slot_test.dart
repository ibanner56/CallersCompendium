import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';
import 'package:compendium_app/src/utils/slot_dance_title.dart';

import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// A slot whose dance another device permanently deleted (Q-6, decided by the
/// maintainer 2026-10-31).
///
/// The deleting device rewrites its own programs' slots, but this device added
/// the dance to a program before the blank arrived, so its slot still cites a
/// blanked tombstone: title "—", no content. Every slot surface used to show
/// that dash, marked "(deleted dance)"; each now shows "Deleted dance".
void main() {
  Future<CompendiumRepositories> seedBlankedSlot() async {
    final repos = openTestRepositories();
    await repos.dances.create(
      Dance(
        id: 'd1',
        title: 'Gone Dance',
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
        title: 'Barn Dance',
        status: ProgramStatus.draft,
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    // The peer's blank, as Device Sync writes it.
    final later = _now.add(const Duration(days: 1));
    await repos.dances.writeFromSync(
      Dance(
        id: 'd1',
        title: blankedRecordTitle,
        createdAt: _now,
        updatedAt: later,
        deletedAt: permanentlyDeletedAt,
      ),
    );
    final stored = await repos.dances.getById('d1', includeDeleted: true);
    expect(isPermanentlyDeleted(stored!.deletedAt), isTrue);
    expect(stored.title, blankedRecordTitle);
    return repos;
  }

  Future<AppLocalizations> pump(WidgetTester tester, Widget home) async {
    installFakeWakelock();
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repos = await seedBlankedSlot();
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
    return AppLocalizations.of(tester.element(find.byWidget(home)));
  }

  void expectPlaceholder(AppLocalizations l10n) {
    expect(find.text(l10n.programsBlankedDanceTitle), findsWidgets);
    expect(
      find.textContaining(blankedRecordTitle),
      findsNothing,
      reason: 'the blank\'s placeholder title must not reach the screen',
    );
  }

  testWidgets('the program summary shows "Deleted dance"', (tester) async {
    final l10n = await pump(
      tester,
      const ProgramSummaryScreen(programId: 'p1'),
    );
    expectPlaceholder(l10n);
  });

  testWidgets('the program builder shows "Deleted dance"', (tester) async {
    final l10n = await pump(
      tester,
      ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    );
    expectPlaceholder(l10n);
  });

  testWidgets('Perform shows "Deleted dance"', (tester) async {
    final l10n = await pump(
      tester,
      const ProgramSummaryScreen(programId: 'p1'),
    );
    await tester.tap(find.byKey(const ValueKey('summary-perform')));
    await tester.pumpAndSettle();
    expect(find.byType(PerformProgramScreen), findsOneWidget);
    expectPlaceholder(l10n);
  });

  group('slotDanceTitle', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });
    Dance dance({DateTime? deletedAt}) => Dance(
      id: 'd',
      title: 'Petronella',
      createdAt: _now,
      updatedAt: _now,
      deletedAt: deletedAt,
    );

    test('a live dance keeps its title, marked or not', () {
      expect(slotDanceTitle(l10n, dance()), 'Petronella');
      expect(slotDanceTitle(l10n, dance(), markDeleted: true), 'Petronella');
    });

    test('a dance in Recently deleted is marked only when asked', () {
      final trashed = dance(deletedAt: _now);
      expect(slotDanceTitle(l10n, trashed), 'Petronella');
      expect(
        slotDanceTitle(l10n, trashed, markDeleted: true),
        'Petronella ${l10n.programsDeletedDanceFallback}',
      );
    });

    test('a blanked dance is "Deleted dance", unmarked, in every view', () {
      final blank = dance(
        deletedAt: permanentlyDeletedAt,
      ).copyWith(title: blankedRecordTitle);
      expect(slotDanceTitle(l10n, blank), l10n.programsBlankedDanceTitle);
      expect(
        slotDanceTitle(l10n, blank, markDeleted: true),
        l10n.programsBlankedDanceTitle,
      );
    });

    // A retention sweep keeps the title of a dance a slot still cites, under
    // the same permanently-deleted mark.
    test('a swept dance that kept its title keeps showing it', () {
      final swept = dance(deletedAt: permanentlyDeletedAt);
      expect(slotDanceTitle(l10n, swept), 'Petronella');
      expect(
        slotDanceTitle(l10n, swept, markDeleted: true),
        'Petronella ${l10n.programsDeletedDanceFallback}',
      );
    });
  });
}
