import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/custom_fields_screen.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Future<void> _pumpScreen(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (_, child) =>
          RepositoriesScope(repositories: repos, child: child!),
      home: const CustomFieldsScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the "New field" form from the screen.
Future<void> _openNewForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('add-field')));
  await tester.pumpAndSettle();
}

/// Opens the edit form for the field with the given label.
Future<void> _openEditForm(WidgetTester tester, String label) async {
  // Find the tile for the given label and tap its edit icon.
  final tileFinder = find.widgetWithText(ListTile, label);
  final editIcon = find.descendant(
    of: tileFinder,
    matching: find.byIcon(Icons.edit_outlined),
  );
  await tester.tap(editIcon.first);
  await tester.pumpAndSettle();
}

/// Fills the create/edit form and taps Save. Returns after the bottom sheet
/// closes.
Future<void> _fillAndSave(
  WidgetTester tester, {
  required String label,
  String? key,
  CustomFieldType type = CustomFieldType.text,
  List<String> choices = const [],
}) async {
  await tester.enterText(find.byKey(const ValueKey('cf-label')), label);
  if (key != null) {
    await tester.enterText(find.byKey(const ValueKey('cf-key')), key);
  }
  if (type != CustomFieldType.text) {
    await tester.tap(find.byKey(const ValueKey('cf-type')));
    await tester.pumpAndSettle();
    final typeLabel = switch (type) {
      CustomFieldType.text => 'Text',
      CustomFieldType.number => 'Number',
      CustomFieldType.boolean => 'Boolean',
      CustomFieldType.choice => 'Choice',
    };
    await tester.tap(find.text(typeLabel).last);
    await tester.pumpAndSettle();
  }
  for (final choice in choices) {
    await tester.enterText(find.byKey(const ValueKey('choice-input')), choice);
    await tester.tap(find.byKey(const ValueKey('add-choice')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('cf-form-save')));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('CustomFieldsScreen', () {
    testWidgets('shows empty state when no fields defined', (tester) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      expect(find.textContaining('No custom fields'), findsOneWidget);
    });

    testWidgets('lists existing field defs with label and type', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'difficulty',
          label: 'Difficulty',
          type: CustomFieldType.choice,
          choices: const ['easy', 'hard'],
          searchable: true,
          showInList: true,
        ),
      );
      await _pumpScreen(tester, repos);
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.textContaining('Choice'), findsOneWidget);
    });

    testWidgets('creates a text field and it appears in the list', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await _fillAndSave(tester, label: 'Notes', key: 'notes');
      expect(find.text('Notes'), findsOneWidget);
      // Also persisted in the repository.
      final saved = await repos.customFieldDefs.listAll();
      expect(saved, hasLength(1));
      expect(saved.first.label, 'Notes');
      expect(saved.first.type, CustomFieldType.text);
    });

    testWidgets('creates a choice field with choices', (tester) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await _fillAndSave(
        tester,
        label: 'Level',
        key: 'level',
        type: CustomFieldType.choice,
        choices: ['beginner', 'intermediate', 'advanced'],
      );
      expect(find.text('Level'), findsOneWidget);
      final saved = await repos.customFieldDefs.listAll();
      expect(saved.first.choices, ['beginner', 'intermediate', 'advanced']);
    });

    testWidgets('edits a field label without changing type or key', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      );
      await _pumpScreen(tester, repos);
      await _openEditForm(tester, 'Notes');
      // Clear label and type a new one.
      await tester.enterText(find.byKey(const ValueKey('cf-label')), 'Remarks');
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Remarks'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);
    });

    testWidgets('deletes an unused field after confirmation', (tester) async {
      final repos = openTestRepositories();
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      );
      await _pumpScreen(tester, repos);
      // Tap delete icon.
      await tester.tap(find.byKey(const ValueKey('delete-field-f1')));
      await tester.pumpAndSettle();
      // Confirm the dialog.
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsNothing);
      expect(await repos.customFieldDefs.listAll(), isEmpty);
    });

    testWidgets('cancels delete when user dismisses dialog', (tester) async {
      final repos = openTestRepositories();
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        ),
      );
      await _pumpScreen(tester, repos);
      await tester.tap(find.byKey(const ValueKey('delete-field-f1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsOneWidget);
    });

    testWidgets(
      'shows friendly snackbar when deleting a field in use on dances',
      (tester) async {
        final repos = openTestRepositories();
        final def = CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        );
        await repos.customFieldDefs.upsert(def);
        // Create a dance that uses this field.
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'Chase the Squirrel',
            customFields: [CustomFieldValue(fieldId: 'f1', value: 'some note')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await _pumpScreen(tester, repos);
        await tester.tap(find.byKey(const ValueKey('delete-field-f1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('delete-confirm')));
        await tester.pumpAndSettle();
        // Field must still be in the list (not deleted).
        expect(find.text('Notes'), findsOneWidget);
        // Friendly message surfaced via snackbar.
        expect(
          find.byKey(const ValueKey('delete-in-use-snackbar')),
          findsOneWidget,
        );
        expect(find.textContaining("Can't delete"), findsOneWidget);
      },
    );

    // ---- form validation ----

    testWidgets('form rejects an empty label', (tester) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      // Leave label blank, fill key.
      await tester.enterText(find.byKey(const ValueKey('cf-key')), 'k');
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Label is required'), findsOneWidget);
      // Bottom sheet should still be open (form not submitted).
      expect(find.byKey(const ValueKey('cf-form-save')), findsOneWidget);
    });

    testWidgets('form rejects an empty key', (tester) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await tester.enterText(find.byKey(const ValueKey('cf-label')), 'Label');
      // Clear key field (it starts empty).
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Key is required'), findsOneWidget);
    });

    testWidgets('form rejects a choice field with no choices', (tester) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await tester.enterText(find.byKey(const ValueKey('cf-label')), 'Level');
      await tester.enterText(find.byKey(const ValueKey('cf-key')), 'level');
      // Switch type to choice.
      await tester.tap(find.byKey(const ValueKey('cf-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choice').last);
      await tester.pumpAndSettle();
      // Don't add any choices.
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one choice'), findsOneWidget);
    });

    // ---- mutability guards ----

    testWidgets('key field is locked when field is in use', (tester) async {
      final repos = openTestRepositories();
      final def = CustomFieldDef(
        id: 'f1',
        key: 'notes',
        label: 'Notes',
        type: CustomFieldType.text,
      );
      await repos.customFieldDefs.upsert(def);
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Dance',
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'hi')],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await _pumpScreen(tester, repos);
      await _openEditForm(tester, 'Notes');
      // Key field should be disabled.
      final keyField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('cf-key')),
      );
      expect(keyField.enabled, isFalse);
    });

    testWidgets('type dropdown is disabled when field is in use', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final def = CustomFieldDef(
        id: 'f1',
        key: 'notes',
        label: 'Notes',
        type: CustomFieldType.text,
      );
      await repos.customFieldDefs.upsert(def);
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Dance',
          customFields: [CustomFieldValue(fieldId: 'f1', value: 'hi')],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await _pumpScreen(tester, repos);
      await _openEditForm(tester, 'Notes');
      // The type dropdown's onChanged should be null (disabled).
      final dropdown = tester.widget<DropdownButtonFormField<CustomFieldType>>(
        find.byKey(const ValueKey('cf-type')),
      );
      expect(dropdown.onChanged, isNull);
    });

    testWidgets(
      'blocking removal of a choice value that is in use shows snackbar',
      (tester) async {
        final repos = openTestRepositories();
        final def = CustomFieldDef(
          id: 'f1',
          key: 'level',
          label: 'Level',
          type: CustomFieldType.choice,
          choices: const ['easy', 'hard'],
        );
        await repos.customFieldDefs.upsert(def);
        // A dance uses the 'easy' choice.
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'Dance',
            customFields: [CustomFieldValue(fieldId: 'f1', value: 'easy')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await _pumpScreen(tester, repos);
        await _openEditForm(tester, 'Level');
        // Try to remove the 'easy' choice.
        await tester.tap(find.byKey(const ValueKey('remove-choice-easy')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('choice-in-use-snackbar')),
          findsOneWidget,
        );
        // 'easy' should still be in the list.
        expect(find.text('easy'), findsOneWidget);
      },
    );

    testWidgets('allows removing an unused choice', (tester) async {
      final repos = openTestRepositories();
      final def = CustomFieldDef(
        id: 'f1',
        key: 'level',
        label: 'Level',
        type: CustomFieldType.choice,
        choices: const ['easy', 'hard'],
      );
      await repos.customFieldDefs.upsert(def);
      await _pumpScreen(tester, repos);
      await _openEditForm(tester, 'Level');
      // Remove 'easy' (not in use).
      await tester.tap(find.byKey(const ValueKey('remove-choice-easy')));
      await tester.pumpAndSettle();
      expect(find.text('easy'), findsNothing);
      // Save and verify.
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      final saved = await repos.customFieldDefs.listAll();
      expect(saved.first.choices, ['hard']);
    });

    testWidgets('adds a new choice to an existing choice field', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'level',
          label: 'Level',
          type: CustomFieldType.choice,
          choices: const ['easy'],
        ),
      );
      await _pumpScreen(tester, repos);
      await _openEditForm(tester, 'Level');
      // Add a new choice.
      await tester.enterText(
        find.byKey(const ValueKey('choice-input')),
        'hard',
      );
      await tester.tap(find.byKey(const ValueKey('add-choice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      final saved = await repos.customFieldDefs.listAll();
      expect(saved.first.choices, containsAll(['easy', 'hard']));
    });

    testWidgets(
      'key and type are editable when field has no values on any dance',
      (tester) async {
        final repos = openTestRepositories();
        await repos.customFieldDefs.upsert(
          CustomFieldDef(
            id: 'f1',
            key: 'notes',
            label: 'Notes',
            type: CustomFieldType.text,
          ),
        );
        await _pumpScreen(tester, repos);
        await _openEditForm(tester, 'Notes');
        final keyField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('cf-key')),
        );
        expect(keyField.enabled, isNot(false));
        final dropdown = tester
            .widget<DropdownButtonFormField<CustomFieldType>>(
              find.byKey(const ValueKey('cf-type')),
            );
        expect(dropdown.onChanged, isNotNull);
      },
    );

    // ---- key validation pattern enforcement ----

    testWidgets('form rejects a key with invalid characters (spaces)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await tester.enterText(
        find.byKey(const ValueKey('cf-label')),
        'My Field',
      );
      await tester.enterText(find.byKey(const ValueKey('cf-key')), 'my field');
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      // Should show a validation error about the key format.
      expect(find.textContaining('letters'), findsOneWidget);
      expect(find.byKey(const ValueKey('cf-form-save')), findsOneWidget);
    });

    testWidgets('form rejects a key starting with a digit', (tester) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await tester.enterText(
        find.byKey(const ValueKey('cf-label')),
        'My Field',
      );
      await tester.enterText(find.byKey(const ValueKey('cf-key')), '1invalid');
      await tester.tap(find.byKey(const ValueKey('cf-form-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('letter or underscore'), findsOneWidget);
    });

    testWidgets('form accepts a valid key with letters, digits, underscores', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpScreen(tester, repos);
      await _openNewForm(tester);
      await _fillAndSave(tester, label: 'Score', key: 'score_2024');
      expect(find.text('Score'), findsOneWidget);
    });

    // ---- delete-snackbar pluralization ----

    testWidgets(
      'delete snackbar says "1 dance" (singular) when only one dance uses it',
      (tester) async {
        final repos = openTestRepositories();
        final def = CustomFieldDef(
          id: 'f1',
          key: 'notes',
          label: 'Notes',
          type: CustomFieldType.text,
        );
        await repos.customFieldDefs.upsert(def);
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'Dance',
            customFields: [CustomFieldValue(fieldId: 'f1', value: 'some note')],
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await _pumpScreen(tester, repos);
        await tester.tap(find.byKey(const ValueKey('delete-field-f1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('delete-confirm')));
        await tester.pumpAndSettle();
        // Snackbar must say "1 dance" not "1 dances".
        expect(find.textContaining('1 dance'), findsOneWidget);
        expect(find.textContaining('1 dances'), findsNothing);
      },
    );
  });
}
