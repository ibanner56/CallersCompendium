import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/editor/editor_draft_codec.dart';
import 'package:compendium_app/src/editor/editor_snapshot.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/dance_editor/name_picker.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/figure_list_editor.dart';
import 'package:compendium_app/src/widgets/lingo_text_editing_controller.dart';
import 'package:compendium_app/src/widgets/section_header.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({
  required String id,
  String title = 'Original',
  List<Figure> figures = const [],
  List<String> authorIds = const [],
  List<DanceLink> links = const [],
  List<CustomFieldValue> customFields = const [],
  DanceLevel? level,
  bool mixedLevel = false,
  int? rating,
  PartialDate? composedOn,
}) => Dance(
  id: id,
  title: title,
  figures: figures,
  authorIds: authorIds,
  links: links,
  customFields: customFields,
  level: level,
  mixedLevel: mixedLevel,
  rating: rating,
  composedOn: composedOn,
  createdAt: _now,
  updatedAt: _now,
);

/// Pumps a trivial home that pushes the editor, so the editor's Save/pop flow
/// returns to a real route (mirroring how it is reached in the app).
Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  String? danceId,
  ThemeData? theme,
}) async {
  // Tall surface so the full editor form (which grew with the walkthrough
  // field, #370) lays out without the trailing controls falling beyond a
  // lazily-built ListView's cache extent, which makes `ensureVisible`
  // under-scroll the last element in widget tests.
  await tester.binding.setSurfaceSize(const Size(1200, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      theme: theme,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(notifier: notifier, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<String>(
                builder: (_) => DanceEditorScreen(danceId: danceId),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

/// Types [typed] into figure [index]'s move field and taps the [optionId]
/// suggestion, mirroring the keyboard-first move picker.
/// Expands the accordion editor for the figure at [index] (no-op if the editor
/// is already open). Figures render as collapsed summary rows at rest.
Future<void> _openFigure(WidgetTester tester, int index) async {
  if (find.byKey(ValueKey('figure-$index-move-input')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(ValueKey('figure-$index-summary')));
  await tester.pumpAndSettle();
}

/// Opens the ⋮ overflow menu for figure [index] and taps its [suffix] item
/// (e.g. 'delete', 'cut', 'move-up').
Future<void> _tapFigureMenuItem(
  WidgetTester tester,
  int index,
  String suffix,
) async {
  await tester.tap(find.byKey(ValueKey('figure-$index-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('figure-$index-$suffix')));
  await tester.pumpAndSettle();
}

Future<void> _selectMoveInEditor(
  WidgetTester tester,
  int index,
  String typed,
  String optionId,
) async {
  await _openFigure(tester, index);
  await tester.enterText(
    find.byKey(ValueKey('figure-$index-move-input')),
    typed,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('figure-$index-move-option-$optionId')));
  await tester.pumpAndSettle();
}

/// Expands the collapsible "More details" (Tier 2) section so its fields
/// (status, level, dates, tags, tunes, links, published sources, related
/// dances, custom fields) become visible and hittable. Idempotent: if the
/// section is already expanded, it does nothing (so calling it again — e.g.
/// via [addRelatedDance] — never toggles it closed).
Future<void> _expandMoreDetails(WidgetTester tester) async {
  if (find.byKey(const ValueKey('related-dance-add')).evaluate().isNotEmpty) {
    return;
  }
  final tile = find.byKey(const ValueKey('more-details-tile'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

/// Reads the value a dropdown's own [FormFieldState] is holding, which is what
/// the closed field displays.
///
/// Issue #775: these assertions used to read the value back out of a
/// value-encoded `ValueKey`, which only proved the parent passed that value
/// down. Going through the field's state proves the field is showing it.
T? _dropdownValue<T>(WidgetTester tester) => tester
    .state<FormFieldState<T>>(find.byType(DropdownButtonFormField<T>))
    .value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new dance: empty title blocks save', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(await repos.dances.listAll(), isEmpty);
  });

  testWidgets('new dance: save creates a dance', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'My New Dance',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dances = await repos.dances.listAll();
    expect(dances, hasLength(1));
    expect(dances.single.title, 'My New Dance');
    // Returned to the launching route.
    expect(find.byKey(const ValueKey('open-editor')), findsOneWidget);
  });

  testWidgets('edit existing: title round-trips', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      isNotNull,
    );
    expect(find.text('Original'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Renamed',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.title, 'Renamed');
    // createdAt preserved from the original.
    expect(saved.createdAt, _now);
  });

  testWidgets('walkthrough round-trips on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await tester.enterText(
      find.byKey(const ValueKey('walkthrough-field')),
      'A1: neighbours balance and swing.\nB1: circle left.',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(
      saved!.walkthrough,
      'A1: neighbours balance and swing.\nB1: circle left.',
    );
  });

  testWidgets('level and mixed level round-trip on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    // Pick a level from the dropdown.
    await tester.tap(find.byKey(const ValueKey('level-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intermediate').last);
    await tester.pumpAndSettle();

    // Toggle mixed level on.
    await tester.tap(find.byKey(const ValueKey('mixed-level-field')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.level, DanceLevel.intermediate);
    expect(saved.mixedLevel, isTrue);
  });

  testWidgets('mixer toggles on and round-trips on save (issue #732)', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    // The mixer checkbox sits under the formation dropdown, not behind the
    // More details expander.
    await tester.tap(find.byKey(const ValueKey('mixer-field')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.mixer, isTrue);
  });

  testWidgets('selecting Unspecified clears an existing level', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Original', level: DanceLevel.advanced),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    await tester.tap(find.byKey(const ValueKey('level-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unspecified').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.level, isNull);
  });

  testWidgets('rating: setting a star round-trips on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await tester.tap(find.byKey(const ValueKey('rating-star-4')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.rating, 4);
  });

  testWidgets('rating: tapping the selected star clears to unrated', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original', rating: 3));
    await _pumpEditor(tester, repos, danceId: 'd1');

    // Tapping the current top star (3) unsets the rating.
    await tester.tap(find.byKey(const ValueKey('rating-star-3')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.rating, isNull);
  });

  testWidgets('rating: clear button unsets an existing rating', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original', rating: 5));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await tester.tap(find.byKey(const ValueKey('rating-clear')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.rating, isNull);
  });

  testWidgets('rating: undo reverts a change; redo re-applies it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    // Set a rating (pushes an undo entry immediately).
    await tester.tap(find.byKey(const ValueKey('rating-star-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rating-clear')), findsOneWidget);

    // Undo → back to unrated (no clear button, no filled stars).
    await tester.tap(find.byKey(const ValueKey('undo-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rating-clear')), findsNothing);

    // Redo → rating restored.
    await tester.tap(find.byKey(const ValueKey('redo-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rating-clear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();
    final saved = await repos.dances.getById('d1');
    expect(saved!.rating, 2);
  });

  testWidgets('rating: stars and clear expose semantic labels', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original', rating: 3));
    await _pumpEditor(tester, repos, danceId: 'd1');

    final handle = tester.ensureSemantics();

    // Overall control exposes a semantic value reflecting the current rating.
    // (label 'Rating' + value '3 of 5 stars' → announced 'Rating, 3 of 5 stars'.)
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('rating-field')))
          .getSemanticsData()
          .value,
      '3 of 5 stars',
    );

    // Each star is an actionable control with a descriptive label.
    expect(find.bySemanticsLabel('Set rating to 4 of 5 stars'), findsOneWidget);

    // The clear action is labelled.
    expect(find.bySemanticsLabel('Clear rating'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('composed date: year-only round-trips on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    await tester.enterText(
      find.byKey(const ValueKey('composed-on-year')),
      '1989',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.composedOn, PartialDate(1989));
    expect(saved.composedOn!.precision, DatePrecision.year);
  });

  testWidgets('composed date: year+month round-trips on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    await tester.enterText(
      find.byKey(const ValueKey('composed-on-year')),
      '2004',
    );
    await tester.pumpAndSettle();

    // Month becomes selectable once a valid year is present.
    final monthField = find.byKey(const ValueKey('composed-on-month'));
    await tester.ensureVisible(monthField);
    await tester.tap(monthField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mar').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.composedOn, PartialDate(2004, 3));
    expect(saved.composedOn!.precision, DatePrecision.month);
  });

  testWidgets('composed date: changing year clears a now-invalid day', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    await tester.enterText(
      find.byKey(const ValueKey('composed-on-year')),
      '2004', // leap year
    );
    await tester.pumpAndSettle();

    // Pick February …
    await tester.ensureVisible(find.byKey(const ValueKey('composed-on-month')));
    await tester.tap(find.byKey(const ValueKey('composed-on-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feb').last);
    await tester.pumpAndSettle();
    // … and the 29th (valid in 2004).
    await tester.ensureVisible(find.byKey(const ValueKey('composed-on-day')));
    await tester.tap(find.byKey(const ValueKey('composed-on-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29').last);
    await tester.pumpAndSettle();

    // Switch to a non-leap year: Feb 29 is no longer valid. This must not throw
    // (the Day dropdown would otherwise get an initialValue absent from items).
    await tester.enterText(
      find.byKey(const ValueKey('composed-on-year')),
      '2005',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    // Day was cleared; year+month precision remains.
    expect(saved!.composedOn, PartialDate(2005, 2));
  });

  testWidgets('revised date loads and clearing the year clears it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Original', composedOn: PartialDate(1995, 6)),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    // The existing year is shown in the field.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('composed-on-year')))
          .controller!
          .text,
      '1995',
    );

    // Clearing the year clears the whole date.
    await tester.enterText(find.byKey(const ValueKey('composed-on-year')), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.composedOn, isNull);
  });

  testWidgets('invalid phrase structure blocks save', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'X');
    await tester.enterText(find.byKey(const ValueKey('phrase-field')), 'abc');
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    expect(find.textContaining('phrases*bars*beatsPerBar'), findsOneWidget);
    expect(await repos.dances.listAll(), isEmpty);
  });

  testWidgets('inline choreographer creation', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('author-input')),
      'Gene Hubert',
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('author-option-create:Gene Hubert')),
    );
    await tester.pumpAndSettle();

    // Choreographer persisted immediately on creation.
    final choreographers = await repos.choreographers.listAll();
    expect(choreographers.map((c) => c.name), contains('Gene Hubert'));

    // Chip shown, then save and confirm it is attached to the dance.
    expect(find.widgetWithText(InputChip, 'Gene Hubert'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'With Author',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.authorIds, hasLength(1));
    expect(dance.authorIds.single, choreographers.single.id);
  });

  testWidgets('author chip opens details dialog and saves shared edits', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.choreographers.upsert(
      Choreographer(id: 'c1', name: 'Gene Hubert'),
    );
    await _pumpEditor(tester, repos, danceId: null);

    // Add the existing author, then edit via the chip.
    await tester.enterText(find.byKey(const ValueKey('author-input')), 'Gene');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('author-option-c1')));
    await tester.pumpAndSettle();

    // The author chip is an editable InputChip; tapping its body opens the
    // dialog.
    expect(find.widgetWithText(InputChip, 'Gene Hubert'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('author-chip-c1')));
    await tester.pumpAndSettle();

    expect(find.text('Choreographer details'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('choreographer-name-field')),
      'Gene H.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('choreographer-email-field')),
      'gene@example.com',
    );
    await tester.tap(find.byKey(const ValueKey('choreographer-save')));
    await tester.pumpAndSettle();

    // Shared record persisted immediately (independent of dance save).
    final saved = await repos.choreographers.getById('c1');
    expect(saved!.name, 'Gene H.');
    expect(saved.email, 'gene@example.com');
    // Chip label reflects the renamed author.
    expect(find.widgetWithText(InputChip, 'Gene H.'), findsOneWidget);
  });

  testWidgets('tag chips are not editable (no details dialog)', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'flowy'));
    await _pumpEditor(tester, repos);

    await _expandMoreDetails(tester);

    await tester.enterText(find.byKey(const ValueKey('tag-input')), 'flowy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-t1')));
    await tester.pumpAndSettle();

    // Tag chips stay plain, non-tappable Chips — never InputChips.
    expect(find.widgetWithText(Chip, 'flowy'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'flowy'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-chip-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Choreographer details'), findsNothing);
  });

  testWidgets(
    'committing a tag clears the input, keeps focus, and supports back-to-back adds',
    (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't1', name: 'flowy'));
      // ignore: unused_result
      await repos.tags.upsert(Tag(id: 't2', name: 'smooth'));
      await _pumpEditor(tester, repos);

      await _expandMoreDetails(tester);

      TextField tagField() =>
          tester.widget<TextField>(find.byKey(const ValueKey('tag-input')));

      // First tag: type, pick the existing option.
      await tester.enterText(find.byKey(const ValueKey('tag-input')), 'flowy');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-option-t1')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'flowy'), findsOneWidget);
      // The typed text is cleared and focus stays in the field so the next tag
      // can be typed immediately (issue #402).
      expect(tagField().controller!.text, isEmpty);
      expect(tagField().focusNode!.hasFocus, isTrue);

      // Second tag added straight away from the now-empty field.
      await tester.enterText(find.byKey(const ValueKey('tag-input')), 'smooth');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-option-t2')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'flowy'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'smooth'), findsOneWidget);
      expect(tagField().controller!.text, isEmpty);
    },
  );

  testWidgets('creating a new tag inline clears the input', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await _expandMoreDetails(tester);

    await tester.enterText(find.byKey(const ValueKey('tag-input')), 'sparkly');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-create:sparkly')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'sparkly'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('tag-input')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('an empty tag entry does not add a chip or corrupt state', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.tags.upsert(Tag(id: 't1', name: 'flowy'));
    await _pumpEditor(tester, repos);

    await _expandMoreDetails(tester);

    // Whitespace-only input never opens options, so nothing can be committed.
    await tester.enterText(find.byKey(const ValueKey('tag-input')), '   ');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-option-t1')), findsNothing);
    expect(find.byKey(const ValueKey('tag-chip-t1')), findsNothing);

    // The field is still usable: a real tag can still be added afterwards.
    await tester.enterText(find.byKey(const ValueKey('tag-input')), 'flowy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-t1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'flowy'), findsOneWidget);
  });

  testWidgets(
    'disposing the picker mid-create does not touch the disposed controller',
    (tester) async {
      // Reproduces the async gap on the create path (#402 follow-up): onCreate
      // is a real Future, so if the editor is dismissed before it completes the
      // owned controller/focus node must not be used. Guarded by !mounted.
      final createCompleter = Completer<String>();
      var addCount = 0;

      Widget harness(bool showPicker) => MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: showPicker
              ? NamePicker(
                  fieldKey: 'tag',
                  selectedIds: const [],
                  namesById: const {},
                  options: const [],
                  onAdd: (_) => addCount++,
                  onRemove: (_) {},
                  onCreate: (_) => createCompleter.future,
                )
              : const SizedBox.shrink(),
        ),
      );

      await tester.pumpWidget(harness(true));
      await tester.enterText(
        find.byKey(const ValueKey('tag-input')),
        'sparkly',
      );
      await tester.pumpAndSettle();
      // Commit via the create option; onSelected now awaits onCreate.
      await tester.tap(find.byKey(const ValueKey('tag-option-create:sparkly')));
      await tester.pump();

      // Tear the picker down while the create is still in flight, then let the
      // future resolve. Without the !mounted guard this would throw
      // "A TextEditingController was used after being disposed."
      await tester.pumpWidget(harness(false));
      createCompleter.complete('t-new');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The guard short-circuits before onAdd/clear once disposed.
      expect(addCount, 0);
    },
  );

  testWidgets(
    'committing an author clears the shared picker input and keeps focus',
    (tester) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.choreographers.upsert(
        Choreographer(id: 'c1', name: 'Gene Hubert'),
      );
      await _pumpEditor(tester, repos, danceId: null);

      await tester.enterText(
        find.byKey(const ValueKey('author-input')),
        'Gene',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('author-option-c1')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, 'Gene Hubert'), findsOneWidget);
      // The shared NamePicker clears + keeps focus for authors too, so the
      // guarantee can't silently regress for one field but not the other.
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('author-input')),
      );
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('surfaces non-blocking phrase warnings', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 20}),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    expect(find.byKey(const ValueKey('warnings-card')), findsOneWidget);
    expect(find.textContaining('beats'), findsWidgets);
  });

  testWidgets('custom text field value round-trips', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'f1',
        key: 'extra',
        label: 'Extra',
        type: CustomFieldType.text,
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'CF');
    await _expandMoreDetails(tester);
    await tester.enterText(
      find.byKey(const ValueKey('custom-f1')),
      'hello world',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields, hasLength(1));
    expect(dance.customFields.single.fieldId, 'f1');
    expect(dance.customFields.single.value, 'hello world');
  });

  testWidgets('inline add-option on a choice field persists and selects it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'adj',
        key: 'adjectives',
        label: 'Adjectives',
        type: CustomFieldType.choice,
        choices: const ['driving'],
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'CF');
    await _expandMoreDetails(tester);

    // Open the inline "add option" dialog, enter a new adjective, confirm.
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-adj-add-option')),
    );
    await tester.tap(find.byKey(const ValueKey('custom-adj-add-option')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-option-input')),
      'lyrical',
    );
    await tester.tap(find.byKey(const ValueKey('add-option-confirm')));
    await tester.pumpAndSettle();

    // The option is persisted to the field definition immediately.
    final def = await repos.customFieldDefs.getById('adj');
    expect(def!.choices, ['driving', 'lyrical']);

    // Saving the dance keeps the newly-added option as the selected value.
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();
    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields.single.value, 'lyrical');
  });

  testWidgets('inline add-option rejects a duplicate without persisting', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'adj',
        key: 'adjectives',
        label: 'Adjectives',
        type: CustomFieldType.choice,
        choices: const ['driving'],
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'CF');
    await _expandMoreDetails(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-adj-add-option')),
    );
    await tester.tap(find.byKey(const ValueKey('custom-adj-add-option')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-option-input')),
      'driving',
    );
    await tester.tap(find.byKey(const ValueKey('add-option-confirm')));
    await tester.pumpAndSettle();

    // Duplicate is reported inline; the dialog stays open and nothing is added.
    expect(find.text('That option already exists.'), findsOneWidget);
    final def = await repos.customFieldDefs.getById('adj');
    expect(def!.choices, ['driving']);
  });

  testWidgets('untouched boolean custom field is not persisted', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'b1',
        key: 'flag',
        label: 'Flag',
        type: CustomFieldType.boolean,
      ),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'B');
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    // The switch was never toggled: no spurious `false` value is written.
    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields, isEmpty);
  });

  testWidgets('toggled boolean custom field round-trips', (tester) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.customFieldDefs.upsert(
      CustomFieldDef(
        id: 'b1',
        key: 'flag',
        label: 'Flag',
        type: CustomFieldType.boolean,
      ),
    );
    await _pumpEditor(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'B');
    await _expandMoreDetails(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('custom-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-b1')));
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.customFields, hasLength(1));
    expect(dance.customFields.single.value, true);
  });

  testWidgets('relatedDance link: edit round-trip via the editor', (
    tester,
  ) async {
    // PR3: relatedDance links are now first-class editable, not read-only.
    final repos = openTestRepositories();
    // FK target for the relatedDance link.
    await repos.dances.create(_dance(id: 'd2', title: 'Target'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Has related',
        links: [
          DanceLink(id: 'l1', kind: LinkKind.relatedDance, targetDanceId: 'd2'),
          DanceLink(
            id: 'l2',
            kind: LinkKind.source,
            url: 'https://example.com',
          ),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Has related (edited)',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    final kinds = saved!.links.map((l) => l.kind).toList();
    // Both links survive the round-trip.
    expect(kinds, containsAll([LinkKind.relatedDance, LinkKind.source]));
    final related = saved.links.firstWhere(
      (l) => l.kind == LinkKind.relatedDance,
    );
    expect(related.targetDanceId, 'd2');
  });

  testWidgets('autocomplete options are keyed by id, not display name', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // ignore: unused_result
    await repos.choreographers.upsert(Choreographer(id: 'c1', name: 'Chris'));
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('author-input')), 'Chris');
    await tester.pumpAndSettle();

    // Existing options are keyed by id so two same-named entities (dedup is
    // deferred) can't produce a duplicate-key crash in the options list.
    expect(find.byKey(const ValueKey('author-option-c1')), findsOneWidget);
  });

  testWidgets('Collection New dance FAB opens the editor', (tester) async {
    final repos = openTestRepositories();
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        builder: (context, child) => RepositoriesScope(
          repositories: repos,
          child: ActiveDialectScope(notifier: notifier, child: child!),
        ),
        home: const DanceListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('new-dance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-dance')));
    await tester.pumpAndSettle();

    expect(find.text('New dance'), findsWidgets);
    expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
  });

  testWidgets('adding a figure via type-ahead persists on save', (
    tester,
  ) async {
    final repos = openTestRepositories();
    // Start from a blank figure list so figure-add yields figure 0 (this test
    // predates the DD.2 stand_still × 8 default template).
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures([]),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'Swung');
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await _selectMoveInEditor(tester, 0, 'sw', 'swing');

    // Progression + note round-trip alongside the params.
    await tester.tap(find.byKey(const ValueKey('figure-0-progression')));
    await tester.pumpAndSettle();
    // The note field is on-demand — reveal it before typing.
    await tester.tap(find.byKey(const ValueKey('figure-0-add-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-note')),
      'big swing',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.figures, hasLength(1));
    final figure = dance.figures.single;
    expect(figure.move, 'swing');
    expect(figure.params['who'], 'partners');
    expect(figure.params['beats'], 8);
    expect(figure.progression, isTrue);
    expect(figure.note, 'big swing');
  });

  testWidgets('a custom figure persists on save', (tester) async {
    final repos = openTestRepositories();
    // Start from a blank figure list so figure-add yields figure 0 (this test
    // predates the DD.2 stand_still × 8 default template).
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures([]),
    );
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'Custom');
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('figure-0-move-input')),
      'scoop them up',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.figures.single.isCustom, isTrue);
    expect(dance.figures.single.params['text'], 'scoop them up');
  });

  testWidgets('editing an existing figure round-trips', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    // The existing figure loads as a collapsed summary; open it to edit.
    await _openFigure(tester, 0);
    expect(find.byKey(const ValueKey('figure-0-beats')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.figures.single.params['beats'], 16);
  });

  testWidgets('deleting a figure removes it on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        figures: [
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
          Figure(move: 'balance', params: {'who': 'neighbors', 'beats': 4}),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _tapFigureMenuItem(tester, 0, 'delete');
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.figures, hasLength(1));
    expect(saved.figures.single.move, 'balance');
  });

  // ── Related dances subsection ─────────────────────────────────────────────

  /// Finds the related-dance picker TextField by its unique labelText.
  Finder pickerField() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Related dance',
  );

  /// Expands "More details" and adds a blank related-dance row.
  Future<void> addRelatedDance(WidgetTester tester) async {
    await _expandMoreDetails(tester);
    final addButton = find.byKey(const ValueKey('related-dance-add'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
  }

  testWidgets('relatedDance: create via picker and save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target', title: 'Target Dance'));
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'With Related',
    );

    // Add a related-dance row in the dedicated subsection.
    await addRelatedDance(tester);

    // Type in the picker to search, then tap the matching option.
    await tester.enterText(pickerField().first, 'Target');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link-dance-option-target')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    // The created dance (not 'target') should have 1 relatedDance link.
    final all = await repos.dances.listAll();
    final created = all.firstWhere((d) => d.id != 'target');
    expect(created.links, hasLength(1));
    expect(created.links.single.kind, LinkKind.relatedDance);
    expect(created.links.single.targetDanceId, 'target');
  });

  testWidgets('relatedDance: note round-trips as the link label', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target', title: 'Target Dance'));
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'With Noted Relation',
    );

    await addRelatedDance(tester);
    await tester.enterText(pickerField().first, 'Target');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link-dance-option-target')));
    await tester.pumpAndSettle();

    // Add a note; it is stored on the DanceLink label.
    final noteField = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          (w.key as ValueKey).value.toString().startsWith(
            'related-dance-note-',
          ),
    );
    await tester.enterText(noteField.first, 'same author');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final all = await repos.dances.listAll();
    final created = all.firstWhere((d) => d.id != 'target');
    expect(created.links.single.kind, LinkKind.relatedDance);
    expect(created.links.single.targetDanceId, 'target');
    expect(created.links.single.label, 'same author');
  });

  testWidgets(
    'relatedDance: a loaded link surfaces in the related-dances editor '
    '(note pre-filled) and never leaks into the generic links list',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'target', title: 'Target Dance'));
      // A dance that already has BOTH a relatedDance link (with a note) and a
      // generic source link, exactly like data written before the editor reorg
      // (PR #108) that split related dances into their own subsection.
      await repos.dances.create(
        _dance(
          id: 'd1',
          title: 'Has related',
          links: [
            DanceLink(
              id: 'l1',
              kind: LinkKind.relatedDance,
              targetDanceId: 'target',
              label: 'kindred spirit',
            ),
            DanceLink(
              id: 'l2',
              kind: LinkKind.source,
              url: 'https://example.com',
              label: 'the source',
            ),
          ],
        ),
      );
      await _pumpEditor(tester, repos, danceId: 'd1');
      await _expandMoreDetails(tester);

      // The pre-existing relatedDance link surfaces in the dedicated editor
      // with its note pre-filled from the link label.
      final noteField = find.byKey(const ValueKey('related-dance-note-l1'));
      expect(noteField, findsOneWidget);
      expect(
        tester.widget<TextField>(noteField).controller?.text,
        'kindred spirit',
      );

      // The relatedDance link must NOT appear in the generic links editor…
      expect(find.byKey(const ValueKey('link-kind-l1')), findsNothing);
      expect(find.byKey(const ValueKey('link-url-l1')), findsNothing);
      // …while the genuine source link still does.
      expect(find.byKey(const ValueKey('link-url-l2')), findsOneWidget);

      // Saving without touching the links strands neither link.
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      final related = saved!.links.firstWhere(
        (l) => l.kind == LinkKind.relatedDance,
      );
      expect(related.targetDanceId, 'target');
      expect(related.label, 'kindred spirit');
      final source = saved.links.firstWhere((l) => l.kind == LinkKind.source);
      expect(source.url, 'https://example.com');
    },
  );

  testWidgets('relatedDance: remove removes it on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target', title: 'Target'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'target',
          ),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    // Remove the related dance.
    final removeButton = find.byKey(const ValueKey('related-dance-remove-l1'));
    await tester.ensureVisible(removeButton);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'No relations',
    );
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.links, isEmpty);
  });

  testWidgets('relatedDance: picker excludes the dance being edited', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Self Dance'));
    await repos.dances.create(_dance(id: 'd2', title: 'Other Dance'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await addRelatedDance(tester);

    // Type to show options.
    await tester.enterText(pickerField().first, 'Dance');
    await tester.pumpAndSettle();

    // 'Self Dance' (d1) must NOT appear — it is the dance being edited.
    expect(find.byKey(const ValueKey('link-dance-option-d1')), findsNothing);
    // 'Other Dance' (d2) SHOULD appear.
    expect(find.byKey(const ValueKey('link-dance-option-d2')), findsOneWidget);
  });

  testWidgets('relatedDance: picker excludes soft-deleted dances', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'live', title: 'Live Dance'));
    await repos.dances.create(_dance(id: 'gone', title: 'Gone Dance'));
    await repos.dances.softDelete('gone', at: DateTime.now().toUtc());
    await _pumpEditor(tester, repos);

    await addRelatedDance(tester);

    await tester.enterText(pickerField().first, 'Dance');
    await tester.pumpAndSettle();

    // Live Dance is in the picker; Gone Dance is soft-deleted and excluded.
    expect(
      find.byKey(const ValueKey('link-dance-option-live')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('link-dance-option-gone')), findsNothing);
  });

  testWidgets(
    'relatedDance: soft-deleted target shows "(missing dance)" in picker',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'gone-target', title: 'Was Here'));
      await repos.dances.create(
        _dance(
          id: 'd1',
          links: [
            DanceLink(
              id: 'l1',
              kind: LinkKind.relatedDance,
              targetDanceId: 'gone-target',
            ),
          ],
        ),
      );
      // Soft-delete the target so it is absent from _danceNamesById on load.
      await repos.dances.softDelete('gone-target', at: DateTime.now().toUtc());
      await _pumpEditor(tester, repos, danceId: 'd1');

      await _expandMoreDetails(tester);

      // Picker shows placeholder because target is soft-deleted (not in listAll).
      expect(find.text('(missing dance)'), findsOneWidget);
    },
  );

  testWidgets('relatedDance: undo of removal restores the relatedDance link', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'target', title: 'Target'));
    await repos.dances.create(
      _dance(
        id: 'd1',
        links: [
          DanceLink(
            id: 'l1',
            kind: LinkKind.relatedDance,
            targetDanceId: 'target',
          ),
        ],
      ),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    // The remove button is present.
    expect(
      find.byKey(const ValueKey('related-dance-remove-l1')),
      findsOneWidget,
    );

    // Remove the related dance — triggers an immediate undo snapshot push.
    await tester.tap(find.byKey(const ValueKey('related-dance-remove-l1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('related-dance-remove-l1')), findsNothing);

    // Undo — the related dance is restored.
    await tester.tap(find.byKey(const ValueKey('undo-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('related-dance-remove-l1')),
      findsOneWidget,
    );

    // Save and confirm the relatedDance link is persisted.
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final saved = await repos.dances.getById('d1');
    expect(saved!.links, hasLength(1));
    expect(saved.links.single.kind, LinkKind.relatedDance);
    expect(saved.links.single.targetDanceId, 'target');
  });

  testWidgets('URL kinds still work after PR3 changes', (tester) async {
    final repos = openTestRepositories();
    await _pumpEditor(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'URL Test',
    );
    await _expandMoreDetails(tester);
    await tester.tap(find.byKey(const ValueKey('link-add')));
    await tester.pumpAndSettle();

    // Default kind is 'source' — URL field is visible.
    final urlField = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          (w.key as ValueKey).value.toString().startsWith('link-url-'),
    );
    await tester.enterText(urlField.first, 'https://example.com');
    await tester.tap(find.byKey(const ValueKey('save-dance')));
    await tester.pumpAndSettle();

    final dance = (await repos.dances.listAll()).single;
    expect(dance.links, hasLength(1));
    expect(dance.links.single.kind, LinkKind.source);
    expect(dance.links.single.url, 'https://example.com');
  });

  group('source citations —', () {
    Future<void> attachExisting(
      WidgetTester tester,
      String query,
      String sourceId,
    ) async {
      await _expandMoreDetails(tester);
      final input = find.byKey(const ValueKey('source-input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, query);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('source-option-$sourceId')));
      await tester.pumpAndSettle();
    }

    testWidgets('attach an existing source persists on save', (tester) async {
      final repos = openTestRepositories();
      await repos.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Zesty Contras', author: 'Jennings'),
      );
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      await attachExisting(tester, 'Zesty', 's1');
      expect(find.byKey(const ValueKey('source-chip-s1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      expect(saved!.sourceCitations, hasLength(1));
      expect(saved.sourceCitations.single.sourceId, 's1');
    });

    testWidgets('edit page and number round-trips on save', (tester) async {
      final repos = openTestRepositories();
      await repos.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Zesty Contras'),
      );
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      await attachExisting(tester, 'Zesty', 's1');

      await tester.enterText(
        find.byKey(const ValueKey('source-page-s1')),
        '12-14',
      );
      await tester.enterText(
        find.byKey(const ValueKey('source-number-s1')),
        'A1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      final citation = saved!.sourceCitations.single;
      expect(citation.sourceId, 's1');
      expect(citation.page, '12-14');
      expect(citation.number, 'A1');
    });

    testWidgets('remove a citation drops it on save', (tester) async {
      final repos = openTestRepositories();
      await repos.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Zesty Contras'),
      );
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      await attachExisting(tester, 'Zesty', 's1');
      final chip = find.byKey(const ValueKey('source-chip-s1'));
      expect(chip, findsOneWidget);

      // The InputChip's delete affordance removes the citation.
      await tester.tap(
        find.descendant(of: chip, matching: find.byType(Icon)).last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-chip-s1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      expect(saved!.sourceCitations, isEmpty);
    });

    testWidgets('create a new source inline via the details dialog', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      await _expandMoreDetails(tester);

      final input = find.byKey(const ValueKey('source-input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Shadrach');
      await tester.pumpAndSettle();
      // The "create" option is offered when no exact title match exists.
      await tester.tap(
        find.byKey(const ValueKey('source-option-create:Shadrach')),
      );
      await tester.pumpAndSettle();

      // The details dialog opens prefilled with the typed title.
      expect(find.byKey(const ValueKey('source-title-field')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('source-author-field')),
        'Carol Ormand',
      );
      await tester.tap(find.byKey(const ValueKey('source-save')));
      await tester.pumpAndSettle();

      // A new source was persisted and a citation chip added.
      final sources = await repos.publishedSources.listAll();
      expect(sources, hasLength(1));
      expect(sources.single.title, 'Shadrach');
      expect(sources.single.author, 'Carol Ormand');

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      expect(saved!.sourceCitations, hasLength(1));
      expect(saved.sourceCitations.single.sourceId, sources.single.id);
    });

    testWidgets('editing a source clears a nullable field to null', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.publishedSources.upsert(
        PublishedSource(id: 's1', title: 'Zesty Contras', author: 'Jennings'),
      );
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      await attachExisting(tester, 'Zesty', 's1');

      // Open the shared-source details dialog from the chip.
      await tester.tap(find.byKey(const ValueKey('source-chip-s1')));
      await tester.pumpAndSettle();
      // Clear the author field.
      await tester.enterText(
        find.byKey(const ValueKey('source-author-field')),
        '',
      );
      await tester.tap(find.byKey(const ValueKey('source-save')));
      await tester.pumpAndSettle();

      final updated = await repos.publishedSources.getById('s1');
      expect(updated!.author, isNull);
    });
  });

  group('two-tier layout —', () {
    testWidgets('Progression and Rating share a row in Tier 1', (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      // Both are visible without expanding "More details" (they are Tier 1).
      expect(find.text('Progression'), findsOneWidget);
      expect(find.byKey(const ValueKey('rating-field')), findsOneWidget);

      // They sit on the same horizontal line (share a Row).
      final progressionField = find.byKey(const ValueKey('progression-field'));
      final progressionY = tester.getTopLeft(progressionField).dy;
      final ratingY = tester
          .getTopLeft(find.byKey(const ValueKey('rating-field')))
          .dy;
      expect((progressionY - ratingY).abs(), lessThan(24));
    });

    testWidgets('More details is collapsed by default and expands on tap', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      // Collapsed: a Tier-2 field (Status dropdown / mixed-level) is not shown.
      expect(find.byKey(const ValueKey('mixed-level-field')), findsNothing);
      expect(find.text('More details'), findsOneWidget);

      // The collapsed header renders its leading "additional details" icon so
      // it reads as a distinct, tappable section header.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('more-details-tile')),
          matching: find.byIcon(Icons.tune),
        ),
        findsOneWidget,
      );

      // Expand → Tier-2 fields become visible.
      await _expandMoreDetails(tester);
      expect(find.byKey(const ValueKey('mixed-level-field')), findsOneWidget);
    });

    testWidgets(
      'Form control is absent from the UI but a loaded form round-trips',
      (tester) async {
        final repos = openTestRepositories();
        // Persist a dance whose form is not the default (contra).
        await repos.dances.create(
          Dance(
            id: 'd1',
            title: 'ECD Dance',
            form: DanceForm.ecd,
            createdAt: _now,
            updatedAt: _now,
          ),
        );
        await _pumpEditor(tester, repos, danceId: 'd1');
        await _expandMoreDetails(tester);

        // No "Form" field is rendered anywhere in the editor.
        final formField = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('form-field-'),
        );
        expect(formField, findsNothing);
        expect(find.text('Form'), findsNothing);

        // Editing an unrelated field and saving preserves the form value.
        await tester.enterText(
          find.byKey(const ValueKey('title-field')),
          'ECD Dance (edited)',
        );
        await tester.tap(find.byKey(const ValueKey('save-dance')));
        await tester.pumpAndSettle();

        final saved = await repos.dances.getById('d1');
        expect(saved!.title, 'ECD Dance (edited)');
        expect(saved.form, DanceForm.ecd);
      },
    );
  });

  group('sectioned layout —', () {
    testWidgets('editor groups the body under shared SectionHeaders', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'Original'));
      await _pumpEditor(tester, repos, danceId: 'd1');

      // The body is grouped into distinct, labelled sections rendered by the
      // shared SectionHeader (the same widget Settings uses).
      expect(find.widgetWithText(SectionHeader, 'Details'), findsOneWidget);
      expect(find.widgetWithText(SectionHeader, 'Figures'), findsOneWidget);
      expect(find.widgetWithText(SectionHeader, 'Notes'), findsOneWidget);

      // Sectioning preserved the pre-existing fields (Tier-1 metadata, the
      // figures editor, and the collapsible "More details" drawer).
      expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
      expect(find.text('Authors'), findsOneWidget);
      expect(find.text('Formation'), findsOneWidget);
      expect(find.byType(FigureListEditor), findsOneWidget);
      expect(find.text('More details'), findsOneWidget);
    });
  });

  group('DD.1 new-dance metadata defaults', () {
    testWidgets('new dance seeds form/formation/progression/phrase from '
        'saved defaults', (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(kDefaultDanceFormKey, DanceForm.square.name);
      await repos.settings.set(
        kDefaultDanceFormationShapeKey,
        FormationShape.longways.name,
      );
      await repos.settings.set(
        kDefaultDanceProgressionKey,
        Progression.triple.name,
      );
      await repos.settings.set(kDefaultDancePhraseStructureKey, '6*8*2');

      await _pumpEditor(tester, repos);

      // The seeded phrase shows in the phrase field before any edit.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('phrase-field')))
            .controller
            ?.text,
        '6*8*2',
      );
      // The seeded formation shows in the formation dropdown.
      expect(_dropdownValue<FormationShape>(tester), FormationShape.longways);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Seeded Dance',
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = (await repos.dances.listAll()).single;
      expect(saved.form, DanceForm.square);
      expect(saved.formation.shape, FormationShape.longways);
      expect(saved.progression, Progression.triple);
      expect(saved.phraseStructure.raw, '6*8*2');
    });

    testWidgets('new dance with no saved defaults keeps hardcoded defaults', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('phrase-field')))
            .controller
            ?.text,
        '',
      );

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Plain Dance',
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = (await repos.dances.listAll()).single;
      expect(saved.form, DanceForm.contra);
      expect(saved.formation.shape, FormationShape.dupleImproper);
      expect(saved.progression, Progression.single);
      expect(saved.phraseStructure, PhraseStructure.standard);
    });

    testWidgets('existing dance ignores the defaults (its stored values win)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // Saved defaults differ from the existing dance's stored metadata.
      await repos.settings.set(kDefaultDanceFormKey, DanceForm.square.name);
      await repos.settings.set(
        kDefaultDanceFormationShapeKey,
        FormationShape.grid.name,
      );
      await repos.settings.set(
        kDefaultDanceProgressionKey,
        Progression.quadruple.name,
      );
      await repos.settings.set(kDefaultDancePhraseStructureKey, '6*8*2');

      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Existing',
          form: DanceForm.ecd,
          formation: const Formation(FormationShape.circleMixer),
          progression: Progression.none,
          phraseStructure: '8*8*1',
          createdAt: _now,
          updatedAt: _now,
        ),
      );

      await _pumpEditor(tester, repos, danceId: 'd1');

      // The existing dance's phrase and formation are shown, not the defaults.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('phrase-field')))
            .controller
            ?.text,
        '8*8*1',
      );
      expect(
        _dropdownValue<FormationShape>(tester),
        FormationShape.circleMixer,
      );

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      expect(saved!.form, DanceForm.ecd);
      expect(saved.formation.shape, FormationShape.circleMixer);
      expect(saved.progression, Progression.none);
      expect(saved.phraseStructure.raw, '8*8*1');
    });

    testWidgets('a restored draft overrides the seeded defaults', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kDefaultDanceFormKey, DanceForm.square.name);
      await repos.settings.set(
        kDefaultDanceFormationShapeKey,
        FormationShape.longways.name,
      );
      await repos.settings.set(
        kDefaultDanceProgressionKey,
        Progression.triple.name,
      );
      await repos.settings.set(kDefaultDancePhraseStructureKey, '6*8*2');

      // A previously-autosaved draft for a NEW dance, with its own metadata.
      const draft = EditorSnapshot(
        title: 'Drafted Dance',
        hook: '',
        notes: '',
        phrase: '2*8*4',
        formationDetail: '',
        form: DanceForm.ecd,
        formationShape: FormationShape.becketCw,
        progression: Progression.double,
        status: DanceStatus.active,
        authorIds: [],
        tagIds: [],
        tunes: [],
        links: [],
        sourceCitations: [],
        customValues: {},
        figureDrafts: [],
      );
      await repos.settings.set('editor_draft:new', encodeDraft(draft));

      await _pumpEditor(tester, repos);

      // Restore dialog appears; choose to restore the draft.
      await tester.tap(find.byKey(const ValueKey('draft-restore')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = (await repos.dances.listAll()).single;
      // The restored draft's metadata wins over the seeded defaults.
      expect(saved.title, 'Drafted Dance');
      expect(saved.form, DanceForm.ecd);
      expect(saved.formation.shape, FormationShape.becketCw);
      expect(saved.progression, Progression.double);
      expect(saved.phraseStructure.raw, '2*8*4');
      // The restored draft's (empty) figure list overrides the DD.2 template
      // seed rather than being appended to it.
      expect(saved.figures, isEmpty);
    });

    testWidgets('new dance with no template seeds the default stand_still x8', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Seeded Dance',
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = (await repos.dances.listAll()).single;
      expect(saved.figures, hasLength(8));
      for (final figure in saved.figures) {
        expect(figure.move, 'stand_still');
        expect(figure.params['beats'], 8);
      }
    });

    testWidgets('new dance seeds figures from a saved template', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([
          Figure(
            move: 'balance',
            params: const {'who': 'neighbors', 'beats': 4},
          ),
          Figure(
            move: 'swing',
            params: const {'who': 'neighbors', 'beats': 12},
          ),
        ]),
      );
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Templated Dance',
      );
      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = (await repos.dances.listAll()).single;
      expect(saved.figures, hasLength(2));
      expect(saved.figures[0].move, 'balance');
      expect(saved.figures[0].params['beats'], 4);
      expect(saved.figures[1].move, 'swing');
      expect(saved.figures[1].params['beats'], 12);
    });

    testWidgets(
      'new dance with an empty saved template opens with no figures',
      (tester) async {
        final repos = openTestRepositories();
        await repos.settings.set(
          kDefaultDanceFiguresTemplateKey,
          encodeFigures(const []),
        );
        await _pumpEditor(tester, repos);

        await tester.enterText(
          find.byKey(const ValueKey('title-field')),
          'Blank Dance',
        );
        await tester.tap(find.byKey(const ValueKey('save-dance')));
        await tester.pumpAndSettle();

        final saved = (await repos.dances.listAll()).single;
        expect(saved.figures, isEmpty);
      },
    );

    testWidgets('existing dance is unaffected by the figures template', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([
          Figure(
            move: 'balance',
            params: const {'who': 'neighbors', 'beats': 4},
          ),
        ]),
      );
      await repos.dances.create(
        _dance(
          id: 'd1',
          figures: [
            Figure(
              move: 'swing',
              params: const {'who': 'partners', 'beats': 8},
            ),
          ],
        ),
      );
      await _pumpEditor(tester, repos, danceId: 'd1');

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final saved = await repos.dances.getById('d1');
      expect(saved!.figures, hasLength(1));
      expect(saved.figures.single.move, 'swing');
    });
  });

  group('per-move insert defaults (DD.3)', () {
    testWidgets('inserting a move applies the saved param override', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // Blank starting template so figure-add yields figure 0.
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([]),
      );
      // Configure a per-move default: circle turns right (default is left).
      await repos.settings.set(
        kDefaultMoveParamOverridesKey,
        encodeMoveParamOverrides({
          'circle': {'turn': 'right'},
        }),
      );
      await _pumpEditor(tester, repos);

      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Circled',
      );
      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      await _selectMoveInEditor(tester, 0, 'circle', 'circle');

      await tester.tap(find.byKey(const ValueKey('save-dance')));
      await tester.pumpAndSettle();

      final figure = (await repos.dances.listAll()).single.figures.single;
      expect(figure.move, 'circle');
      // Overridden param takes the configured value...
      expect(figure.params['turn'], 'right');
      // ...while non-overridden params keep the taxonomy defaults.
      expect(figure.params['places'], 4);
      expect(figure.params['beats'], 8);
    });
  });

  group('Save FAB + delete (UI consistency pass)', () {
    testWidgets(
      'Save is a bottom-right FAB that shows a spinner while saving',
      (tester) async {
        final repos = openTestRepositories();
        await _pumpEditor(tester, repos);

        // The Save affordance is a FloatingActionButton (matching the program
        // builder), not an AppBar text button.
        final fab = find.byKey(const ValueKey('save-dance'));
        expect(fab, findsOneWidget);
        expect(tester.widget(fab), isA<FloatingActionButton>());

        await tester.enterText(
          find.byKey(const ValueKey('title-field')),
          'Spinner Dance',
        );
        await tester.tap(fab);
        // One frame after tapping: `_saving` is true, so the FAB renders a
        // spinner in place of the save icon (disabled while in flight).
        await tester.pump();
        expect(
          find.descendant(
            of: fab,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );

        await tester.pumpAndSettle();
        // Save completed and popped back to the launcher route.
        expect(find.byType(DanceEditorScreen), findsNothing);
        expect((await repos.dances.listAll()).single.title, 'Spinner Dance');
      },
    );

    testWidgets(
      'Delete soft-deletes the dance, pops, and shows an undo snackbar',
      (tester) async {
        final repos = openTestRepositories();
        await repos.dances.create(_dance(id: 'd1', title: 'Doomed Dance'));
        await _pumpEditor(tester, repos, danceId: 'd1');

        expect(find.byKey(const ValueKey('delete-dance')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('delete-dance')));
        await tester.pumpAndSettle();

        // Navigated back to the launcher route.
        expect(find.byType(DanceEditorScreen), findsNothing);
        expect(find.text('open'), findsOneWidget);

        // Undo snackbar names the deleted dance.
        expect(find.byKey(const ValueKey('deleted-snackbar')), findsOneWidget);
        expect(find.text('"Doomed Dance" deleted.'), findsOneWidget);

        // Soft-deleted (not hard-deleted): excluded from listAll, restorable.
        expect(
          (await repos.dances.listAll()).where((d) => d.id == 'd1'),
          isEmpty,
        );
        final deleted = await repos.dances.getById('d1', includeDeleted: true);
        expect(deleted, isNotNull);
        expect(deleted!.deletedAt, isNotNull);

        // Undo restores it.
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        final restored = await repos.dances.getById('d1');
        expect(restored, isNotNull);
        expect(restored!.deletedAt, isNull);
      },
    );

    testWidgets('Delete is hidden for a new (unsaved) dance', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);
      // Save is always available; delete only appears for a saved dance.
      expect(find.byKey(const ValueKey('save-dance')), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-dance')), findsNothing);
    });
  });

  group('lingo strikethrough on prose fields', () {
    // Flattens the styled span the field's [LingoTextEditingController] renders
    // for its current text into (text, decoration) parts.
    List<(String, TextDecoration?)> lingoParts(
      WidgetTester tester,
      String fieldKey,
    ) {
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(fieldKey)),
          matching: find.byType(EditableText),
        ),
      );
      final controller = editable.controller as LingoTextEditingController;
      final span = controller.buildTextSpan(
        context: tester.element(find.byKey(ValueKey(fieldKey))),
        style: null,
        withComposing: false,
      );
      final parts = <(String, TextDecoration?)>[];
      void visit(InlineSpan s) {
        if (s is! TextSpan) return;
        if (s.children != null) {
          for (final child in s.children!) {
            visit(child);
          }
        } else if (s.text != null && s.text!.isNotEmpty) {
          parts.add((s.text!, s.style?.decoration));
        }
      }

      visit(span);
      return parts;
    }

    testWidgets(
      'Title strikes through a discouraged term but not a normal one',
      (tester) async {
        final repos = openTestRepositories();
        await _pumpEditor(tester, repos);
        await tester.enterText(
          find.byKey(const ValueKey('title-field')),
          'gents swing',
        );
        await tester.pump();

        final parts = lingoParts(tester, 'title-field');
        final gents = parts.firstWhere(
          (p) => p.$1.toLowerCase() == 'gents',
          orElse: () => ('', null),
        );
        expect(gents.$2, TextDecoration.lineThrough);
        // A non-discouraged word keeps no strike-through decoration.
        final swing = parts.firstWhere(
          (p) => p.$1.toLowerCase().contains('swing'),
          orElse: () => ('', null),
        );
        expect(swing.$2, isNot(TextDecoration.lineThrough));
        // Accessible, non-visual signal is present.
        expect(find.byKey(const ValueKey('title-lingo-hint')), findsOneWidget);
      },
    );

    testWidgets('Calling notes strikes through a discouraged term', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);
      await tester.enterText(
        find.byKey(const ValueKey('notes-field')),
        'ask the gents to allemande',
      );
      await tester.pump();

      final parts = lingoParts(tester, 'notes-field');
      final gents = parts.firstWhere(
        (p) => p.$1.toLowerCase() == 'gents',
        orElse: () => ('', null),
      );
      expect(gents.$2, TextDecoration.lineThrough);
      expect(find.byKey(const ValueKey('notes-lingo-hint')), findsOneWidget);
    });

    testWidgets('no discouraged term means no strike-through and no hint', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos);
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'happy swing',
      );
      await tester.pump();

      final parts = lingoParts(tester, 'title-field');
      for (final p in parts) {
        expect(p.$2, isNot(TextDecoration.lineThrough));
      }
      expect(find.byKey(const ValueKey('title-lingo-hint')), findsNothing);
    });
  });

  group('Themed field decoration (UX-2 §5.3/§8)', () {
    testWidgets('Title field inherits the shared themed input border '
        '(filled, 12dp) instead of a hard-coded bare border', (tester) async {
      final repos = openTestRepositories();
      await _pumpEditor(tester, repos, theme: AppTheme.light);

      final decorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const ValueKey('title-field')),
          matching: find.byType(InputDecorator),
        ),
      );

      // Filled treatment comes from the shared InputDecorationTheme.
      expect(decorator.decoration.filled, isTrue);
      // Removing the ad-hoc `OutlineInputBorder()` lets the field pick up the
      // theme's 12dp radius; a bare default border would be 4dp.
      final border = decorator.decoration.border;
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border as OutlineInputBorder).borderRadius,
        const BorderRadius.all(Radius.circular(12)),
      );
    });
  });

  group('live reference data (issue #768, PR 9)', () {
    testWidgets(
      'a choreographer/tag/dance/source written elsewhere appears without '
      'reopening the editor',
      (tester) async {
        final repos = openTestRepositories();
        await _pumpEditor(tester, repos);

        // ignore: unused_result
        await repos.choreographers.upsert(
          Choreographer(id: 'c1', name: 'Gene Hubert'),
        );
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 't1', name: 'flowy'));
        await repos.publishedSources.upsert(
          PublishedSource(id: 's1', title: 'Zesty Contras'),
        );
        await repos.dances.create(
          _dance(id: 'd-other', title: 'Petronella Twirl'),
        );
        await tester.pumpAndSettle();

        // Author picker: option only exists if the choreographer cache was
        // re-read after the write above (the editor never queried it itself).
        await tester.enterText(
          find.byKey(const ValueKey('author-input')),
          'Gene',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('author-option-c1')), findsOneWidget);

        // Tag picker (Tier 2 — must expand "More details" first).
        await _expandMoreDetails(tester);
        await tester.enterText(
          find.byKey(const ValueKey('tag-input')),
          'flowy',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-option-t1')), findsOneWidget);
      },
    );
  });

  group('the draft survives a reference-data reload (issue #768, PR 9)', () {
    testWidgets(
      'a held title, undo stack and figure survive an unrelated tag write',
      (tester) async {
        // Opened against an EXISTING dance (not a new one): the mutation this
        // test must catch — re-running the one-shot `_load()` on a stream
        // emission — only clobbers something observable when there is a
        // stored value to clobber the edit back to. A brand-new dance's
        // `_load()` does not touch `titleController.text` when no seed title
        // is set, so it would pass against that mutation for the wrong
        // reason (nothing to overwrite, not "the overwrite was prevented").
        final repos = openTestRepositories();
        await repos.dances.create(_dance(id: 'd1', title: 'Original Title'));
        await _pumpEditor(tester, repos, danceId: 'd1');

        await tester.enterText(
          find.byKey(const ValueKey('title-field')),
          'My Working Title',
        );
        // Past the undo-push debounce (mirrors editor_autosave_undo_test.dart),
        // so the draft is recorded as dirty before the write below.
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('undo-button')))
              .onPressed,
          isNotNull,
          reason: 'typing must register as a dirty draft before the write',
        );

        // An unrelated write the reference-data stream must wake for — but
        // must not route into the draft.
        // ignore: unused_result
        await repos.tags.upsert(Tag(id: 't-unrelated', name: 'unrelated-tag'));
        await tester.pumpAndSettle();

        // Negative: the draft is untouched. Re-running `_load()` from a
        // stream emission (the mutation this test is written to catch) would
        // re-fetch the STORED dance and reset the title field back to
        // 'Original Title', clobbering the unsaved edit.
        expect(find.text('My Working Title'), findsOneWidget);
        expect(find.text('Original Title'), findsNothing);
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('undo-button')))
              .onPressed,
          isNotNull,
          reason: 'the undo stack must survive the reload',
        );

        // Positive control: the write did reach the screen, so the negatives
        // above are evidence the reload is scoped correctly rather than
        // evidence that nothing happened.
        await _expandMoreDetails(tester);
        await tester.enterText(
          find.byKey(const ValueKey('tag-input')),
          'unrelated',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('tag-option-t-unrelated')),
          findsOneWidget,
        );

        // Save still works: the draft was never disturbed.
        await tester.tap(find.byKey(const ValueKey('save-dance')));
        await tester.pumpAndSettle();
        final saved = await repos.dances.getById('d1');
        expect(saved!.title, 'My Working Title');
      },
    );
  });

  group('bounded reload count (issue #768, PR 9)', () {
    testWidgets(
      'a program write does not reload; a burst of dance-source writes '
      'coalesces',
      (tester) async {
        final db = openWidgetTestDatabase();
        addTearDown(db.close);
        final counting = _CountingDanceRepository(db, contraTaxonomy);
        final repos = CompendiumRepositories(
          db,
          contraTaxonomy,
          dances: counting,
        );
        await _pumpEditor(tester, repos);
        await tester.pumpAndSettle();
        final afterInitialLoad = counting.listAllCalls;
        expect(afterInitialLoad, greaterThan(0));

        // A program write does not touch the editor's read set at all.
        await repos.programs.create(
          Program(
            id: 'p1',
            title: 'Autumn Ball',
            status: ProgramStatus.draft,
            slots: const [],
            createdAt: _now,
            updatedAt: _now,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          counting.listAllCalls,
          afterInitialLoad,
          reason:
              'the editor renders nothing program-derived, so a program '
              'write must not reload it',
        );

        // A burst of writes to OTHER dances (the shape a batch-tag loop
        // produces) must coalesce rather than reload once per write.
        for (var i = 0; i < 10; i++) {
          await repos.dances.create(
            Dance(
              id: 'burst$i',
              title: 'Burst $i',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
        }
        await tester.pumpAndSettle();

        // Paired positive: the counter can move at all, so the bound below is
        // evidence about coalescing and not about a dead subscription.
        expect(
          counting.listAllCalls,
          greaterThan(afterInitialLoad),
          reason: 'without this, the bound below would pass for a dead reload',
        );
        expect(
          counting.listAllCalls - afterInitialLoad,
          lessThan(10),
          reason: 'a 10-write burst must not produce one reload per write',
        );
      },
    );
  });

  group('a reference-data load error is surfaced (issue #768, PR 9)', () {
    testWidgets('a failed choreographer read renders the load-error message', (
      tester,
    ) async {
      final failer = _FailOneChoreographersSelect();
      final repos = CompendiumRepositories(
        openWidgetTestDatabase(NativeDatabase.memory().interceptWith(failer)),
        contraTaxonomy,
      );
      addTearDown(repos.db.close);

      failer.arm();
      await _pumpEditor(tester, repos);
      await tester.pumpAndSettle();

      expect(
        failer.fired,
        isTrue,
        reason: 'the injected failure must actually have fired',
      );
      expect(find.text('Could not load the dance.'), findsOneWidget);
    });

    testWidgets(
      'a subsequent write recovers the editor after a stream error',
      (tester) async {
        final failer = _FailOneChoreographersSelect();
        final repos = CompendiumRepositories(
          openWidgetTestDatabase(NativeDatabase.memory().interceptWith(failer)),
          contraTaxonomy,
        );
        addTearDown(repos.db.close);

        failer.arm();
        await _pumpEditor(tester, repos);
        await tester.pumpAndSettle();

        expect(
          failer.fired,
          isTrue,
          reason: 'the injected failure must actually have fired',
        );
        expect(find.text('Could not load the dance.'), findsOneWidget);

        // A new write triggers reference-data stream re-emission, which
        // now succeeds because failer only failed one select.
        await repos.choreographers.upsert(
          Choreographer(id: 'c1', name: 'Gene Hubert'),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Could not load the dance.'),
          findsNothing,
          reason: 'successful stream emission must clear _loadError',
        );
        expect(
          find.byKey(const ValueKey('save-dance')),
          findsOneWidget,
          reason: 'the editor UI must be restored on recovery',
        );
      },
    );
  });
}

/// A [DanceRepository] that counts [listAll] calls, so a test can assert a
/// bound on how many times the reference-data stream re-read rather than only
/// observing its rendered effect.
class _CountingDanceRepository extends DanceRepository {
  _CountingDanceRepository(super.db, super.taxonomy);

  int listAllCalls = 0;

  @override
  Future<List<Dance>> listAll({bool includeDeleted = false}) {
    listAllCalls++;
    return super.listAll(includeDeleted: includeDeleted);
  }
}

/// Fails exactly one `choreographers` select once armed, then delegates
/// normally. Mirrors `_FailOneVenuesSelect` in `per_consumer_read_sets_test.dart`.
class _FailOneChoreographersSelect extends drift.QueryInterceptor {
  bool _armed = false;
  bool _fired = false;

  bool get fired => _fired;

  void arm() => _armed = true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_armed && !_fired && statement.contains('FROM "choreographers"')) {
      _fired = true;
      throw Exception('injected transient choreographers read failure');
    }
    return executor.runSelect(statement, args);
  }
}
