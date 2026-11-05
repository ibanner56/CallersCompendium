import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../figures_support.dart';
import '../support/batch_screen_harness.dart';
import '../support/test_repositories.dart';

/// Counts the dance reads a batch handler makes, so a regression to one
/// `getById` per selected dance (N4-S4) is caught by count, not by timing.
class _ReadCountingDances extends DanceRepository {
  _ReadCountingDances(CompendiumDatabase db) : super(db, contraTaxonomy);

  int getByIdCalls = 0;
  int getByIdsCalls = 0;

  @override
  Future<Dance?> getById(
    String id, {
    bool includeDeleted = false,
    bool includeDeletedAuthors = false,
  }) {
    getByIdCalls++;
    return super.getById(
      id,
      includeDeleted: includeDeleted,
      includeDeletedAuthors: includeDeletedAuthors,
    );
  }

  @override
  Future<List<Dance>> getByIds(
    Iterable<String> ids, {
    bool includeDeleted = false,
  }) {
    getByIdsCalls++;
    return super.getByIds(ids, includeDeleted: includeDeleted);
  }
}

Dance _dance(String id, {List<String> tunes = const []}) => Dance(
  id: id,
  title: 'Dance $id',
  tunes: tunes,
  rating: 2,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

final _textDef = CustomFieldDef(
  id: 'f-text',
  key: 'origin',
  label: 'Origin',
  type: CustomFieldType.text,
);

Future<({CompendiumRepositories repos, _ReadCountingDances dances})>
_pumpWithThreeDances(WidgetTester tester) async {
  final db = openWidgetTestDatabase();
  final dances = _ReadCountingDances(db);
  final repos = CompendiumRepositories(db, contraTaxonomy, dances: dances);
  // ignore: unused_result
  await repos.customFieldDefs.upsert(_textDef);
  for (final id in ['d1', 'd2', 'd3']) {
    await repos.dances.create(_dance(id, tunes: ['Reel A']));
  }
  await pumpBatchScreen(tester, repos);
  await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-select')));
  await tester.pumpAndSettle();
  for (final id in ['d1', 'd2', 'd3']) {
    await tester.tap(find.byKey(ValueKey('batch-checkbox-$id')));
    await tester.pumpAndSettle();
  }
  dances
    ..getByIdCalls = 0
    ..getByIdsCalls = 0;
  return (repos: repos, dances: dances);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void _expectBatched(_ReadCountingDances dances) {
  expect(
    dances.getByIdCalls,
    0,
    reason: 'priors must come from one batched read, not a getById per dance',
  );
  expect(dances.getByIdsCalls, 1);
}

void main() {
  testWidgets('set level reads its priors in one batch', (tester) async {
    final t = await _pumpWithThreeDances(tester);
    await _tap(tester, 'batch-set-level');
    await _tap(tester, 'batch-level-option-intermediate');
    await _tap(tester, 'batch-level-confirm');
    _expectBatched(t.dances);
  });

  testWidgets('set rating reads its priors in one batch', (tester) async {
    final t = await _pumpWithThreeDances(tester);
    await _tap(tester, 'batch-more');
    await _tap(tester, 'batch-set-rating');
    await _tap(tester, 'batch-rating-option-4');
    await _tap(tester, 'batch-rating-confirm');
    _expectBatched(t.dances);
    expect((await t.repos.dances.getById('d2'))!.rating, 4);
  });

  testWidgets('add tunes reads its priors in one batch', (tester) async {
    final t = await _pumpWithThreeDances(tester);
    await _tap(tester, 'batch-more');
    await _tap(tester, 'batch-add-tunes');
    await tester.enterText(
      find.byKey(const ValueKey('batch-tunes-field')),
      'Jig B',
    );
    await _tap(tester, 'batch-tunes-add');
    await _tap(tester, 'batch-tunes-confirm');
    _expectBatched(t.dances);
    expect(tunesOf((await t.repos.dances.getById('d3'))!), ['Reel A', 'Jig B']);
  });

  testWidgets('clear tunes reads its priors in one batch', (tester) async {
    final t = await _pumpWithThreeDances(tester);
    await _tap(tester, 'batch-more');
    await _tap(tester, 'batch-clear-tunes');
    await _tap(tester, 'batch-clear-tunes-confirm-button');
    _expectBatched(t.dances);
    expect(tunesOf((await t.repos.dances.getById('d1'))!), isEmpty);
  });

  testWidgets('edit custom field reads its priors in one batch', (
    tester,
  ) async {
    final t = await _pumpWithThreeDances(tester);
    await _tap(tester, 'batch-more');
    await _tap(tester, 'batch-edit-custom-field');
    await tester.enterText(
      find.byKey(const ValueKey('batch-custom-field-value-f-text')),
      'New England',
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'batch-custom-field-confirm');
    _expectBatched(t.dances);
  });
}
