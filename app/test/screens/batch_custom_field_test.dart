import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';
import '../support/batch_screen_harness.dart';

Dance _dance({
  required String id,
  required String title,
  List<CustomFieldValue> customFields = const [],
}) => Dance(
  id: id,
  title: title,
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: customFields,
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

final _numberDef = CustomFieldDef(
  id: 'f-num',
  key: 'number',
  label: 'Number',
  type: CustomFieldType.number,
);

Future<void> _enterSelectionMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('batch-select')));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String danceId) async {
  await tester.tap(find.byKey(ValueKey('batch-checkbox-$danceId')));
  await tester.pumpAndSettle();
}

Future<void> _openCustomFieldDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('batch-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('batch-edit-custom-field')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('upsert sets a text field value across the selection', (
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
    await _openCustomFieldDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('batch-custom-field-value-f-text')),
      'New England',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-confirm')));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.customFields, [
      CustomFieldValue(fieldId: 'f-text', value: 'New England'),
    ]);
    expect((await repos.dances.getById('d2'))!.customFields, [
      CustomFieldValue(fieldId: 'f-text', value: 'New England'),
    ]);
    expect(find.text('Updated field on 2 dances'), findsOneWidget);
  });

  testWidgets('upsert overwrites the key but leaves other keys untouched', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(_textDef);
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f-num',
        key: 'year',
        label: 'Year',
        type: CustomFieldType.number,
      ),
    );
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Alpha',
        customFields: [
          CustomFieldValue(fieldId: 'f-text', value: 'Old'),
          CustomFieldValue(fieldId: 'f-num', value: 1990),
        ],
      ),
    );
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openCustomFieldDialog(tester);
    // Two defs exist, so no field is auto-selected — choose "Origin" first.
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-key')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Origin').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('batch-custom-field-value-f-text')),
      'Updated',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-confirm')));
    await tester.pumpAndSettle();

    final fields = (await repos.dances.getById('d1'))!.customFields;
    expect(
      fields,
      containsAll([
        CustomFieldValue(fieldId: 'f-text', value: 'Updated'),
        CustomFieldValue(fieldId: 'f-num', value: 1990),
      ]),
    );
    expect(fields.length, 2);
  });

  testWidgets('non-finite number values cannot be submitted', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(_numberDef);
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openCustomFieldDialog(tester);
    final field = find.byKey(const ValueKey('batch-custom-field-value-f-num'));
    final confirm = find.byKey(const ValueKey('batch-custom-field-confirm'));
    for (final raw in ['1e400', '-1e400', 'Infinity', 'NaN']) {
      await tester.enterText(field, raw);
      await tester.pumpAndSettle();
      expect(find.text('Enter a number'), findsOneWidget, reason: raw);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    }
  });

  testWidgets('clearing a field removes only that key', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(_textDef);
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Alpha',
        customFields: [CustomFieldValue(fieldId: 'f-text', value: 'x')],
      ),
    );
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openCustomFieldDialog(tester);
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-confirm')));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.customFields, isEmpty);
    expect(find.text('Cleared field on 1 dance'), findsOneWidget);
  });

  testWidgets('undo restores the prior per-dance custom fields', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(_textDef);
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Alpha',
        customFields: [CustomFieldValue(fieldId: 'f-text', value: 'before')],
      ),
    );
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openCustomFieldDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('batch-custom-field-value-f-text')),
      'after',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-custom-field-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await repos.dances.getById('d1'))!.customFields, [
      CustomFieldValue(fieldId: 'f-text', value: 'before'),
    ]);
  });

  testWidgets('dialog shows an empty state when no custom fields exist', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await pumpBatchScreen(tester, repos);

    await _enterSelectionMode(tester);
    await _toggle(tester, 'd1');
    await _openCustomFieldDialog(tester);

    expect(find.text('No custom fields are defined yet.'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('batch-custom-field-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });
}
