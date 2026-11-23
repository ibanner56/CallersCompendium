// Show pay off (issue #2355): pay is hidden in the program editor and summary,
// and hiding it never clears or changes a program's stored pay.

import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/program_auto_commit_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/show_program_pay_scope.dart';
import 'package:compendium_app/src/editor/program_editor_draft_codec.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/program_summary_screen.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _created = DateTime.utc(2026, 1, 1);

Program _program({int? payMinorUnits = 5000, String? payCurrency = 'JPY'}) =>
    Program(
      id: 'p1',
      title: 'Night',
      payMinorUnits: payMinorUnits,
      payCurrency: payCurrency,
      createdAt: _created,
      updatedAt: _created,
    );

final _payField = find.byKey(const ValueKey('program-pay'));
final _title = find.byKey(const ValueKey('program-title'));

/// Pumps the program editor for `p1` with Show pay driven by [showPay].
Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos,
  ValueNotifier<bool> showPay, {
  bool autoCommit = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  final autoCommitNotifier = ValueNotifier<bool>(autoCommit);
  addTearDown(autoCommitNotifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: dialect,
          child: ProgramAutoCommitScope(
            notifier: autoCommitNotifier,
            child: ShowProgramPayScope(notifier: showPay, child: child!),
          ),
        ),
      ),
      home: ProgramEditorScreen(programId: 'p1', onSaved: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
  // Fire the post-frame draft-restore check and settle any dialog it opens.
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _expandMoreDetails(WidgetTester tester) async {
  final tile = tester.widget<ExpansionTile>(
    find.byKey(const ValueKey('program-more-details-tile')),
  );
  if (!tile.controller!.isExpanded) {
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('save-program')));
  await tester.pumpAndSettle();
}

ValueNotifier<bool> _showPay(bool value) {
  final notifier = ValueNotifier<bool>(value);
  addTearDown(notifier.dispose);
  return notifier;
}

void main() {
  group('program editor with Show pay off', () {
    testWidgets('More details has no Pay field; turning Show pay on shows it '
        'with the stored amount', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      final showPay = _showPay(false);
      await _pumpEditor(tester, repos, showPay);
      await _expandMoreDetails(tester);

      expect(_payField, findsNothing);
      expect(find.byKey(const ValueKey('program-pay-currency')), findsNothing);

      showPay.value = true;
      await tester.pumpAndSettle();
      expect(_payField, findsOneWidget);
      expect(tester.widget<TextFormField>(_payField).controller!.text, '5000');
    });

    testWidgets('saving an edited title keeps the stored pay exactly', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      await _pumpEditor(tester, repos, _showPay(false));

      await tester.enterText(_title, 'Renamed');
      await _save(tester);

      final saved = await repos.programs.getById('p1');
      expect(saved!.title, 'Renamed');
      expect(saved.payMinorUnits, 5000);
      expect(saved.payCurrency, 'JPY');
    });

    testWidgets('a save keeps pay that changed elsewhere while the editor was '
        'open, rather than the copy it loaded', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      await _pumpEditor(tester, repos, _showPay(false));

      // Another device's pay arrives (sync) while this editor is open.
      final stored = (await repos.programs.getById('p1'))!;
      await repos.programs.update(
        stored.copyWith(
          payMinorUnits: 7500,
          payCurrency: 'EUR',
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      await tester.enterText(_title, 'Renamed');
      await _save(tester);

      final saved = await repos.programs.getById('p1');
      expect(saved!.title, 'Renamed');
      expect(saved.payMinorUnits, 7500);
      expect(saved.payCurrency, 'EUR');
    });

    for (final typed in ['250', '250.00']) {
      testWidgets('after auto-saving pay typed as "$typed", hiding pay keeps '
          'the next auto-save from overwriting pay changed elsewhere', (
        tester,
      ) async {
        final repos = openTestRepositories();
        await repos.programs.create(
          _program(payMinorUnits: null, payCurrency: null),
        );
        final showPay = _showPay(true);
        await _pumpEditor(tester, repos, showPay, autoCommit: true);
        await _expandMoreDetails(tester);
        // The currency is left at the locale default, never picked.
        await tester.enterText(_payField, typed);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        final committed = (await repos.programs.getById('p1'))!;
        expect(
          (committed.payMinorUnits, committed.payCurrency),
          (25000, 'USD'),
        );

        showPay.value = false;
        await tester.pumpAndSettle();
        await repos.programs.update(
          committed.copyWith(
            payMinorUnits: 30000,
            payCurrency: 'EUR',
            updatedAt: DateTime.utc(2026, 1, 3),
          ),
        );
        await tester.enterText(_title, 'Renamed');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        final saved = (await repos.programs.getById('p1'))!;
        expect(saved.title, 'Renamed');
        expect((saved.payMinorUnits, saved.payCurrency), (30000, 'EUR'));
      });
    }

    testWidgets('a pay change typed before pay was hidden is still saved', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      final showPay = _showPay(true);
      await _pumpEditor(tester, repos, showPay);
      await _expandMoreDetails(tester);
      await tester.enterText(_payField, '6000');

      showPay.value = false;
      await tester.pumpAndSettle();
      expect(_payField, findsNothing);
      await _save(tester);

      final saved = await repos.programs.getById('p1');
      expect(saved!.payMinorUnits, 6000);
      expect(saved.payCurrency, 'JPY');
    });

    testWidgets('an amount that does not parse stays visible after hiding, '
        'so the save it blocks can be fixed and made', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      final showPay = _showPay(true);
      await _pumpEditor(tester, repos, showPay);
      await _expandMoreDetails(tester);
      await tester.enterText(_payField, 'lots');

      showPay.value = false;
      await tester.pumpAndSettle();
      expect(_payField, findsOneWidget);

      await tester.enterText(_payField, '6000');
      // Any other edit rebuilds the editor; the corrected field must not
      // vanish while the person is still on it.
      final hideAlternates = find.byKey(
        const ValueKey('program-hide-alternates'),
      );
      await tester.ensureVisible(hideAlternates);
      await tester.tap(hideAlternates);
      await tester.pumpAndSettle();
      expect(_payField, findsOneWidget, reason: 'it does not vanish mid-fix');
      await _save(tester);

      final saved = await repos.programs.getById('p1');
      expect(saved!.payMinorUnits, 6000);
    });
  });

  group('autosave draft with Show pay off', () {
    testWidgets('is written without pay, and restoring it keeps the pay as '
        'stored at restore time', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      await _pumpEditor(tester, repos, _showPay(false));

      await tester.enterText(_title, 'Renamed');
      await tester.pump(const Duration(milliseconds: 600));
      final draftKey = programEditorDraftKey('p1');
      final raw = await repos.settings.get(draftKey);
      expect(raw, isNotNull, reason: 'the autosave draft was written');
      final json = jsonDecode(raw as String) as Map<String, Object?>;
      expect(json.containsKey('payText'), isFalse);
      expect(json.containsKey('payCurrency'), isFalse);

      // Leave without saving, then pay changes elsewhere (sync).
      await tester.pumpWidget(const SizedBox());
      final stored = (await repos.programs.getById('p1'))!;
      await repos.programs.update(
        stored.copyWith(
          payMinorUnits: 7500,
          payCurrency: 'EUR',
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      await _pumpEditor(tester, repos, _showPay(false));
      await tester.tap(find.byKey(const ValueKey('program-draft-restore')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: _title, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Renamed',
      );
      await _save(tester);

      final saved = await repos.programs.getById('p1');
      expect(saved!.title, 'Renamed');
      expect(saved.payMinorUnits, 7500);
      expect(saved.payCurrency, 'EUR');
    });
  });

  group('program summary', () {
    Future<void> pumpSummary(
      WidgetTester tester,
      CompendiumRepositories repos,
      ValueNotifier<bool> showPay,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
      addTearDown(dialect.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => RepositoriesScope(
            repositories: repos,
            child: ActiveDialectScope(
              notifier: dialect,
              child: ShowProgramPayScope(notifier: showPay, child: child!),
            ),
          ),
          home: const ProgramSummaryScreen(programId: 'p1'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hides the pay line while Show pay is off, and shows it '
        'again when it is turned on', (tester) async {
      final repos = openTestRepositories();
      await repos.programs.create(_program());
      final showPay = _showPay(false);
      await pumpSummary(tester, repos, showPay);

      expect(find.textContaining('Pay:'), findsNothing);
      expect(find.byIcon(Icons.payments_outlined), findsNothing);

      showPay.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Pay: 5000 JPY'), findsOneWidget);
    });
  });
}
