import 'dart:async';
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/aggressive_beats_update_scope.dart';
import 'package:compendium_app/src/data/app_theme_scope.dart';
import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/custom_themes_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_scope.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/search/collection_query.dart';
import 'package:compendium_app/src/search/program_sort.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';

import 'support/test_repositories.dart';
import 'support/l10n_harness.dart';
import 'support/screen_size.dart';
import 'support/text_scale.dart';

final _now = DateTime.utc(2026, 1, 1);

Dance _dance({required String id, required String title}) => Dance(
  id: id,
  title: title,
  authorIds: const [],
  tagIds: const [],
  form: DanceForm.contra,
  formation: const Formation(FormationShape.dupleImproper),
  status: DanceStatus.active,
  figures: const [],
  customFields: const [],
  hook: '',
  createdAt: _now,
  updatedAt: _now,
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

/// A [SettingsRepository] whose reads can be held open per key. The value is
/// captured *before* the gate, so a released read resolves with what storage
/// held when the read began — exactly the late read a user edit must beat.
class _GatedSettings extends SettingsRepository {
  _GatedSettings(super.db);

  final Map<String, Completer<void>> _gates = {};

  Completer<void> hold(String key) => _gates[key] = Completer<void>();

  @override
  Future<Object?> get(String key) async {
    final value = await super.get(key);
    final gate = _gates[key];
    if (gate != null) await gate.future;
    return value;
  }
}

class _ThrowingReadSettings extends SettingsRepository {
  _ThrowingReadSettings(super.db, {required this.throwFor});

  final Set<String> throwFor;

  @override
  Future<Object?> get(String key) {
    if (throwFor.contains(key)) {
      return Future<Object?>.error(StateError('read failed: $key'));
    }
    return super.get(key);
  }
}

/// Counts and optionally fails the two dance reads the Defaults section makes:
/// the titles-only projection and the full load behind `CollectionData`.
class _CountingDances extends DanceRepository {
  _CountingDances(CompendiumDatabase db) : super(db, contraTaxonomy);

  bool failTitles = false;
  bool failFullLoad = false;
  int titleLoads = 0;
  int fullLoads = 0;

  @override
  Future<List<({String id, String title})>> listIdsAndTitles({
    bool includeDeleted = false,
  }) async {
    titleLoads++;
    if (failTitles) throw StateError('titles load failed');
    return super.listIdsAndTitles(includeDeleted: includeDeleted);
  }

  @override
  Future<List<Dance>> listAll({bool includeDeleted = false}) async {
    fullLoads++;
    if (failFullLoad) throw StateError('full load failed');
    return super.listAll(includeDeleted: includeDeleted);
  }
}

class _RecordingCrashLogSink implements CrashLogSink {
  final List<String> sources = [];

  @override
  void record(Object error, StackTrace? stack, {required String source}) {
    sources.add(source);
  }
}

Future<void> _openDifficultySection(WidgetTester tester) async {
  await _scrollTo(tester, const ValueKey('defaults-difficulty-levels-section'));
  await tester.tap(
    find.byKey(const ValueKey('defaults-difficulty-levels-section')),
  );
  await tester.pumpAndSettle();
}

/// Pumps the settings screen on a wide surface backed by [repos] and opens the
/// Defaults section.
Future<void> _pumpDefaults(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool expandGroups = true,
  ValueNotifier<Set<String>>? hiddenFacets,
  Size surface = const Size(1200, 4500),
  double textScale = 1,
}) async {
  await setScreenSize(tester, surface);

  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  final theme = ValueNotifier<AppThemeSelection>(AppThemeSelection.system);
  final customThemes = CustomThemesController(repos.settings);
  await customThemes.load();
  final aggressiveBeatsUpdate = ValueNotifier<bool>(
    await repos.settings.get(kAggressiveBeatsUpdateKey) == true,
  );
  final shorthandMappings = ShorthandMappingsController(repos.settings);
  await shorthandMappings.load();
  final walkthroughSnippets = WalkthroughSnippetLibraryController(
    repos.settings,
  );
  await walkthroughSnippets.load();
  final facetsNotifier = hiddenFacets ?? ValueNotifier<Set<String>>(const {});
  if (hiddenFacets == null) addTearDown(facetsNotifier.dispose);
  addTearDown(dialect.dispose);
  addTearDown(theme.dispose);
  addTearDown(customThemes.dispose);
  addTearDown(aggressiveBeatsUpdate.dispose);
  addTearDown(shorthandMappings.dispose);
  addTearDown(walkthroughSnippets.dispose);

  // The scopes sit above the Navigator (as in the real app) so a narrow
  // surface, where a section opens as a pushed route, still reaches them.
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) {
        final scaled = textScaleBuilder(textScale)?.call(context, child);
        return RepositoriesScope(
          repositories: repos,
          child: AppThemeScope(
            notifier: theme,
            child: CustomThemesScope(
              controller: customThemes,
              child: ActiveDialectScope(
                notifier: dialect,
                child: AggressiveBeatsUpdateScope(
                  notifier: aggressiveBeatsUpdate,
                  child: ShorthandMappingsScope(
                    controller: shorthandMappings,
                    child: WalkthroughSnippetLibraryScope(
                      controller: walkthroughSnippets,
                      child: CollectionFacetsScope(
                        notifier: facetsNotifier,
                        child: scaled ?? child!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      home: const SettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('settings-nav-defaults')));
  await tester.pumpAndSettle();
  if (expandGroups) {
    await tester.tap(find.byKey(const ValueKey('defaults-program-group')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('defaults-authoring-group')),
    );
    await tester.tap(find.byKey(const ValueKey('defaults-authoring-group')));
    await tester.pumpAndSettle();
  }
}

/// Scrolls the Defaults content list until [key] is visible. The
/// Dance-authoring subsection sits below the fold on the test surface; the
/// tester selects the relevant ancestor scrollable for the target.
Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starting program templates round-trip semantic entries', () {
    final encoded = encodeStartingProgramTemplate([
      const StartingProgramTemplateEntry(danceId: 'dance-1'),
      const StartingProgramTemplateEntry(
        danceId: 'dance-2',
        text: 'Guest caller',
      ),
      const StartingProgramTemplateEntry(text: Program.breakSlotText),
    ]);

    final decoded = tryDecodeStartingProgramTemplate(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.map((entry) => entry.danceId), [
      'dance-1',
      'dance-2',
      null,
    ]);
    expect(decoded.map((entry) => entry.text), [
      null,
      'Guest caller',
      Program.breakSlotText,
    ]);
  });

  test('starting program encoder emits only decoder-accepted entries', () {
    final encoded = encodeStartingProgramTemplate([
      for (var i = 0; i < 101; i++)
        StartingProgramTemplateEntry(
          danceId: 'dance-$i',
          text: i == 0 ? 'x' * 501 : null,
        ),
    ]);

    final decoded = tryDecodeStartingProgramTemplate(encoded);
    expect(decoded, hasLength(100));
    expect(decoded!.first.text, hasLength(500));
  });

  test(
    'starting program templates reject malformed or unsupported entries',
    () {
      expect(
        tryDecodeStartingProgramTemplate(
          jsonEncode({
            'version': 1,
            'slots': <Map<String, Object?>>[{}],
          }),
        ),
        isNull,
      );
      expect(
        tryDecodeStartingProgramTemplate(
          jsonEncode({
            'version': 1,
            'slots': [
              {'danceId': 'dance-1', 'id': 'persisted-id'},
            ],
          }),
        ),
        isNull,
      );
      expect(startingProgramTemplateFromStored('not-json'), isEmpty);
    },
  );

  testWidgets('Defaults dropdown rows survive 360 dp wide at 2x text', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(
      tester,
      repos,
      surface: const Size(360, 4500),
      textScale: 2,
      expandGroups: false,
    );
    expect(tester.takeException(), isNull);

    Future<void> expectOnScreen(String key) async {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      // A dropdown inside a ListTile's trailing slot cannot wrap.
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.byKey(ValueKey(key)),
        ),
        findsNothing,
        reason: key,
      );
      final box = tester.getRect(find.byKey(ValueKey(key)));
      expect(box.left, greaterThanOrEqualTo(0), reason: key);
      expect(box.right, lessThanOrEqualTo(360), reason: key);
    }

    await expectOnScreen('defaults-collection-sort');
    await expectOnScreen('defaults-program-sort');
    // The dance-form rows live in the authoring group, collapsed by default.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('defaults-authoring-group')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('defaults-authoring-group')));
    await tester.pumpAndSettle();
    await expectOnScreen('defaults-dance-form');
    await expectOnScreen('defaults-dance-formation');
    await expectOnScreen('defaults-dance-progression');
    expect(tester.takeException(), isNull);
  });

  testWidgets('program and authoring groups start collapsed', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos, expandGroups: false);

    expect(find.byKey(const ValueKey('defaults-program-caller')), findsNothing);
    expect(find.byKey(const ValueKey('defaults-dance-form')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('defaults-program-group')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('defaults-program-caller')),
      findsOneWidget,
    );
  });

  testWidgets(
    'starting program notes keep their dance when edited and reordered',
    (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance(id: 'd1', title: 'First dance'));
      await repos.dances.create(_dance(id: 'd2', title: 'Second dance'));
      await repos.settings.set(
        kDefaultStartingProgramKey,
        encodeStartingProgramTemplate([
          const StartingProgramTemplateEntry(danceId: 'd1'),
          const StartingProgramTemplateEntry(danceId: 'd2'),
        ]),
      );

      await _pumpDefaults(tester, repos);
      final noteField = find.byType(TextFormField).first;
      await tester.enterText(noteField, 'Guest caller');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pumpAndSettle();

      final stored = startingProgramTemplateFromStored(
        await repos.settings.get(kDefaultStartingProgramKey),
      );
      expect(stored.map((entry) => entry.danceId), ['d2', 'd1']);
      expect(stored.last.text, 'Guest caller');
    },
  );

  group('default import tags (#1476)', () {
    Future<void> openImportGroup(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('defaults-import-group')),
      );
      await tester.tap(find.byKey(const ValueKey('defaults-import-group')));
      await tester.pumpAndSettle();
    }

    testWidgets('choosing and clearing a tag persists the selection', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final _ = await repos.tags.upsert(Tag(id: 't1', name: 'No card'));
      final _ = await repos.tags.upsert(Tag(id: 't2', name: 'Smooth'));
      await _pumpDefaults(tester, repos);
      await openImportGroup(tester);

      await tester.tap(find.byKey(const ValueKey('defaults-import-tag-t1')));
      await tester.pumpAndSettle();
      expect(
        tryDecodeDefaultImportTagNames(
          await repos.settings.get(kDefaultImportTagNamesKey),
        ),
        ['No card'],
      );

      await tester.tap(find.byKey(const ValueKey('defaults-import-tag-t2')));
      await tester.tap(find.byKey(const ValueKey('defaults-import-tag-t1')));
      await tester.pumpAndSettle();
      expect(
        tryDecodeDefaultImportTagNames(
          await repos.settings.get(kDefaultImportTagNamesKey),
        ),
        ['Smooth'],
      );
    });

    testWidgets('at the cap the unchosen tags are disabled, so no visible '
        'selection is left unsaved', (tester) async {
      final repos = openTestRepositories();
      for (var i = 0; i <= kMaxDefaultImportTags; i++) {
        final _ = await repos.tags.upsert(
          Tag(id: 't$i', name: 'Tag ${i.toString().padLeft(2, '0')}'),
        );
      }
      await repos.settings.set(
        kDefaultImportTagNamesKey,
        encodeDefaultImportTagNames([
          for (var i = 0; i < kMaxDefaultImportTags; i++)
            'Tag ${i.toString().padLeft(2, '0')}',
        ]),
      );
      await _pumpDefaults(tester, repos);
      await openImportGroup(tester);

      final extra = find.byKey(
        ValueKey('defaults-import-tag-t$kMaxDefaultImportTags'),
      );
      await tester.ensureVisible(extra);
      expect(tester.widget<FilterChip>(extra).onSelected, isNull);
      final chosen = find.byKey(const ValueKey('defaults-import-tag-t0'));
      await tester.ensureVisible(chosen);
      expect(tester.widget<FilterChip>(chosen).onSelected, isNotNull);
    });

    testWidgets('a saved selection shows as chosen, and a deleted tag is '
        'dropped on the next save', (tester) async {
      final repos = openTestRepositories();
      final _ = await repos.tags.upsert(Tag(id: 't1', name: 'No card'));
      final _ = await repos.tags.upsert(Tag(id: 't2', name: 'Smooth'));
      await repos.settings.set(
        kDefaultImportTagNamesKey,
        encodeDefaultImportTagNames(['No card', 'Gone']),
      );
      await _pumpDefaults(tester, repos);
      await openImportGroup(tester);

      final chip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('defaults-import-tag-t1')),
      );
      expect(chip.selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('defaults-import-tag-t2')));
      await tester.pumpAndSettle();
      expect(
        tryDecodeDefaultImportTagNames(
          await repos.settings.get(kDefaultImportTagNamesKey),
        ),
        ['No card', 'Smooth'],
      );
    });
  });

  testWidgets('Defaults appears as a settings section', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    // Display defaults retains collection sorting; dance-detail rendering
    // belongs to Dialect's dance-details subsection.
    expect(
      find.byKey(const ValueKey('defaults-collection-sort')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('defaults-dance-detail-canonical')),
      findsNothing,
    );
  });

  testWidgets('difficulty vocabulary setting starts collapsed', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await _scrollTo(
      tester,
      const ValueKey('defaults-difficulty-levels-section'),
    );

    final tile = tester.widget<ExpansionTile>(
      find.byKey(const ValueKey('defaults-difficulty-levels-section')),
    );
    expect(tile.initiallyExpanded, isFalse);
  });

  testWidgets('difficulty vocabulary rename persists when focus is lost', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await _scrollTo(
      tester,
      const ValueKey('defaults-difficulty-levels-section'),
    );
    await tester.tap(
      find.byKey(const ValueKey('defaults-difficulty-levels-section')),
    );
    await tester.pumpAndSettle();

    final labelKey = const ValueKey(
      'difficulty-level-label-${DifficultyLevel.beginnerId}',
    );
    await tester.enterText(find.byKey(labelKey), 'Novice');
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final renamed = await repos.difficultyLevels.getById(
      DifficultyLevel.beginnerId,
    );
    expect(renamed?.label, 'Novice');
  });

  testWidgets('blank difficulty rename resets the field', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await _scrollTo(
      tester,
      const ValueKey('defaults-difficulty-levels-section'),
    );
    await tester.tap(
      find.byKey(const ValueKey('defaults-difficulty-levels-section')),
    );
    await tester.pumpAndSettle();

    final labelKey = const ValueKey(
      'difficulty-level-label-${DifficultyLevel.beginnerId}',
    );
    await tester.enterText(find.byKey(labelKey), '');
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(find.byKey(labelKey)).controller?.text,
      'Beginner',
    );
    expect(
      await repos.difficultyLevels.getById(DifficultyLevel.beginnerId),
      DifficultyLevel.beginner,
    );
    final l10n = _l10n(tester);
    expect(
      find.text(l10n.settingsDefaultsDifficultyLevelEmpty),
      findsOneWidget,
    );
    expect(find.textContaining('Invalid argument'), findsNothing);
  });

  testWidgets('deleting an in-use difficulty level shows a localised message', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.dances.create(
      _dance(
        id: 'd1',
        title: 'Uses it',
      ).copyWith(difficultyLevelId: DifficultyLevel.beginnerId),
    );
    await _pumpDefaults(tester, repos);
    await _openDifficultySection(tester);

    await tester.tap(
      find.byKey(
        const ValueKey('difficulty-level-delete-${DifficultyLevel.beginnerId}'),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = _l10n(tester);
    expect(
      find.text(l10n.settingsDefaultsDifficultyLevelInUse('Beginner', 1)),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('difficulty-beginner'), findsNothing);
    expect(
      await repos.difficultyLevels.getById(DifficultyLevel.beginnerId),
      DifficultyLevel.beginner,
    );
  });

  testWidgets(
    'renaming a difficulty level to an existing label shows a localised message',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await _openDifficultySection(tester);

      await tester.enterText(
        find.byKey(
          const ValueKey(
            'difficulty-level-label-${DifficultyLevel.intermediateId}',
          ),
        ),
        'Beginner',
      );
      tester.binding.focusManager.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(
        find.text(l10n.settingsDefaultsDifficultyLevelDuplicate('Beginner')),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
    },
  );

  testWidgets('failed difficulty rename resets the field', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await _scrollTo(
      tester,
      const ValueKey('defaults-difficulty-levels-section'),
    );
    await tester.tap(
      find.byKey(const ValueKey('defaults-difficulty-levels-section')),
    );
    await tester.pumpAndSettle();

    final labelKey = const ValueKey(
      'difficulty-level-label-${DifficultyLevel.beginnerId}',
    );
    await tester.enterText(find.byKey(labelKey), 'Intermediate');
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(find.byKey(labelKey)).controller?.text,
      'Beginner',
    );
    expect(
      (await repos.difficultyLevels.getById(DifficultyLevel.beginnerId))?.label,
      'Beginner',
    );
  });

  testWidgets(
    'difficulty vocabulary reorder uses the displayed destination index',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await _scrollTo(
        tester,
        const ValueKey('defaults-difficulty-levels-section'),
      );
      await tester.tap(
        find.byKey(const ValueKey('defaults-difficulty-levels-section')),
      );
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView).first,
      );
      expect(list.buildDefaultDragHandles, isFalse);
      expect(
        find.descendant(
          of: find.byType(ReorderableListView).first,
          matching: find.byType(ReorderableDragStartListener),
        ),
        findsNWidgets(3),
      );
      list.onReorderItem!(0, 2);
      await tester.pumpAndSettle();

      final levels = await repos.difficultyLevels.listAll();
      expect(levels.map((level) => level.id), [
        DifficultyLevel.intermediateId,
        DifficultyLevel.advancedId,
        DifficultyLevel.beginnerId,
      ]);
    },
  );

  testWidgets('Display defaults show the historical defaults when unset', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      const SortDefaultSetting.concrete(CollectionSort.title),
    );
    expect(
      find.byKey(const ValueKey('defaults-dance-detail-canonical')),
      findsNothing,
    );
  });

  testWidgets('changing the default sort persists it', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await tester.tap(find.byKey(const ValueKey('defaults-collection-sort')));
    await tester.pumpAndSettle();
    // Pick "Author" from the opened dropdown menu (last matches the menu item).
    await tester.tap(find.text('Author').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      const SortDefaultSetting.concrete(CollectionSort.author),
    );
    expect(
      await repos.settings.get(kDefaultCollectionSortKey),
      CollectionSort.author.name,
    );
  });

  testWidgets('a saved default sort is reflected on reload', (tester) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultCollectionSortKey,
      CollectionSort.lastCalled.name,
    );

    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      const SortDefaultSetting.concrete(CollectionSort.lastCalled),
    );
  });

  testWidgets('both saved Display defaults reflect independently on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultCollectionSortKey,
      CollectionSort.author.name,
    );
    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
            find.byKey(const ValueKey('defaults-collection-sort')),
          )
          .value,
      const SortDefaultSetting.concrete(CollectionSort.author),
    );
    expect(
      find.byKey(const ValueKey('defaults-dance-detail-canonical')),
      findsNothing,
    );
  });

  group('Programs default sort (issue #895)', () {
    testWidgets('shows Title (the historical default) when unset', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);

      expect(
        tester
            .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
              find.byKey(const ValueKey('defaults-program-sort')),
            )
            .value,
        const SortDefaultSetting.concrete(ProgramSort.title),
      );
    });

    testWidgets('changing it persists the concrete sort', (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);

      await tester.tap(find.byKey(const ValueKey('defaults-program-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event date').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
              find.byKey(const ValueKey('defaults-program-sort')),
            )
            .value,
        const SortDefaultSetting.concrete(ProgramSort.eventDate),
      );
      expect(
        await repos.settings.get(kDefaultProgramSortKey),
        ProgramSort.eventDate.name,
      );
    });

    testWidgets('a saved default sort is reflected on reload', (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultProgramSortKey,
        ProgramSort.recentlyUpdated.name,
      );

      await _pumpDefaults(tester, repos);

      expect(
        tester
            .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
              find.byKey(const ValueKey('defaults-program-sort')),
            )
            .value,
        const SortDefaultSetting.concrete(ProgramSort.recentlyUpdated),
      );
    });
  });

  group('"Last used" default-sort option (issue #895)', () {
    testWidgets(
      'selecting Last used for Collection persists the sentinel, not an '
      'enum name',
      (tester) async {
        final repos = openTestRepositories();
        await _pumpDefaults(tester, repos);

        await tester.tap(
          find.byKey(const ValueKey('defaults-collection-sort')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Last used').last);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
                find.byKey(const ValueKey('defaults-collection-sort')),
              )
              .value,
          const SortDefaultSetting.lastUsed(CollectionSort.title),
        );
        expect(
          await repos.settings.get(kDefaultCollectionSortKey),
          kLastUsedSortSentinel,
        );
      },
    );

    testWidgets(
      'selecting Last used for Programs persists the sentinel, not an enum '
      'name',
      (tester) async {
        final repos = openTestRepositories();
        await _pumpDefaults(tester, repos);

        await tester.tap(find.byKey(const ValueKey('defaults-program-sort')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Last used').last);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
                find.byKey(const ValueKey('defaults-program-sort')),
              )
              .value,
          const SortDefaultSetting.lastUsed(ProgramSort.title),
        );
        expect(
          await repos.settings.get(kDefaultProgramSortKey),
          kLastUsedSortSentinel,
        );
      },
    );

    testWidgets(
      'a saved "last_used" sentinel reflects as Last used on reload for '
      'both lists',
      (tester) async {
        final repos = openTestRepositories();
        await repos.settings.set(
          kDefaultCollectionSortKey,
          kLastUsedSortSentinel,
        );
        await repos.settings.set(kDefaultProgramSortKey, kLastUsedSortSentinel);

        await _pumpDefaults(tester, repos);

        expect(
          tester
              .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
                find.byKey(const ValueKey('defaults-collection-sort')),
              )
              .value,
          const SortDefaultSetting.lastUsed(CollectionSort.title),
        );
        expect(
          tester
              .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
                find.byKey(const ValueKey('defaults-program-sort')),
              )
              .value,
          const SortDefaultSetting.lastUsed(ProgramSort.title),
        );
      },
    );
  });

  testWidgets('Program-defaults subsection renders both fields', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    expect(find.text('Program defaults'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('defaults-program-caller')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('defaults-program-band')), findsOneWidget);
  });

  testWidgets('default group headings use the shared section heading style', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos, expandGroups: false);

    final theme = Theme.of(
      tester.element(find.byKey(const ValueKey('defaults-program-group'))),
    );
    final expectedStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.primary,
    );

    for (final key in [
      const ValueKey('defaults-program-group'),
      const ValueKey('defaults-authoring-group'),
    ]) {
      final tile = tester.widget<ExpansionTile>(find.byKey(key));
      final title = tile.title as Text;
      expect(title.style, expectedStyle);
    }
  });

  testWidgets('editing the default caller and band persists them', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await tester.enterText(
      find.byKey(const ValueKey('defaults-program-caller')),
      'Folk Process',
    );
    await tester.enterText(
      find.byKey(const ValueKey('defaults-program-band')),
      'The Syncopators',
    );
    await tester.pumpAndSettle();

    expect(await repos.settings.get(kDefaultProgramCallerKey), 'Folk Process');
    expect(await repos.settings.get(kDefaultProgramBandKey), 'The Syncopators');
  });

  testWidgets('saved caller and band defaults reflect on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultProgramCallerKey, 'Grace Hopper');
    await repos.settings.set(kDefaultProgramBandKey, 'The Debuggers');

    await _pumpDefaults(tester, repos);

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-program-caller')),
          )
          .controller
          ?.text,
      'Grace Hopper',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-program-band')),
          )
          .controller
          ?.text,
      'The Debuggers',
    );
  });

  testWidgets('Dance-authoring subsection renders all four controls', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));

    expect(find.text('Dance-authoring defaults'), findsOneWidget);
    expect(find.byKey(const ValueKey('defaults-dance-form')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('defaults-dance-formation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('defaults-dance-progression')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('defaults-dance-phrase')), findsOneWidget);
  });

  testWidgets('Dance-authoring controls show historical defaults when unset', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));

    expect(
      tester
          .widget<DropdownButton<DanceForm>>(
            find.byKey(const ValueKey('defaults-dance-form')),
          )
          .value,
      DanceForm.contra,
    );
    expect(
      tester
          .widget<DropdownButton<FormationShape>>(
            find.byKey(const ValueKey('defaults-dance-formation')),
          )
          .value,
      FormationShape.dupleImproper,
    );
    expect(
      tester
          .widget<DropdownButton<Progression>>(
            find.byKey(const ValueKey('defaults-dance-progression')),
          )
          .value,
      Progression.single,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-dance-phrase')),
          )
          .controller
          ?.text,
      '',
    );
  });

  testWidgets('changing each Dance-authoring control persists it', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);

    await _scrollTo(tester, const ValueKey('defaults-dance-form'));
    await tester.tap(find.byKey(const ValueKey('defaults-dance-form')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-formation'));
    await tester.tap(find.byKey(const ValueKey('defaults-dance-formation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Becket (CW)').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-progression'));
    await tester.tap(find.byKey(const ValueKey('defaults-dance-progression')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Double').last);
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));
    await tester.enterText(
      find.byKey(const ValueKey('defaults-dance-phrase')),
      '6*8*2',
    );
    await tester.pumpAndSettle();

    expect(
      await repos.settings.get(kDefaultDanceFormKey),
      DanceForm.square.name,
    );
    expect(
      await repos.settings.get(kDefaultDanceFormationShapeKey),
      FormationShape.becketCw.name,
    );
    expect(
      await repos.settings.get(kDefaultDanceProgressionKey),
      Progression.double.name,
    );
    expect(await repos.settings.get(kDefaultDancePhraseStructureKey), '6*8*2');
  });

  testWidgets('saved Dance-authoring defaults reflect on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kDefaultDanceFormKey, DanceForm.ecd.name);
    await repos.settings.set(
      kDefaultDanceFormationShapeKey,
      FormationShape.longways.name,
    );
    await repos.settings.set(
      kDefaultDanceProgressionKey,
      Progression.none.name,
    );
    await repos.settings.set(kDefaultDancePhraseStructureKey, '8*8*1');

    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));

    expect(
      tester
          .widget<DropdownButton<DanceForm>>(
            find.byKey(const ValueKey('defaults-dance-form')),
          )
          .value,
      DanceForm.ecd,
    );
    expect(
      tester
          .widget<DropdownButton<FormationShape>>(
            find.byKey(const ValueKey('defaults-dance-formation')),
          )
          .value,
      FormationShape.longways,
    );
    expect(
      tester
          .widget<DropdownButton<Progression>>(
            find.byKey(const ValueKey('defaults-dance-progression')),
          )
          .value,
      Progression.none,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('defaults-dance-phrase')),
          )
          .controller
          ?.text,
      '8*8*1',
    );
  });

  testWidgets('Starting-figures editor renders with the default template', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    expect(find.text('Starting figures'), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-add')), findsOneWidget);
    // The pre-seeded default is eight stand_still figures.
    for (var i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey('figure-$i-summary')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('figure-8-summary')), findsNothing);
  });

  testWidgets(
    'Meanwhile defaults are ordinary side figures and persist blank',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      expect(find.text('Meanwhile defaults'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('meanwhile-side-0-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('meanwhile-side-1-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('meanwhile-side-beats-total')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('meanwhile-side-add')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('meanwhile-side-0-menu')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('meanwhile-side-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('meanwhile-side-0-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('meanwhile-side-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('meanwhile-side-0-delete')));
      await tester.pumpAndSettle();

      expect(await repos.settings.get(kDefaultMeanwhileSideFiguresKey), '[]');
      expect(find.byKey(const ValueKey('meanwhile-side-add')), findsOneWidget);
    },
  );

  testWidgets('Meanwhile defaults hide insertion controls at six sides', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('meanwhile-side-add')));
      await tester.pumpAndSettle();
    }

    expect(
      find.byKey(const ValueKey('meanwhile-side-5-summary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('meanwhile-side-add')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('meanwhile-side-0-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('meanwhile-side-0-duplicate')),
      findsNothing,
    );
  });

  testWidgets('Meanwhile free-text composer closes when reaching six sides', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(kFreeTextEntryKey, true);
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('meanwhile-side-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('meanwhile-side-free-text-field')),
      'circle left 3/4; turn alone; circle left 3/4; turn alone',
    );
    await tester.tap(
      find.byKey(const ValueKey('meanwhile-side-free-text-submit')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('meanwhile-side-5-summary')),
      findsOneWidget,
    );
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      startsWith('figure-row-'),
    );
    expect(tester.binding.focusManager.primaryFocus?.context, isNotNull);
    expect(
      find.byKey(const ValueKey('meanwhile-side-free-text-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('meanwhile-side-add')), findsNothing);
  });

  testWidgets('Starting figures can add a meanwhile template', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('figure-add-meanwhile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('figure-8-add-side')), findsOneWidget);
    expect(
      danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      ),
      hasLength(8),
    );
  });

  testWidgets('editing the template figure persists it', (tester) async {
    final repos = openTestRepositories();
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('figure-0-summary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('figure-0-beats')), '16');
    await tester.pumpAndSettle();

    final stored = danceFiguresTemplateFromStored(
      await repos.settings.get(kDefaultDanceFiguresTemplateKey),
    );
    // The editor persists the full edited list: eight figures, the first with
    // the edited beats (16) and the remaining seven at the default (8).
    expect(stored, hasLength(8));
    expect(stored.first.move, 'stand_still');
    expect(stored.first.params['beats'], 16);
    for (final figure in stored.skip(1)) {
      expect(figure.move, 'stand_still');
      expect(figure.params['beats'], 8);
    }
  });

  testWidgets(
    'deleting template figures persists the shortened/empty template',
    (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      // Delete one of the eight seeded figures: the shortened list persists.
      await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
      await tester.pumpAndSettle();

      final afterOne = danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      );
      expect(afterOne, hasLength(7));

      // Delete the remaining seven (indices shift down, so always target 0).
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
        await tester.pumpAndSettle();
      }

      // An emptied template persists as an intentional '[]', not the default.
      expect(await repos.settings.get(kDefaultDanceFiguresTemplateKey), '[]');
      expect(find.byKey(const ValueKey('figure-0-summary')), findsNothing);
    },
  );

  testWidgets('a saved multi-figure template reflects on reload', (
    tester,
  ) async {
    final repos = openTestRepositories();
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures([
        Figure(move: 'balance', params: const {'who': 'neighbors', 'beats': 4}),
        Figure(move: 'swing', params: const {'who': 'neighbors', 'beats': 12}),
      ]),
    );
    await _pumpDefaults(tester, repos);
    await tester.binding.setSurfaceSize(const Size(1200, 4500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-2-summary')), findsNothing);
  });

  testWidgets(
    'duplicating a template figure preserves the assumed-subject marker (#460)',
    (tester) async {
      final repos = openTestRepositories();
      // Seed a template whose single figure carries the non-authoritative
      // assumed-subject marker (as an import would produce).
      await repos.settings.set(
        kDefaultDanceFiguresTemplateKey,
        encodeFigures([
          Figure(
            move: 'allemande',
            params: const {'who': 'neighbors', 'hand': 'left', 'beats': 8},
            assumedSubject: true,
          ),
        ]),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-0-duplicate')));
      await tester.pumpAndSettle();

      final stored = danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      );
      // The clone is inserted after the source and the persisted template keeps
      // the marker on BOTH figures (the #460 regression dropped it on the copy).
      expect(stored, hasLength(2));
      expect(stored.every((f) => f.move == 'allemande'), isTrue);
      expect(stored.every((f) => f.assumedSubject), isTrue);
    },
  );

  group('Move defaults (DD.3)', () {
    testWidgets('editor renders with an add affordance', (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      expect(find.text('Move defaults'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-defaults-add')), findsOneWidget);
    });

    testWidgets('adding a move and setting a param persists an override', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('move-defaults-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('move-defaults-add-picker-input')),
        'circle',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('move-defaults-add-picker-option-circle')),
      );
      await tester.pumpAndSettle();

      // The move card renders; change its beats away from the default (8).
      expect(
        find.byKey(const ValueKey('move-default-card-circle')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('move-default-circle-beats')),
        '12',
      );
      await tester.pumpAndSettle();

      final stored = moveParamOverridesFromStored(
        await repos.settings.get(kDefaultMoveParamOverridesKey),
      );
      expect(stored, {
        'circle': {'beats': 12},
      });
    });

    testWidgets('facing star labels its who override backing up', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultMoveParamOverridesKey,
        encodeMoveParamOverrides({
          'facing_star': {'who': 'partners'},
        }),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      expect(find.text('backing up'), findsOneWidget);
    });

    testWidgets('resetting a param to its default drops it from storage', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultMoveParamOverridesKey,
        encodeMoveParamOverrides({
          'circle': {'beats': 12},
        }),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      // The saved override renders its card on reload; reset beats to 8.
      expect(
        find.byKey(const ValueKey('move-default-card-circle')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('move-default-circle-beats')),
        '8',
      );
      await tester.pumpAndSettle();

      expect(
        moveParamOverridesFromStored(
          await repos.settings.get(kDefaultMoveParamOverridesKey),
        ),
        isEmpty,
      );
    });

    testWidgets('removing a move override persists and hides its card', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultMoveParamOverridesKey,
        encodeMoveParamOverrides({
          'circle': {'beats': 12},
        }),
      );
      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('move-default-remove-circle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('move-default-card-circle')),
        findsNothing,
      );
      expect(
        moveParamOverridesFromStored(
          await repos.settings.get(kDefaultMoveParamOverridesKey),
        ),
        isEmpty,
      );
    });
  });

  group('Starting figures free-text entry (#419)', () {
    testWidgets('when on, the template editor Add opens a free-text field', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kFreeTextEntryKey, true);
      // Start from an empty template so the Add button is unambiguous.
      await repos.settings.set(kDefaultDanceFiguresTemplateKey, '[]');

      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('figure-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('figure-add-figure')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('figure-free-text-field')),
        findsOneWidget,
      );

      // Typing a recognised line inserts a structured figure into the template.
      await tester.enterText(
        find.byKey(const ValueKey('figure-free-text-field')),
        'Neighbor swing',
      );
      await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
      await tester.pumpAndSettle();

      final stored = danceFiguresTemplateFromStored(
        await repos.settings.get(kDefaultDanceFiguresTemplateKey),
      );
      expect(stored, hasLength(1));
      expect(stored.single.move, 'swing');
    });

    testWidgets('Modifier defaults honor free-text entry and persist figures', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await repos.settings.set(kFreeTextEntryKey, true);
      await repos.settings.set(kDefaultModifierFiguresKey, '[]');

      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('modifier-default-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('modifier-default-free-text-field')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('modifier-default-free-text-field')),
        'Neighbor swing',
      );
      await tester.tap(
        find.byKey(const ValueKey('modifier-default-free-text-submit')),
      );
      await tester.pumpAndSettle();

      expect(
        modifierFiguresFromStored(
          await repos.settings.get(kDefaultModifierFiguresKey),
        ),
        hasLength(1),
      );
    });

    testWidgets(
      'Modifier defaults preserve an empty template when its core is blank',
      (tester) async {
        final repos = openTestRepositories();
        await repos.settings.set(kDefaultModifierFiguresKey, '[]');

        await _pumpDefaults(tester, repos);
        await tester.binding.setSurfaceSize(const Size(1200, 4500));
        await tester.pumpAndSettle();
        await _scrollTo(tester, const ValueKey('modifier-default-add'));

        await tester.tap(find.byKey(const ValueKey('modifier-default-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('modifier-default-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('figure-1-move-input')),
          'roll away',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(await repos.settings.get(kDefaultModifierFiguresKey), '[]');
      },
    );
  });

  testWidgets(
    'Dance-authoring defaults render in the documented order (#942)',
    (tester) async {
      // Regression guard for #942: two feature PRs (#705, #567) each inserted
      // a new tile near the top of this subsection instead of at its
      // documented position (docs/user/settings.md:388-422), splitting
      // Free-text entry from Figure shorthands. This asserts the whole
      // subsection's rendered vertical order, not just that one adjacency.
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      // Tall enough for every tile plus the two embedded editors to lay out
      // without needing mid-test scrolling (precedent: the Move-defaults
      // group already uses 1200x4500 at line 747).
      await tester.binding.setSurfaceSize(const Size(1200, 5000));
      await tester.pumpAndSettle();

      const orderedKeys = [
        ValueKey('defaults-dance-form'),
        ValueKey('defaults-dance-formation'),
        ValueKey('defaults-dance-progression'),
        ValueKey('defaults-dance-phrase'),
        ValueKey('figure-add'), // Starting figures editor
        ValueKey('move-defaults-add'), // Move defaults editor
        ValueKey('defaults-aggressive-beats-update'),
      ];

      final tops = [
        for (final key in orderedKeys) tester.getTopLeft(find.byKey(key)).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason:
              '${orderedKeys[i].value} should render below '
              '${orderedKeys[i - 1].value}',
        );
      }
    },
  );

  group('Aggressive beats update toggle (#689)', () {
    const toggleKey = ValueKey('defaults-aggressive-beats-update');

    testWidgets('renders in the Dance-authoring section, off by default', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await _scrollTo(tester, toggleKey);

      expect(
        tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
        isFalse,
      );
    });

    testWidgets('toggling it on persists the preference', (tester) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos);
      await _scrollTo(tester, toggleKey);

      await tester.tap(find.byKey(toggleKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
        isTrue,
      );
      expect(await repos.settings.get(kAggressiveBeatsUpdateKey), isTrue);
    });

    testWidgets('a saved preference reflects on reload', (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(kAggressiveBeatsUpdateKey, true);

      await _pumpDefaults(tester, repos);
      await _scrollTo(tester, toggleKey);

      expect(
        tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
        isTrue,
      );
    });

    testWidgets(
      'a corrupt (non-bool) stored value falls back to off, never crashes',
      (tester) async {
        final repos = openTestRepositories();
        // Simulate a corrupted/foreign-typed stored value (OWASP: never trust
        // stored input without validation).
        await repos.settings.set(kAggressiveBeatsUpdateKey, 'not-a-bool');

        await _pumpDefaults(tester, repos);
        await _scrollTo(tester, toggleKey);

        expect(
          tester.widget<SwitchListTile>(find.byKey(toggleKey)).value,
          isFalse,
        );
      },
    );
  });

  group('Collection filters visibility (#1419)', () {
    Key box(String id) => ValueKey('defaults-facet-$id');
    bool ticked(WidgetTester tester, Key key) =>
        tester.widget<CheckboxListTile>(find.byKey(key)).value ?? false;

    testWidgets('offers one checkbox per built-in filter, all ticked', (
      tester,
    ) async {
      final repos = openTestRepositories();
      await _pumpDefaults(tester, repos, expandGroups: false);

      for (final id in CollectionFacetIds.builtIns) {
        await _scrollTo(tester, box(id));
        expect(ticked(tester, box(id)), isTrue, reason: id);
      }
    });

    testWidgets('unticking hides the filter live and persists the hidden id', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final hidden = ValueNotifier<Set<String>>(const {});
      addTearDown(hidden.dispose);
      await _pumpDefaults(
        tester,
        repos,
        expandGroups: false,
        hiddenFacets: hidden,
      );

      await _scrollTo(tester, box(CollectionFacetIds.status));
      await tester.tap(find.byKey(box(CollectionFacetIds.status)));
      await tester.pumpAndSettle();

      expect(hidden.value, {CollectionFacetIds.status});
      expect(ticked(tester, box(CollectionFacetIds.status)), isFalse);
      expect(await repos.settings.get(kCollectionHiddenFacetsKey), [
        CollectionFacetIds.status,
      ]);

      // Ticking it again shows it and stores an empty list, not a stale id.
      await tester.tap(find.byKey(box(CollectionFacetIds.status)));
      await tester.pumpAndSettle();
      expect(hidden.value, isEmpty);
      expect(await repos.settings.get(kCollectionHiddenFacetsKey), isEmpty);
    });

    testWidgets('two taps before a rebuild both take effect', (tester) async {
      final repos = openTestRepositories();
      final hidden = ValueNotifier<Set<String>>(const {});
      addTearDown(hidden.dispose);
      await _pumpDefaults(
        tester,
        repos,
        expandGroups: false,
        hiddenFacets: hidden,
      );
      await _scrollTo(tester, box(CollectionFacetIds.tags));
      await _scrollTo(tester, box(CollectionFacetIds.status));

      // No pump between the taps: the second must build on the notifier's
      // current value, not on the build-time snapshot the first also saw.
      await tester.tap(find.byKey(box(CollectionFacetIds.status)));
      await tester.tap(find.byKey(box(CollectionFacetIds.tags)));
      await tester.pumpAndSettle();

      expect(hidden.value, {
        CollectionFacetIds.status,
        CollectionFacetIds.tags,
      });
      expect(await repos.settings.get(kCollectionHiddenFacetsKey), [
        CollectionFacetIds.status,
        CollectionFacetIds.tags,
      ]);
    });

    testWidgets('a filter hidden before the screen opens shows unticked', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final hidden = ValueNotifier<Set<String>>({CollectionFacetIds.author});
      addTearDown(hidden.dispose);
      await _pumpDefaults(
        tester,
        repos,
        expandGroups: false,
        hiddenFacets: hidden,
      );

      await _scrollTo(tester, box(CollectionFacetIds.author));
      expect(ticked(tester, box(CollectionFacetIds.author)), isFalse);
      await _scrollTo(tester, box(CollectionFacetIds.tags));
      expect(ticked(tester, box(CollectionFacetIds.tags)), isTrue);
    });

    testWidgets('each searchable custom field gets its own checkbox, by id', (
      tester,
    ) async {
      final repos = openTestRepositories();
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f1',
          key: 'region_a',
          label: 'Region',
          type: CustomFieldType.choice,
          choices: const ['north'],
        ),
      );
      // Same label: the checkboxes must still be told apart by id.
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f2',
          key: 'region_b',
          label: 'Region',
          type: CustomFieldType.text,
        ),
      );
      // Not searchable, so the Filters panel has no section for it either.
      // ignore: unused_result
      await repos.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f3',
          key: 'private_note',
          label: 'Private note',
          type: CustomFieldType.text,
          searchable: false,
        ),
      );
      final hidden = ValueNotifier<Set<String>>(const {});
      addTearDown(hidden.dispose);
      await _pumpDefaults(
        tester,
        repos,
        expandGroups: false,
        hiddenFacets: hidden,
      );

      await _scrollTo(tester, box('cf-f1'));
      expect(find.byKey(box('cf-f2')), findsOneWidget);
      expect(find.byKey(box('cf-f3')), findsNothing);

      await tester.tap(find.byKey(box('cf-f2')));
      await tester.pumpAndSettle();

      // Only the second "Region" is hidden, under its type-agnostic id.
      expect(hidden.value, {customFieldFacetId('f2')});
      expect(ticked(tester, box('cf-f1')), isTrue);
      expect(ticked(tester, box('cf-f2')), isFalse);
      expect(await repos.settings.get(kCollectionHiddenFacetsKey), ['cf:f2']);
    });
  });

  group('late settings reads never clobber a user edit', () {
    // Each case: the key whose read is held open, the stored value it will
    // eventually resolve with, the user's edit made while it is held, and the
    // expectation that the edit survived the late read.
    final cases =
        <
          ({
            String name,
            String key,
            Object stored,
            Future<void> Function(WidgetTester) edit,
            void Function(WidgetTester) expectEdited,
          })
        >[
          (
            name: 'default collection sort',
            key: kDefaultCollectionSortKey,
            stored: CollectionSort.lastCalled.name,
            edit: (tester) async {
              await tester.tap(
                find.byKey(const ValueKey('defaults-collection-sort')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Author').last);
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
                    find.byKey(const ValueKey('defaults-collection-sort')),
                  )
                  .value,
              const SortDefaultSetting.concrete(CollectionSort.author),
            ),
          ),
          (
            name: 'default program sort',
            key: kDefaultProgramSortKey,
            stored: ProgramSort.recentlyUpdated.name,
            edit: (tester) async {
              await tester.tap(
                find.byKey(const ValueKey('defaults-program-sort')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Event date').last);
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
                    find.byKey(const ValueKey('defaults-program-sort')),
                  )
                  .value,
              const SortDefaultSetting.concrete(ProgramSort.eventDate),
            ),
          ),
          (
            name: 'default caller',
            key: kDefaultProgramCallerKey,
            stored: 'Stored caller',
            edit: (tester) async {
              await tester.enterText(
                find.byKey(const ValueKey('defaults-program-caller')),
                'Typed caller',
              );
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('defaults-program-caller')),
                  )
                  .controller
                  ?.text,
              'Typed caller',
            ),
          ),
          (
            name: 'default band',
            key: kDefaultProgramBandKey,
            stored: 'Stored band',
            edit: (tester) async {
              await tester.enterText(
                find.byKey(const ValueKey('defaults-program-band')),
                'Typed band',
              );
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('defaults-program-band')),
                  )
                  .controller
                  ?.text,
              'Typed band',
            ),
          ),
          (
            name: 'default dance form',
            key: kDefaultDanceFormKey,
            stored: DanceForm.ecd.name,
            edit: (tester) async {
              await _scrollTo(tester, const ValueKey('defaults-dance-form'));
              await tester.tap(
                find.byKey(const ValueKey('defaults-dance-form')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Square').last);
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<DropdownButton<DanceForm>>(
                    find.byKey(const ValueKey('defaults-dance-form')),
                  )
                  .value,
              DanceForm.square,
            ),
          ),
          (
            name: 'default formation shape',
            key: kDefaultDanceFormationShapeKey,
            stored: FormationShape.longways.name,
            edit: (tester) async {
              await _scrollTo(
                tester,
                const ValueKey('defaults-dance-formation'),
              );
              await tester.tap(
                find.byKey(const ValueKey('defaults-dance-formation')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Becket (CW)').last);
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<DropdownButton<FormationShape>>(
                    find.byKey(const ValueKey('defaults-dance-formation')),
                  )
                  .value,
              FormationShape.becketCw,
            ),
          ),
          (
            name: 'default progression',
            key: kDefaultDanceProgressionKey,
            stored: Progression.none.name,
            edit: (tester) async {
              await _scrollTo(
                tester,
                const ValueKey('defaults-dance-progression'),
              );
              await tester.tap(
                find.byKey(const ValueKey('defaults-dance-progression')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Double').last);
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<DropdownButton<Progression>>(
                    find.byKey(const ValueKey('defaults-dance-progression')),
                  )
                  .value,
              Progression.double,
            ),
          ),
          (
            name: 'default phrase structure',
            key: kDefaultDancePhraseStructureKey,
            stored: '8*8*1',
            edit: (tester) async {
              await _scrollTo(tester, const ValueKey('defaults-dance-phrase'));
              await tester.enterText(
                find.byKey(const ValueKey('defaults-dance-phrase')),
                '6*8*2',
              );
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('defaults-dance-phrase')),
                  )
                  .controller
                  ?.text,
              '6*8*2',
            ),
          ),
          (
            name: 'starting-figures template',
            key: kDefaultDanceFiguresTemplateKey,
            stored: encodeFigures([
              Figure(move: 'stand_still', params: const {'beats': 16}),
            ]),
            edit: (tester) async {
              await tester.tap(find.byKey(const ValueKey('figure-0-menu')));
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('figure-0-delete')));
              await tester.pumpAndSettle();
            },
            // Eight seeded figures minus the deleted one; the late read would
            // have replaced them with the single stored figure.
            expectEdited: (tester) {
              expect(
                find.byKey(const ValueKey('figure-6-summary')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('figure-7-summary')),
                findsNothing,
              );
            },
          ),
          (
            name: 'meanwhile side figures',
            key: kDefaultMeanwhileSideFiguresKey,
            stored: '[]',
            edit: (tester) async {
              await tester.tap(
                find.byKey(const ValueKey('meanwhile-side-add')),
              );
              await tester.pumpAndSettle();
            },
            // Two seeded sides plus the added one; the late read would have
            // replaced them with the stored empty list.
            expectEdited: (tester) => expect(
              find.byKey(const ValueKey('meanwhile-side-2-summary')),
              findsOneWidget,
            ),
          ),
          (
            name: 'modifier figures',
            key: kDefaultModifierFiguresKey,
            stored: '[]',
            edit: (tester) async {
              await _scrollTo(tester, const ValueKey('modifier-default-add'));
              await tester.tap(
                find.byKey(const ValueKey('modifier-default-add')),
              );
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) => expect(
              find.byKey(const ValueKey('modifier-default-2-summary')),
              findsOneWidget,
            ),
          ),
          (
            name: 'move param overrides',
            key: kDefaultMoveParamOverridesKey,
            stored: encodeMoveParamOverrides({
              'swing': {'beats': 4},
            }),
            edit: (tester) async {
              await tester.tap(find.byKey(const ValueKey('move-defaults-add')));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const ValueKey('move-defaults-add-picker-input')),
                'circle',
              );
              await tester.pumpAndSettle();
              await tester.tap(
                find.byKey(
                  const ValueKey('move-defaults-add-picker-option-circle'),
                ),
              );
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const ValueKey('move-default-circle-beats')),
                '12',
              );
              await tester.pumpAndSettle();
            },
            // The stored override map names `swing`; the late read must not
            // surface it over the user's own `circle` edit.
            expectEdited: (tester) {
              expect(
                find.byKey(const ValueKey('move-default-card-circle')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('move-default-card-swing')),
                findsNothing,
              );
            },
          ),
          (
            name: 'starting-program template',
            key: kDefaultStartingProgramKey,
            stored: encodeStartingProgramTemplate([
              const StartingProgramTemplateEntry(text: 'Stored note'),
            ]),
            edit: (tester) async {
              await tester.tap(
                find.byKey(const ValueKey('starting-program-insert-break')),
              );
              await tester.pumpAndSettle();
            },
            expectEdited: (tester) {
              expect(find.text(Program.breakSlotText), findsOneWidget);
              expect(find.text('Stored note'), findsNothing);
            },
          ),
        ];

    for (final c in cases) {
      testWidgets('${c.name}: an edit made before the read resolves wins', (
        tester,
      ) async {
        final db = openWidgetTestDatabase();
        final settings = _GatedSettings(db);
        final repos = CompendiumRepositories(
          db,
          contraTaxonomy,
          settings: settings,
        );
        await settings.set(c.key, c.stored);
        final gate = settings.hold(c.key);
        // A resolved gate must never leave the read hanging past the test.
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });

        await _pumpDefaults(tester, repos);
        await tester.binding.setSurfaceSize(const Size(1200, 4500));
        await tester.pumpAndSettle();

        await c.edit(tester);
        gate.complete();
        await tester.pumpAndSettle();

        c.expectEdited(tester);
      });
    }
  });

  testWidgets(
    'every failed settings read falls back to the historical default',
    (tester) async {
      final db = openWidgetTestDatabase();
      final repos = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: _ThrowingReadSettings(
          db,
          throwFor: {
            kDefaultCollectionSortKey,
            kDefaultProgramSortKey,
            kDefaultProgramCallerKey,
            kDefaultProgramBandKey,
            kDefaultDanceFormKey,
            kDefaultDanceFormationShapeKey,
            kDefaultDanceProgressionKey,
            kDefaultDancePhraseStructureKey,
            kDefaultDanceFiguresTemplateKey,
            kDefaultMeanwhileSideFiguresKey,
            kDefaultModifierFiguresKey,
            kDefaultMoveParamOverridesKey,
            kFreeTextEntryKey,
            kDefaultStartingProgramKey,
          },
        ),
      );

      await _pumpDefaults(tester, repos);
      await tester.binding.setSurfaceSize(const Size(1200, 4500));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButton<SortDefaultSetting<CollectionSort>>>(
              find.byKey(const ValueKey('defaults-collection-sort')),
            )
            .value,
        const SortDefaultSetting.concrete(CollectionSort.title),
      );
      expect(
        tester
            .widget<DropdownButton<SortDefaultSetting<ProgramSort>>>(
              find.byKey(const ValueKey('defaults-program-sort')),
            )
            .value,
        const SortDefaultSetting.concrete(ProgramSort.title),
      );
      await _scrollTo(tester, const ValueKey('defaults-dance-form'));
      expect(
        tester
            .widget<DropdownButton<DanceForm>>(
              find.byKey(const ValueKey('defaults-dance-form')),
            )
            .value,
        DanceForm.contra,
      );
      expect(
        tester
            .widget<DropdownButton<FormationShape>>(
              find.byKey(const ValueKey('defaults-dance-formation')),
            )
            .value,
        FormationShape.dupleImproper,
      );
      expect(
        tester
            .widget<DropdownButton<Progression>>(
              find.byKey(const ValueKey('defaults-dance-progression')),
            )
            .value,
        Progression.single,
      );
      // The pre-seeded templates survive a failed read.
      expect(find.byKey(const ValueKey('figure-7-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('figure-8-summary')), findsNothing);
      expect(
        find.byKey(const ValueKey('meanwhile-side-1-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('meanwhile-side-2-summary')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('modifier-default-1-summary')),
        findsOneWidget,
      );
    },
  );

  group('starting-program dance titles and the full collection load', () {
    late _RecordingCrashLogSink sink;

    setUp(() {
      sink = _RecordingCrashLogSink();
      installCaughtErrorLog(sink);
      addTearDown(resetCaughtErrorLogForTesting);
    });

    Future<({CompendiumRepositories repos, _CountingDances dances})> open({
      bool failTitles = false,
      bool failFullLoad = false,
    }) async {
      final db = openWidgetTestDatabase();
      final dances = _CountingDances(db)
        ..failTitles = failTitles
        ..failFullLoad = failFullLoad;
      final repos = CompendiumRepositories(db, contraTaxonomy, dances: dances);
      await repos.dances.create(_dance(id: 'd1', title: 'First dance'));
      await repos.settings.set(
        kDefaultStartingProgramKey,
        encodeStartingProgramTemplate([
          const StartingProgramTemplateEntry(danceId: 'd1'),
        ]),
      );
      dances.fullLoads = 0;
      dances.titleLoads = 0;
      return (repos: repos, dances: dances);
    }

    Future<void> rebuildThrice(WidgetTester tester) async {
      // Each break insertion calls the section's setState, i.e. rebuilds it.
      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.byKey(const ValueKey('starting-program-insert-break')),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a failing titles load is logged once across rebuilds', (
      tester,
    ) async {
      final opened = await open(failTitles: true);
      await _pumpDefaults(tester, opened.repos);
      await rebuildThrice(tester);

      expect(
        sink.sources.where(
          (s) => s == 'defaults_section.starting_program_titles',
        ),
        hasLength(1),
      );
      expect(opened.dances.titleLoads, 1);
    });

    testWidgets('the starting-program list shows titles without loading the '
        'collection', (tester) async {
      final opened = await open(failFullLoad: true);
      await _pumpDefaults(tester, opened.repos);

      expect(find.text('First dance'), findsOneWidget);
      expect(opened.dances.fullLoads, 0);
      expect(sink.sources, isEmpty);
    });

    testWidgets('rebuilding never loads the full collection', (tester) async {
      final opened = await open();
      await _pumpDefaults(tester, opened.repos);
      await rebuildThrice(tester);

      expect(opened.dances.fullLoads, 0);
      expect(opened.dances.titleLoads, 1);
    });

    testWidgets('opening the dance picker loads the full collection once', (
      tester,
    ) async {
      final opened = await open();
      await _pumpDefaults(tester, opened.repos);
      await tester.tap(
        find.byKey(const ValueKey('starting-program-add-dance')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CollectionPicker), findsOneWidget);
      expect(opened.dances.fullLoads, 1);
    });

    testWidgets('a failed picker load is logged per tap and retried on the '
        'next tap', (tester) async {
      final opened = await open(failFullLoad: true);
      await _pumpDefaults(tester, opened.repos);
      final add = find.byKey(const ValueKey('starting-program-add-dance'));

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionPicker), findsNothing);
      expect(
        sink.sources.where(
          (s) => s == 'defaults_section.starting_program_picker',
        ),
        hasLength(1),
      );

      opened.dances.failFullLoad = false;
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionPicker), findsOneWidget);
      expect(opened.dances.fullLoads, 2);
    });
  });
}
