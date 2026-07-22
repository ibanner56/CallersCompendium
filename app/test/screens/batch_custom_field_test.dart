import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';

import '../support/test_repositories.dart';
import '../support/l10n_harness.dart';

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

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final themeNotifier = ValueNotifier<AppThemeSelection>(
    AppThemeSelection.system,
  );
  addTearDown(themeNotifier.dispose);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  addTearDown(customThemes.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: AppThemeScope(
          notifier: themeNotifier,
          child: CustomThemesScope(
            controller: customThemes,
            child: ActiveDialectScope(notifier: notifier, child: child!),
          ),
        ),
      ),
      home: const DanceListScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('upsert sets a text field value across the selection', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.customFieldDefs.upsert(_textDef);
    await repos.dances.create(_dance(id: 'd1', title: 'Alpha'));
    await repos.dances.create(_dance(id: 'd2', title: 'Bravo'));
    await _pumpScreen(tester, repos);

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
    await repos.customFieldDefs.upsert(_textDef);
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
    await _pumpScreen(tester, repos);

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

  testWidgets('clearing a field removes only that key', (tester) async {
    final repos = openTestRepositories();
    await repos.customFieldDefs.upsert(_textDef);
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Alpha',
        customFields: [CustomFieldValue(fieldId: 'f-text', value: 'x')],
      ),
    );
    await _pumpScreen(tester, repos);

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
    await repos.customFieldDefs.upsert(_textDef);
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Alpha',
        customFields: [CustomFieldValue(fieldId: 'f-text', value: 'before')],
      ),
    );
    await _pumpScreen(tester, repos);

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
    await _pumpScreen(tester, repos);

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
