// A selected value the collection no longer offers — no live dance has it, or
// it came in with a saved search before any dance had it — must still show as
// a chip the user can see and remove (#2325). The panel used to build each
// section's chips from the offered values only, and to leave a section out
// when none were offered, so such a value went on filtering invisibly.
//
// One test per kind of facet. Every test offers NOTHING (the collection has
// no value at all for that section) and selects one value, which is the
// hardest case: the section itself would otherwise not be built.
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations_en.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/widgets/facet_panel.dart';
import '../support/l10n_harness.dart';

const _missing = 'Not in your library';
final _en = AppLocalizationsEn();

Future<void> _pump(
  WidgetTester tester,
  FacetSelections facets, {
  List<DifficultyLevel> allLevels = const [],
  Map<String, String> authorNames = const {},
  Map<String, String> allTagNames = const {},
  Map<String, String> sourceTitles = const {},
  List<CustomFieldDef> choiceFields = const [],
  List<CustomFieldDef> allCustomFields = const [],
  Map<String, String> deletedCustomFieldNames = const {},
  required VoidCallback onChanged,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: FacetPanel(
              facets: facets,
              forms: const [],
              formations: const [],
              progressions: const [],
              statuses: const [],
              levels: const [],
              hasMixedLevel: false,
              hasMixer: false,
              hasRating: false,
              authors: const [],
              tags: const [],
              citedSources: const [],
              tunes: const [],
              choiceFields: choiceFields,
              booleanFields: const [],
              textFields: const [],
              numberFields: const [],
              allLevels: allLevels,
              authorNames: authorNames,
              allTagNames: allTagNames,
              sourceTitles: sourceTitles,
              allCustomFields: allCustomFields,
              deletedCustomFieldNames: deletedCustomFieldNames,
              onChanged: () {
                onChanged();
                setState(() {});
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The chip keyed [key] shows [label], is selected, and tapping it removes the
/// selection ([isCleared] then holds) and tells the host once.
Future<void> _expectRemovableChip(
  WidgetTester tester, {
  required String key,
  required String label,
  required bool Function() isCleared,
  required int Function() changes,
}) async {
  final chip = find.byKey(ValueKey(key));
  expect(chip, findsOneWidget, reason: 'no chip for the selected value');
  expect(find.descendant(of: chip, matching: find.text(label)), findsOneWidget);
  expect(tester.widget<FilterChip>(chip).selected, isTrue);
  expect(isCleared(), isFalse);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(isCleared(), isTrue, reason: 'the chip must remove the selection');
  expect(changes(), 1);
}

void main() {
  group('a selected value no dance has still shows as a removable chip', () {
    testWidgets('form', (tester) async {
      final facets = FacetSelections()..forms.add(DanceForm.square);
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'form-square',
        label: danceFormLabel(_en, DanceForm.square),
        isCleared: () => facets.forms.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('formation', (tester) async {
      final facets = FacetSelections()..formations.add(FormationShape.becketCw);
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'formation-becketCw',
        label: formationShapeLabel(_en, FormationShape.becketCw),
        isCleared: () => facets.formations.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('progression', (tester) async {
      final facets = FacetSelections()..progressions.add(Progression.double);
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'progression-double',
        label: progressionLabel(_en, Progression.double),
        isCleared: () => facets.progressions.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('status', (tester) async {
      final facets = FacetSelections()..statuses.add(DanceStatus.broken);
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'status-broken',
        label: danceStatusLabel(_en, DanceStatus.broken),
        isCleared: () => facets.statuses.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('level, named from every configured level', (tester) async {
      final level = DifficultyLevel(id: 'lv1', label: 'Gnarly', position: 9);
      final facets = FacetSelections()..levels.add('lv1');
      var changes = 0;
      await _pump(
        tester,
        facets,
        allLevels: [level],
        onChanged: () => changes++,
      );
      await _expectRemovableChip(
        tester,
        key: 'level-id-lv1',
        label: 'Gnarly',
        isCleared: () => facets.levels.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('mixed level, either way', (tester) async {
      final facets = FacetSelections()..mixedLevel = false;
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      // "Not mixed level" is not offered by the panel; it is shown anyway.
      await _expectRemovableChip(
        tester,
        key: 'mixed-level-no',
        label: _en.commonNo,
        isCleared: () => facets.mixedLevel == null,
        changes: () => changes,
      );
    });

    testWidgets('mixer', (tester) async {
      final facets = FacetSelections()..mixer = true;
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'mixer-yes',
        label: _en.commonMixer,
        isCleared: () => facets.mixer == null,
        changes: () => changes,
      );
    });

    testWidgets('minimum rating', (tester) async {
      final facets = FacetSelections()..minRating = 4;
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'min-rating-4',
        label: _en.collectionFacetMinRatingChip(4),
        isCleared: () => facets.minRating == null,
        changes: () => changes,
      );
    });

    testWidgets('called / not called, in a collection with no history', (
      tester,
    ) async {
      final facets = FacetSelections()..callStatuses.add(false);
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'call-status-not-called',
        label: _en.collectionFacetNotCalled,
        isCleared: () => facets.callStatuses.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('author, named from every choreographer', (tester) async {
      final facets = FacetSelections()..authorIds.add('c1');
      var changes = 0;
      await _pump(
        tester,
        facets,
        authorNames: const {'c1': 'Gene Hubert'},
        onChanged: () => changes++,
      );
      final chip = find.byKey(const ValueKey('author-facet-chip-c1'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('Gene Hubert')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: chip, matching: find.byIcon(Icons.close)),
      );
      await tester.pumpAndSettle();
      expect(facets.authorIds, isEmpty);
      expect(changes, 1);
    });

    testWidgets('tag, named from every tag', (tester) async {
      final facets = FacetSelections()..setTag('t1', selected: true);
      var changes = 0;
      await _pump(
        tester,
        facets,
        allTagNames: const {'t1': 'family'},
        onChanged: () => changes++,
      );
      await _expectRemovableChip(
        tester,
        key: 'tag-t1',
        label: 'family',
        isCleared: () => facets.tagIds.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('a deleted tag reads "Not in your library", never its id', (
      tester,
    ) async {
      final facets = FacetSelections()..setTag('gone-id', selected: true);
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      expect(find.text('gone-id'), findsNothing);
      await _expectRemovableChip(
        tester,
        key: 'tag-gone-id',
        label: _missing,
        isCleared: () => facets.tagIds.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('untagged, in a collection with no tags', (tester) async {
      final facets = FacetSelections()..untagged = true;
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'untagged-chip',
        label: _en.collectionFacetUntagged,
        isCleared: () => !facets.untagged,
        changes: () => changes,
      );
    });

    testWidgets('source, named from every published source', (tester) async {
      final facets = FacetSelections()..sourceIds.add('s1');
      var changes = 0;
      await _pump(
        tester,
        facets,
        sourceTitles: const {'s1': 'Zesty Contras'},
        onChanged: () => changes++,
      );
      await _expectRemovableChip(
        tester,
        key: 'source-s1',
        label: 'Zesty Contras',
        isCleared: () => facets.sourceIds.isEmpty,
        changes: () => changes,
      );
    });

    // Meter, Key and Tunes already kept a picked value no dance has (ADR-006
    // F3, #1420); these pin that it stays so.
    testWidgets('meter', (tester) async {
      final facets = FacetSelections()..meters.add('9/8');
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'meter-9/8',
        label: '9/8',
        isCleared: () => facets.meters.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('key', (tester) async {
      final facets = FacetSelections()..musicalKeys.add('F# minor');
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'musical-key-F# minor',
        label: 'F# minor',
        isCleared: () => facets.musicalKeys.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('tune', (tester) async {
      final facets = FacetSelections()..addTune('Dmaj');
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      final chip = find.byKey(const ValueKey('tunes-facet-chip-Dmaj'));
      expect(chip, findsOneWidget);
      await tester.tap(
        find.descendant(of: chip, matching: find.byIcon(Icons.close)),
      );
      await tester.pumpAndSettle();
      expect(facets.tunes, isEmpty);
      expect(changes, 1);
    });

    testWidgets('a custom choice option the field no longer has', (
      tester,
    ) async {
      final region = CustomFieldDef(
        id: 'f1',
        key: 'region',
        label: 'Region',
        type: CustomFieldType.choice,
        choices: const ['north', 'south'],
      );
      final facets = FacetSelections()..choiceValues['f1'] = {'east'};
      var changes = 0;
      await _pump(
        tester,
        facets,
        choiceFields: [region],
        allCustomFields: [region],
        onChanged: () => changes++,
      );
      await _expectRemovableChip(
        tester,
        key: 'cf-f1-east',
        label: 'east',
        isCleared: () => facets.choiceValues['f1']?.isEmpty ?? true,
        changes: () => changes,
      );
    });

    testWidgets('a custom field that is no longer offered as a filter', (
      tester,
    ) async {
      // Not searchable any more, so not among the offered boolean fields;
      // the search still applies the selection, so the section must show.
      final def = CustomFieldDef(
        id: 'f2',
        key: 'contra_dance',
        label: 'Called at camp',
        type: CustomFieldType.boolean,
      );
      final facets = FacetSelections()..booleanValues['f2'] = true;
      var changes = 0;
      await _pump(
        tester,
        facets,
        allCustomFields: [def],
        onChanged: () => changes++,
      );
      expect(find.text('Called at camp'), findsOneWidget);
      await _expectRemovableChip(
        tester,
        key: 'cf-f2-yes',
        label: _en.commonYes,
        isCleared: () => !facets.booleanValues.containsKey('f2'),
        changes: () => changes,
      );
    });

    // A saved search can name a custom field that has since been deleted, or
    // changed type; the search leaves the filter out, and the notice asks the
    // user to remove it, so it needs a chip like any other selection.
    testWidgets('a choice on a deleted custom field, named as it was', (
      tester,
    ) async {
      final facets = FacetSelections()..choiceValues['cf1'] = {'calm'};
      var changes = 0;
      await _pump(
        tester,
        facets,
        deletedCustomFieldNames: const {'cf1': 'Mood'},
        onChanged: () => changes++,
      );
      // (The panel puts its section's key on the padding around it too.)
      expect(find.byKey(const ValueKey('facet-row-cf-stale')), findsWidgets);
      await _expectRemovableChip(
        tester,
        key: 'cf-stale-cf1-choice-calm',
        label: 'Mood: calm',
        isCleared: () => facets.isEmpty,
        changes: () => changes,
      );
      // Its section goes with its last chip.
      expect(find.byKey(const ValueKey('facet-row-cf-stale')), findsNothing);
    });

    testWidgets('a text filter on a deleted field whose name is not known', (
      tester,
    ) async {
      final facets = FacetSelections()
        ..textValues['cf3'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: 'slow',
        );
      var changes = 0;
      await _pump(tester, facets, onChanged: () => changes++);
      await _expectRemovableChip(
        tester,
        key: 'cf-stale-cf3-text',
        label: _missing,
        isCleared: () => facets.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('a number filter on a deleted field', (tester) async {
      final facets = FacetSelections()
        ..numberValues['cf4'] = const NumberFacetState(
          op: CustomFieldOp.eq,
          lo: 3,
        );
      var changes = 0;
      await _pump(
        tester,
        facets,
        deletedCustomFieldNames: const {'cf4': 'Tempo'},
        onChanged: () => changes++,
      );
      await _expectRemovableChip(
        tester,
        key: 'cf-stale-cf4-number',
        label: 'Tempo',
        isCleared: () => facets.isEmpty,
        changes: () => changes,
      );
    });

    testWidgets('a yes/no filter on a field that is now a text field: named '
        'from the live field, and removing it keeps its text filter', (
      tester,
    ) async {
      final def = CustomFieldDef(
        id: 'cf2',
        key: 'mood',
        label: 'Mood',
        type: CustomFieldType.text,
      );
      final facets = FacetSelections()
        ..booleanValues['cf2'] = true
        ..textValues['cf2'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: 'calm',
        );
      var changes = 0;
      await _pump(
        tester,
        facets,
        allCustomFields: [def],
        onChanged: () => changes++,
      );
      await _expectRemovableChip(
        tester,
        key: 'cf-stale-cf2-bool',
        label: 'Mood: ${_en.commonYes}',
        isCleared: () => facets.booleanValues.isEmpty,
        changes: () => changes,
      );
      expect(facets.textValues['cf2']?.value, 'calm');
    });
  });
}
