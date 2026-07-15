import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/dance_list_screen.dart';

import 'support/test_repositories.dart';

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
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
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
Future<void> _selectMoveInEditor(
  WidgetTester tester,
  int index,
  String typed,
  String optionId,
) async {
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

  testWidgets('level and mixed level round-trip on save', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance(id: 'd1', title: 'Original'));
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    // Pick a level from the dropdown.
    await tester.tap(find.byKey(const ValueKey('level-field-none')));
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

  testWidgets('selecting Unspecified clears an existing level', (tester) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(id: 'd1', title: 'Original', level: DanceLevel.advanced),
    );
    await _pumpEditor(tester, repos, danceId: 'd1');

    await _expandMoreDetails(tester);

    await tester.tap(find.byKey(const ValueKey('level-field-advanced')));
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
    final monthField = find.byKey(const ValueKey('composed-on-month-0'));
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('composed-on-month-0')),
    );
    await tester.tap(find.byKey(const ValueKey('composed-on-month-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feb').last);
    await tester.pumpAndSettle();
    // … and the 29th (valid in 2004).
    await tester.ensureVisible(find.byKey(const ValueKey('composed-on-day-0')));
    await tester.tap(find.byKey(const ValueKey('composed-on-day-0')));
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

  testWidgets('untouched boolean custom field is not persisted', (
    tester,
  ) async {
    final repos = openTestRepositories();
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
    await _expandMoreDetails(tester);
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
    await _pumpEditor(tester, repos);

    await tester.enterText(find.byKey(const ValueKey('title-field')), 'Swung');
    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await _selectMoveInEditor(tester, 0, 'sw', 'swing');

    // Progression + note round-trip alongside the params.
    await tester.tap(find.byKey(const ValueKey('figure-0-progression')));
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

    // The existing figure loads into an editable row.
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

    await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
    await tester.pumpAndSettle();
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
        'Ted Sannella',
      );
      await tester.tap(find.byKey(const ValueKey('source-save')));
      await tester.pumpAndSettle();

      // A new source was persisted and a citation chip added.
      final sources = await repos.publishedSources.listAll();
      expect(sources, hasLength(1));
      expect(sources.single.title, 'Shadrach');
      expect(sources.single.author, 'Ted Sannella');

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
      final progressionField = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            (w.key as ValueKey).value.toString().startsWith(
              'progression-field-',
            ),
      );
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
}
