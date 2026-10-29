import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/batch_screen_harness.dart';
import '../figures_support.dart';
import '../support/test_repositories.dart';

Dance _dance({
  required String id,
  required String title,
  DanceLevel? level,
  int? rating,
  List<String> tunes = const [],
  List<CustomFieldValue> customFields = const [],
}) => Dance(
  id: id,
  title: title,
  level: level,
  rating: rating,
  tunes: tunes,
  customFields: customFields,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  hook: '',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Makes every UPDATE of a dance row fail (or, with [onlyId], that one's): the
/// same shape as a full disk or a locked database from the app's point of view.
Future<void> _failDanceUpdates(
  CompendiumRepositories repos, {
  String? onlyId,
}) => repos.db.customStatement(
  'CREATE TRIGGER fail_dance_update BEFORE UPDATE ON dances '
  '${onlyId == null ? '' : "WHEN NEW.id = '$onlyId' "}'
  "BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END",
);

Future<void> _enterSelectionMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('collection-more-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-select')));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String danceId) async {
  await tester.tap(find.byKey(ValueKey('batch-checkbox-$danceId')));
  await tester.pumpAndSettle();
}

Future<void> _openMore(WidgetTester tester, String itemKey) async {
  await tester.tap(find.byKey(const ValueKey('batch-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(itemKey)));
  await tester.pumpAndSettle();
}

Future<void> _setLevel(WidgetTester tester, String optionKey) async {
  await tester.tap(find.byKey(const ValueKey('batch-set-level')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('batch-level-option-$optionKey')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-level-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _setRating(WidgetTester tester, String optionKey) async {
  await _openMore(tester, 'batch-set-rating');
  await tester.tap(find.byKey(ValueKey('batch-rating-option-$optionKey')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-rating-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _addTune(WidgetTester tester, String tune) async {
  await _openMore(tester, 'batch-add-tunes');
  await tester.enterText(find.byKey(const ValueKey('batch-tunes-field')), tune);
  await tester.tap(find.byKey(const ValueKey('batch-tunes-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-tunes-confirm')));
  await tester.pumpAndSettle();
}

final _textDef = CustomFieldDef(
  id: 'f-text',
  key: 'origin',
  label: 'Origin',
  type: CustomFieldType.text,
);

final _otherDef = CustomFieldDef(
  id: 'f-other',
  key: 'other',
  label: 'Other',
  type: CustomFieldType.text,
);

final _choiceDef = CustomFieldDef(
  id: 'f-choice',
  key: 'mood',
  label: 'Mood',
  type: CustomFieldType.choice,
  choices: const ['Bouncy'],
);

const _applyError = 'Could not apply batch changes. Try again.';
const _undoFailed =
    'Couldn’t undo that. Please check the result and try again.';

void main() {
  group('a failed batch write is reported', () {
    testWidgets('level', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _failDanceUpdates(repos);

      await _setLevel(tester, 'advanced');

      expect(find.text(_applyError), findsOneWidget);
      expect((await repos.dances.getById('d1'))!.difficultyLevelId, isNull);
      // The selection stays open so the caller can retry.
      expect(find.byKey(const ValueKey('batch-more')), findsOneWidget);
    });

    testWidgets('rating', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _failDanceUpdates(repos);

      await _setRating(tester, '4');

      expect(find.text(_applyError), findsOneWidget);
      expect((await repos.dances.getById('d1'))!.rating, isNull);
      expect(find.byKey(const ValueKey('batch-more')), findsOneWidget);
    });

    testWidgets('add tunes', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _failDanceUpdates(repos);

      await _addTune(tester, 'Reel A');

      expect(find.text(_applyError), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-more')), findsOneWidget);
    });

    testWidgets('clear tunes', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(id: 'd1', title: 'Alpha', tunes: ['Reel A']),
      );
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _failDanceUpdates(repos);

      await _openMore(tester, 'batch-clear-tunes');
      await tester.tap(
        find.byKey(const ValueKey('batch-clear-tunes-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text(_applyError), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-more')), findsOneWidget);
    });

    testWidgets('custom field', (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(_textDef);
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _failDanceUpdates(repos);

      await _openMore(tester, 'batch-edit-custom-field');
      await tester.enterText(
        find.byKey(const ValueKey('batch-custom-field-value-f-text')),
        'Somewhere',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('batch-custom-field-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text(_applyError), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-more')), findsOneWidget);
    });
  });

  group('Undo is transactional and reports a failure', () {
    testWidgets('level: one dance failing puts none back, and says so', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(
        _dance(id: 'd1', title: 'Alpha', level: DanceLevel.beginner),
      );
      await repos.dances.create(
        _dance(id: 'd2', title: 'Bravo', level: DanceLevel.beginner),
      );
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _toggle(tester, 'd2');
      await _setLevel(tester, 'advanced');
      // Undo writes d1 first; d2's write then fails.
      await _failDanceUpdates(repos, onlyId: 'd2');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text(_undoFailed), findsOneWidget);
      // Neither dance is half-restored.
      expect(
        (await repos.dances.getById('d1'))!.difficultyLevelId,
        DifficultyLevel.advancedId,
      );
      expect(
        (await repos.dances.getById('d2'))!.difficultyLevelId,
        DifficultyLevel.advancedId,
      );
    });

    testWidgets('rating: one dance failing puts none back, and says so', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha', rating: 2));
      await repos.dances.create(_dance(id: 'd2', title: 'Bravo', rating: 2));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _toggle(tester, 'd2');
      await _setRating(tester, '5');
      await _failDanceUpdates(repos, onlyId: 'd2');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text(_undoFailed), findsOneWidget);
      expect((await repos.dances.getById('d1'))!.rating, 5);
      expect((await repos.dances.getById('d2'))!.rating, 5);
    });

    testWidgets('tunes: one dance failing puts none back, and says so', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _toggle(tester, 'd2');
      await _addTune(tester, 'Reel A');
      await _failDanceUpdates(repos, onlyId: 'd2');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text(_undoFailed), findsOneWidget);
      expect(tunesOf((await repos.dances.getById('d1'))!), ['Reel A']);
      expect(tunesOf((await repos.dances.getById('d2'))!), ['Reel A']);
    });

    testWidgets('custom field: one dance failing puts none back, and says so', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(_textDef);
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _toggle(tester, 'd2');
      await _openMore(tester, 'batch-edit-custom-field');
      await tester.enterText(
        find.byKey(const ValueKey('batch-custom-field-value-f-text')),
        'Somewhere',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('batch-custom-field-confirm')),
      );
      await tester.pumpAndSettle();
      await _failDanceUpdates(repos, onlyId: 'd2');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text(_undoFailed), findsOneWidget);
      final expected = [
        CustomFieldValue(fieldId: 'f-text', value: 'Somewhere'),
      ];
      expect((await repos.dances.getById('d1'))!.customFields, expected);
      expect((await repos.dances.getById('d2'))!.customFields, expected);
    });
  });

  testWidgets('custom-field Undo restores only the field it changed', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(_textDef);
    // ignore: unused_result
    await repos.customFieldDefs.upsert(_otherDef);
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Alpha',
        customFields: [
          CustomFieldValue(fieldId: 'f-text', value: 'before'),
          CustomFieldValue(fieldId: 'f-other', value: 'kept'),
        ],
      ),
    );
    await pumpBatchScreen(tester, repos);
    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openMore(tester, 'batch-edit-custom-field');
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Origin').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('batch-custom-field-value-f-text')),
      'after',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-confirm')));
    await tester.pumpAndSettle();

    // Something else changes the OTHER field before Undo is tapped (a hand
    // edit, or a value arriving by sync).
    final current = (await repos.dances.getById('d1'))!;
    await repos.dances.update(
      current.copyWith(
        customFields: [
          for (final f in current.customFields)
            if (f.fieldId == 'f-other')
              CustomFieldValue(fieldId: 'f-other', value: 'changed meanwhile')
            else
              f,
        ],
        updatedAt: DateTime.utc(2026, 2, 1),
      ),
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final fields = (await repos.dances.getById('d1'))!.customFields;
    expect(
      fields,
      unorderedEquals([
        CustomFieldValue(fieldId: 'f-text', value: 'before'),
        CustomFieldValue(fieldId: 'f-other', value: 'changed meanwhile'),
      ]),
    );
  });

  group('the batch dialog can add a choice option', () {
    testWidgets('saves it to the definition and applies it', (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(_choiceDef);
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _openMore(tester, 'batch-edit-custom-field');

      await tester.tap(
        find.byKey(const ValueKey('batch-custom-field-add-option-f-choice')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('add-option-input')),
        '  Mellow ',
      );
      await tester.tap(find.byKey(const ValueKey('add-option-confirm')));
      await tester.pumpAndSettle();

      // Saved at once, like the single-dance editor, and selected.
      final saved = (await repos.customFieldDefs.listAll()).single;
      expect(saved.choices, ['Bouncy', 'Mellow']);
      await tester.tap(
        find.byKey(const ValueKey('batch-custom-field-confirm')),
      );
      await tester.pumpAndSettle();
      expect((await repos.dances.getById('d1'))!.customFields, [
        CustomFieldValue(fieldId: 'f-choice', value: 'Mellow'),
      ]);
    });

    testWidgets('rejects a duplicate option inline', (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(_choiceDef);
      await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
      await pumpBatchScreen(tester, repos);
      await _enterSelectionMode(tester);
      await _toggle(tester, 'd1');
      await _openMore(tester, 'batch-edit-custom-field');

      await tester.tap(
        find.byKey(const ValueKey('batch-custom-field-add-option-f-choice')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('add-option-input')),
        'Bouncy',
      );
      await tester.tap(find.byKey(const ValueKey('add-option-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('add-option-input')), findsOneWidget);
      expect((await repos.customFieldDefs.listAll()).single.choices, [
        'Bouncy',
      ]);
    });
  });
}
