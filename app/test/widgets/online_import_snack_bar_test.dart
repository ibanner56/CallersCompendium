import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/import_io.dart';
import 'package:compendium_app/src/data/online_search.dart';
import 'package:compendium_app/src/widgets/online_import_snack_bar.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

// 2026-10 behaviour audit, INTAKE-5: a single-dance online import offers Undo
// on its snackbar, and that Undo is the exact revert every other import has.

final _stamp = DateTime.utc(2026, 1, 1);

Dance _dance({required String id, required String title, String? figure}) =>
    Dance(
      id: id,
      title: title,
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      figures: [customFigure(figure ?? 'neighbors balance and swing')],
      hook: '',
      createdAt: _stamp,
      updatedAt: _stamp,
    );

ImportRecordPlan _plan({String? linkTo}) => ImportRecordPlan(
  draft: StructuredDraft(
    dance: _dance(id: '', title: 'Money Musk', figure: 'actives swing'),
    raw: const RawRecord(
      source: ProvenanceSource.callersbox,
      externalId: '10600',
      payload: '{}',
    ),
  ),
  verdict: linkTo == null
      ? DedupeVerdict.isNew()
      : DedupeVerdict.ambiguous([
          DedupeCandidate(danceId: linkTo, score: 0.97, confident: true),
        ]),
);

Future<OnlineImportResult> _commit(
  CompendiumRepositories repos, {
  String? linkTo,
}) => commitPreviewedOnlinePlan(
  repos,
  _plan(linkTo: linkTo),
  now: _stamp,
  ambiguousResolution: linkTo == null ? null : DedupeResolution.link(linkTo),
  defaultTagIds: const [],
  importFailedReason: UrlFetchFailureReason.callersBoxImportFailed,
  debugLabel: 'test',
);

/// Pumps a scaffold and shows the snackbar for [result]; returns how many
/// times `onDanceRemoved` has run so far.
Future<int Function()> _show(
  WidgetTester tester,
  CompendiumRepositories repos,
  OnlineImportResult result,
) async {
  var removed = 0;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  final context = tester.element(find.byType(Scaffold));
  showOnlineImportSnackBar(
    ScaffoldMessenger.of(context),
    l10n: AppLocalizations.of(context),
    result: result,
    repos: repos,
    accessibleNavigation: false,
    onDanceRemoved: () => removed++,
  );
  await tester.pumpAndSettle();
  return () => removed;
}

/// Taps Undo and lets its database work finish: the repository runs on real
/// async I/O, which fake-async pumping alone does not advance.
Future<void> _tapUndo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('online-import-undo')));
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('Undo removes a new dance and says so to the caller', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final result = await tester.runAsync(() => _commit(repos));
    final danceId = result!.danceId!;

    final removed = await _show(tester, repos, result);
    expect(find.text('Imported "Money Musk".'), findsOneWidget);
    await _tapUndo(tester);
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => repos.dances.getById(danceId)), isNull);
    expect(removed(), 1);
  });

  testWidgets('Undo after "Same dance" puts your own version back', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final mine = _dance(id: 'mine', title: 'Money Musk (my notes)');
    final result = await tester.runAsync(() async {
      await repos.dances.create(mine);
      return _commit(repos, linkTo: 'mine');
    });
    expect(result!.danceId, 'mine');
    expect(
      (await tester.runAsync(() => repos.dances.getById('mine')))!.title,
      'Money Musk',
      reason: 'the link replaced it',
    );

    final removed = await _show(tester, repos, result);
    await _tapUndo(tester);
    await tester.pumpAndSettle();

    final restored = await tester.runAsync(() => repos.dances.getById('mine'));
    expect(restored!.title, 'Money Musk (my notes)');
    expect(removed(), 0, reason: 'the dance still exists');
  });

  testWidgets('Undo keeps a dance edited since the import, and says so', (
    tester,
  ) async {
    final repos = openTestRepositories();
    final result = await tester.runAsync(() => _commit(repos));
    final danceId = result!.danceId!;

    final removed = await _show(tester, repos, result);
    await tester.runAsync(() async {
      final dance = await repos.dances.getById(danceId);
      await repos.dances.update(
        dance!.copyWith(
          hook: 'my calling notes',
          updatedAt: dance.updatedAt.add(const Duration(minutes: 1)),
        ),
      );
    });
    await _tapUndo(tester);
    await tester.pumpAndSettle();

    final kept = await tester.runAsync(() => repos.dances.getById(danceId));
    expect(kept!.hook, 'my calling notes');
    expect(removed(), 0);
    expect(
      find.byKey(const ValueKey('online-import-undo-kept')),
      findsOneWidget,
    );
  });

  testWidgets('Undo keeps a new dance a program now uses', (tester) async {
    final repos = openTestRepositories();
    final result = await tester.runAsync(() => _commit(repos));
    final danceId = result!.danceId!;
    await tester.runAsync(
      () => repos.programs.create(
        Program(
          id: 'p1',
          title: 'Friday',
          slots: [ProgramSlot(id: 's1', position: 0, danceId: danceId)],
          createdAt: _stamp,
          updatedAt: _stamp,
        ),
      ),
    );

    final removed = await _show(tester, repos, result);
    await _tapUndo(tester);
    await tester.pumpAndSettle();

    expect(
      await tester.runAsync(() => repos.dances.getById(danceId)),
      isNotNull,
    );
    expect(removed(), 0);
  });

  testWidgets('a dance already in the collection gets no Undo', (tester) async {
    final repos = openTestRepositories();
    await _show(
      tester,
      repos,
      const OnlineImportResult(
        kind: OnlineImportKind.alreadyInCollection,
        title: 'Money Musk',
        danceId: 'mine',
      ),
    );

    expect(find.byKey(const ValueKey('online-import-snackbar')), findsOne);
    expect(find.byKey(const ValueKey('online-import-undo')), findsNothing);
  });
}
