import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/diagnostics/crash_reporter.dart';
import 'package:compendium_app/src/diagnostics/error_log.dart';
import 'package:compendium_app/src/screens/settings/program_templates_screen.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/pump_until.dart';
import 'support/test_repositories.dart';

/// Counts and optionally fails the two dance reads the template editor
/// makes: the titles-only projection and the full load behind
/// `CollectionData`.
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

final _now = DateTime.utc(2026, 1, 1);

Dance _dance(String id, String title) =>
    Dance(id: id, title: title, createdAt: _now, updatedAt: _now);

Future<void> _pump(
  WidgetTester tester,
  CompendiumRepositories repos,
  Widget home,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final confirm = ValueNotifier<bool>(false);
  addTearDown(confirm.dispose);
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ConfirmBeforeDeleteScope(
          notifier: confirm,
          child: ActiveDialectScope(notifier: dialect, child: child!),
        ),
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<ProgramTemplates> _stored(CompendiumRepositories repos) =>
    loadProgramTemplates(repos.settings);

Future<void> _seed(
  CompendiumRepositories repos,
  List<ProgramTemplate> templates,
) async {
  for (final template in templates) {
    await saveProgramTemplate(repos.settings, template);
  }
  await saveProgramTemplateOrder(repos.settings, [
    for (final t in templates) t.id,
  ]);
}

void main() {
  group('the template manager', () {
    testWidgets('an empty manager offers New template, which names a '
        'template, saves it and opens its editor', (tester) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, const ProgramTemplatesScreen());

      expect(
        find.byKey(const ValueKey('program-templates-empty')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('program-templates-add')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('program-templates-empty-add')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-name-field')),
        'Family dance',
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-name-save')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProgramTemplateEditorScreen), findsOneWidget);
      final stored = await _stored(repos);
      expect([for (final t in stored.templates) t.name], ['Family dance']);
      // With one template there is no chooser, so the first one becomes the
      // default: otherwise New program could never reach it.
      expect(stored.defaultId, stored.templates.single.id);
    });

    testWidgets('the Starting program shows by its localized name before and '
        'after it is copied, and opens with that name', (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set(
        kDefaultStartingProgramKey,
        encodeStartingProgramTemplate(const [
          ProgramTemplateEntry(text: 'Opener'),
        ]),
      );
      await _pump(tester, repos, const ProgramTemplatesScreen());
      final tile = find.byKey(
        ValueKey('program-template-tile-$kMigratedStartingProgramTemplateId'),
      );
      expect(
        find.descendant(of: tile, matching: find.text('Starting program')),
        findsOneWidget,
      );
      // Showing it wrote nothing.
      expect(await repos.settings.contains(kProgramTemplateOrderKey), isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('program-template-editor-name')),
      );
      expect(field.controller!.text, 'Starting program');
    });

    testWidgets('the name field holds the name to the stored limit in '
        'UTF-16 units, so 60 emoji are not let through', (tester) async {
      final repos = openTestRepositories();
      await _pump(tester, repos, const ProgramTemplatesScreen());
      await tester.tap(
        find.byKey(const ValueKey('program-templates-empty-add')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-name-field')),
        '\u{1F3BB}' * 60,
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('program-template-name-field')),
      );
      expect(field.controller!.text, '\u{1F3BB}' * 50);
    });

    testWidgets('a new template leaves an explicit Blank program default '
        'alone', (tester) async {
      final repos = openTestRepositories();
      await saveProgramTemplateDefault(repos.settings, null);
      await _pump(tester, repos, const ProgramTemplatesScreen());

      await tester.tap(
        find.byKey(const ValueKey('program-templates-empty-add')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-name-field')),
        'Family dance',
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-name-save')),
      );
      await tester.pumpAndSettle();

      final stored = await _stored(repos);
      expect(stored.templates, hasLength(1));
      expect(stored.defaultId, isNull);
    });

    testWidgets('a failed save says so and does not open the editor', (
      tester,
    ) async {
      final sink = _RecordingCrashLogSink();
      installCaughtErrorLog(sink);
      addTearDown(resetCaughtErrorLogForTesting);
      final db = openWidgetTestDatabase();
      final settings = FailingSettingsRepository(db);
      final repos = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: settings,
      );
      await _pump(tester, repos, const ProgramTemplatesScreen());

      await tester.tap(
        find.byKey(const ValueKey('program-templates-empty-add')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-name-field')),
        'Family dance',
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-name-save')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProgramTemplateEditorScreen), findsNothing);
      expect(
        find.text("Couldn't save that change to your templates. Try again."),
        findsOneWidget,
      );
      expect(sink.sources, ['program_templates_screen.create']);
    });

    testWidgets('at the template cap, New template and Duplicate are '
        'disabled', (tester) async {
      final repos = openTestRepositories();
      await _seed(repos, [
        for (var i = 0; i < kMaxProgramTemplateOrderLength; i++)
          ProgramTemplate(id: 't$i', name: 'Template $i'),
      ]);
      await _pump(tester, repos, const ProgramTemplatesScreen());

      final fab = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('program-templates-add')),
      );
      expect(fab.onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('program-template-menu-t0')));
      await tester.pumpAndSettle();
      final duplicate = tester.widget<PopupMenuItem<Object?>>(
        find.byKey(const ValueKey('program-template-duplicate')),
      );
      expect(duplicate.enabled, isFalse);
    });

    testWidgets('rename, duplicate and reorder', (tester) async {
      final repos = openTestRepositories();
      await _seed(repos, const [
        ProgramTemplate(
          id: 'a',
          name: 'Family',
          entries: [ProgramTemplateEntry(text: 'Waltz')],
        ),
        ProgramTemplate(id: 'b', name: 'Saturday'),
      ]);
      await _pump(tester, repos, const ProgramTemplatesScreen());

      // Rename.
      await tester.tap(find.byKey(const ValueKey('program-template-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-template-rename')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-name-field')),
        'Family night',
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-name-save')),
      );
      await tester.pumpAndSettle();
      expect((await _stored(repos)).byId('a')!.name, 'Family night');

      // Duplicate lands right after the original, with its slots.
      await tester.tap(find.byKey(const ValueKey('program-template-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-duplicate')),
      );
      await tester.pumpAndSettle();
      var stored = await _stored(repos);
      expect(
        [for (final t in stored.templates) t.name],
        ['Family night', 'Family night (copy)', 'Saturday'],
      );
      expect(stored.templates[1].entries, stored.templates[0].entries);
      expect(stored.templates[1].id, isNot('a'));

      // Move down writes the order key.
      await tester.tap(
        find.byKey(const ValueKey('program-template-a-move-down')),
      );
      await tester.pumpAndSettle();
      stored = await _stored(repos);
      expect(
        [for (final t in stored.templates) t.name],
        ['Family night (copy)', 'Family night', 'Saturday'],
      );
    });

    testWidgets('delete removes the template at once, and Undo brings it back '
        'in place and as the default', (tester) async {
      final repos = openTestRepositories();
      await _seed(repos, const [
        ProgramTemplate(id: 'a', name: 'Family'),
        ProgramTemplate(id: 'b', name: 'Saturday'),
      ]);
      await saveProgramTemplateDefault(repos.settings, 'a');
      await _pump(tester, repos, const ProgramTemplatesScreen());

      await tester.tap(find.byKey(const ValueKey('program-template-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('program-template-delete')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('program-template-tile-a')),
        findsNothing,
      );
      expect(await repos.settings.contains(programTemplateKey('a')), isFalse);

      await tester.tap(
        find.byKey(const ValueKey('program-template-delete-undo')),
      );
      await tester.pumpAndSettle();
      final stored = await _stored(repos);
      expect([for (final t in stored.templates) t.id], ['a', 'b']);
      expect(stored.defaultId, 'a');
      expect(
        find.byKey(const ValueKey('program-template-tile-a')),
        findsOneWidget,
      );
    });
  });

  group('the template editor', () {
    testWidgets('notes keep their dance when edited and reordered, and only '
        "the template's own key is written", (tester) async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('d1', 'First dance'));
      await repos.dances.create(_dance('d2', 'Second dance'));
      const template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry(danceId: 'd1'),
          ProgramTemplateEntry(danceId: 'd2'),
        ],
      );
      await _seed(repos, const [template, ProgramTemplate(id: 'b', name: 'B')]);
      final otherBefore = await repos.settings.get(programTemplateKey('b'));

      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      await tester.enterText(find.byType(TextFormField).first, 'Guest caller');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pumpAndSettle();

      final stored = (await _stored(repos)).byId('a')!;
      expect(stored.entries.map((entry) => entry.danceId), ['d2', 'd1']);
      expect(stored.entries.last.text, 'Guest caller');
      expect(await repos.settings.get(programTemplateKey('b')), otherBefore);
    });

    testWidgets('renaming in the editor saves; a blank name keeps the last '
        'one', (tester) async {
      final repos = openTestRepositories();
      const template = ProgramTemplate(id: 'a', name: 'Family');
      await _seed(repos, const [template]);
      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      final name = find.byKey(const ValueKey('program-template-editor-name'));
      await tester.enterText(name, 'Family night');
      await tester.pumpAndSettle();
      expect((await _stored(repos)).byId('a')!.name, 'Family night');
      await tester.enterText(name, '   ');
      await tester.pumpAndSettle();
      expect((await _stored(repos)).byId('a')!.name, 'Family night');
    });

    testWidgets('notes and breaks are added to the end', (tester) async {
      final repos = openTestRepositories();
      const template = ProgramTemplate(id: 'a', name: 'Family');
      await _seed(repos, const [template]);
      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      await tester.enterText(
        find.byKey(const ValueKey('program-template-text-field')),
        'Waltz',
      );
      await tester.tap(find.byKey(const ValueKey('program-template-add-text')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-insert-break')),
      );
      await tester.pumpAndSettle();
      expect((await _stored(repos)).byId('a')!.entries, const [
        ProgramTemplateEntry(text: 'Waltz'),
        ProgramTemplateEntry(text: Program.breakSlotText),
      ]);
    });
  });

  group('slot rules (#2338)', () {
    Future<SavedSearch> saveSearch(CompendiumRepositories repos, String name) =>
        repos.savedSearches.create(
          name: name,
          spec: SavedSearchSpec.fromPanelState(
            CollectionPanelState(text: 'swing'),
            today: DateTime.utc(2026, 11, 22),
          ).value!,
        );

    testWidgets('Add slot rule stores a label and the saved search chosen, '
        'and the row names the search', (tester) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      await saveSearch(repos, 'Other');
      const template = ProgramTemplate(id: 'a', name: 'Family');
      await _seed(repos, const [template]);
      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );

      await tester.tap(find.byKey(const ValueKey('program-template-add-rule')));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('program-template-rule-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('program-template-rule-search-${family.id}')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-rule-label')),
        'Easy family opener',
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect((await _stored(repos)).byId('a')!.entries, [
        ProgramTemplateEntry.rule(
          savedSearchId: family.id,
          label: 'Easy family opener',
        ),
      ]);
      expect(find.text('Easy family opener'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('program-template-rule-subtitle-0')),
        findsOneWidget,
      );
      expect(find.textContaining('Family dances'), findsOneWidget);
    });

    testWidgets('a saved search deleted while the slot rule dialog is open: '
        'the editor says so and goes back to the saved slots (#2529)', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      const template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [ProgramTemplateEntry(text: 'Waltz')],
      );
      await _seed(repos, const [template]);
      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );

      await tester.tap(find.byKey(const ValueKey('program-template-add-rule')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('program-template-rule-search-${family.id}')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-rule-label')),
        'Easy family opener',
      );
      await tester.pumpAndSettle();
      // Deleted elsewhere (the Collection, or a peer by sync) meanwhile.
      await repos.savedSearches.delete(family.id);
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-save')),
      );
      await tester.pumpAndSettle();

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('program-template-slot-rule-search-gone')),
      );
      expect(
        find.text(
          "That saved search was just deleted, so the slot rule wasn't saved.",
        ),
        findsOneWidget,
      );
      await pumpUntil(
        tester,
        () => find.text('Easy family opener').evaluate().isEmpty,
        description: 'the refused slot rule to leave the list',
      );
      expect((await _stored(repos)).byId('a')!.entries, const [
        ProgramTemplateEntry(text: 'Waltz'),
      ]);
      expect(find.text('Waltz'), findsOneWidget);
    });

    testWidgets('without a saved search, Add slot rule says where to make one '
        'and adds nothing', (tester) async {
      final repos = openTestRepositories();
      const template = ProgramTemplate(id: 'a', name: 'Family');
      await _seed(repos, const [template]);
      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      await tester.tap(find.byKey(const ValueKey('program-template-add-rule')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('program-template-rule-no-searches')),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await _stored(repos)).byId('a')!.entries, isEmpty);
    });

    testWidgets('a rule whose saved search is gone says so on its row', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry.rule(
            savedSearchId: 'deleted-search',
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      final subtitle = tester.widget<Text>(
        find.byKey(const ValueKey('program-template-rule-subtitle-0')),
      );
      expect(subtitle.data, 'Its saved search was deleted');
    });

    testWidgets('a screen reader hears "Slot rule" once on a slot rule: from '
        'its icon, or from its subtitle while the saved searches cannot be '
        'read', (tester) async {
      final semantics = tester.ensureSemantics();
      final db = openWidgetTestDatabase();
      final settings = FailingSavedSearchReadsSettings(db);
      final repos = CompendiumRepositories(
        db,
        contraTaxonomy,
        settings: settings,
      );
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry.rule(
            savedSearchId: 'deleted-search',
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);

      /// How many times the slot rule's row says "Slot rule", across every
      /// semantics node in it, merged or not.
      int slotRuleSaid() {
        final row = find.ancestor(
          of: find.byKey(const ValueKey('program-template-rule-subtitle-0')),
          matching: find.byType(ListTile),
        );
        var count = 0;
        void visit(SemanticsNode node) {
          count += RegExp('Slot rule').allMatches(node.label).length;
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(tester.getSemantics(row));
        return count;
      }

      settings.failSearchReads = true;
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('program-template-rule-subtitle-0')),
            )
            .data,
        'Slot rule',
      );
      expect(slotRuleSaid(), 1);
      semantics.dispose();
    });

    testWidgets('with the saved searches read, a slot rule\'s icon still says '
        'what the row is', (tester) async {
      final semantics = tester.ensureSemantics();
      final repos = openTestRepositories();
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry.rule(
            savedSearchId: 'deleted-search',
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      expect(find.bySemanticsLabel(RegExp('Slot rule')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets("a rule whose saved search is stored but unreadable says it "
        "can't be opened, not that it was deleted", (tester) async {
      final repos = openTestRepositories();
      await repos.settings.set('saved_search:newer', {'v': 2, 'name': 'Newer'});
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry.rule(
            savedSearchId: 'newer',
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      final subtitle = tester.widget<Text>(
        find.byKey(const ValueKey('program-template-rule-subtitle-0')),
      );
      expect(subtitle.data, "Its saved search can't be opened");
    });

    testWidgets('Edit changes a rule\'s label and saved search in place', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      final other = await saveSearch(repos, 'Other');
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          const ProgramTemplateEntry(text: 'Waltz'),
          ProgramTemplateEntry.rule(
            savedSearchId: family.id,
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      expect(
        find.byKey(const ValueKey('program-template-rule-edit-0')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-edit-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit slot rule'), findsOneWidget);
      final label = find.byKey(const ValueKey('program-template-rule-label'));
      expect(
        tester.widget<TextField>(label).controller!.text,
        'Easy family opener',
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('program-template-rule-search-${other.id}')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(label, 'Something else');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-save')),
      );
      await tester.pumpAndSettle();

      expect((await _stored(repos)).byId('a')!.entries, [
        const ProgramTemplateEntry(text: 'Waltz'),
        ProgramTemplateEntry.rule(
          savedSearchId: other.id,
          label: 'Something else',
        ),
      ]);
    });

    testWidgets('an Edit to a saved search deleted before it is saved puts the '
        'rule back as it was (#2529)', (tester) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      final other = await saveSearch(repos, 'Other');
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          const ProgramTemplateEntry(text: 'Waltz'),
          ProgramTemplateEntry.rule(
            savedSearchId: family.id,
            label: 'Easy family opener',
          ),
        ],
      );
      // The editor holds a note the stored copy does not have yet (as if
      // added a moment before): undoing the refused rule must keep it.
      await _seed(repos, [
        ProgramTemplate(
          id: 'a',
          name: 'Family',
          entries: [template.entries[1]],
        ),
      ]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );

      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-edit-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('program-template-rule-search-${other.id}')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('program-template-rule-label')),
        'Something else',
      );
      await tester.pumpAndSettle();
      await repos.savedSearches.delete(other.id);
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-save')),
      );
      await tester.pumpAndSettle();

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('program-template-slot-rule-search-gone')),
      );
      await pumpUntilFound(tester, find.text('Easy family opener'));
      expect(find.text('Something else'), findsNothing);
      expect((await _stored(repos)).byId('a')!.entries, template.entries);
    });

    testWidgets('Duplicate of a template whose slot rule names a deleted saved '
        'search is refused, naming the rule (#2529)', (tester) async {
      final repos = openTestRepositories();
      await _seed(repos, [
        ProgramTemplate(
          id: 'a',
          name: 'Family',
          entries: [
            ProgramTemplateEntry.rule(
              savedSearchId: 'deleted-search',
              label: 'Easy family opener',
            ),
          ],
        ),
      ]);
      await _pump(tester, repos, const ProgramTemplatesScreen());

      await tester.tap(find.byKey(const ValueKey('program-template-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-duplicate')),
      );
      await tester.pumpAndSettle();

      await pumpUntilFound(
        tester,
        find.byKey(const ValueKey('program-template-search-gone')),
      );
      expect(
        find.text(
          "Couldn't duplicate: the saved search of the slot rule "
          '"Easy family opener" was deleted. Edit or remove that rule, then '
          'try again.',
        ),
        findsOneWidget,
      );
      expect(
        [for (final t in (await _stored(repos)).templates) t.id],
        ['a'],
        reason: 'no copy, and no order entry for one',
      );
    });

    testWidgets('Edit with no saved search left keeps the edit form: the label '
        'can change, no search is chosen, and a note says why', (tester) async {
      final repos = openTestRepositories();
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry.rule(
            savedSearchId: 'deleted-search',
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-edit-0')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('program-template-rule-no-searches')),
        findsNothing,
      );
      expect(find.text('Edit slot rule'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('program-template-rule-no-searches-note')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('program-template-rule-search')),
        findsNothing,
      );
      final label = find.byKey(const ValueKey('program-template-rule-label'));
      expect(
        tester.widget<TextField>(label).controller!.text,
        'Easy family opener',
      );
      await tester.enterText(label, 'Something else');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('program-template-rule-save')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('Edit of a rule whose saved search is gone starts with no '
        'search chosen, and keeps the rule in its place among the others', (
      tester,
    ) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          const ProgramTemplateEntry(text: 'Waltz'),
          ProgramTemplateEntry.rule(
            savedSearchId: 'deleted-search',
            label: 'Easy family opener',
          ),
          const ProgramTemplateEntry(text: Program.breakSlotText),
          const ProgramTemplateEntry(text: 'Last waltz'),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-edit-1')),
      );
      await tester.pumpAndSettle();

      final dropdown = find.byKey(
        const ValueKey('program-template-rule-search'),
      );
      expect(dropdown, findsOneWidget);
      expect(
        find.descendant(of: dropdown, matching: find.text('Family dances')),
        findsNothing,
      );
      final save = find.byKey(const ValueKey('program-template-rule-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('program-template-rule-search-${family.id}')).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect((await _stored(repos)).byId('a')!.entries, [
        const ProgramTemplateEntry(text: 'Waltz'),
        ProgramTemplateEntry.rule(
          savedSearchId: family.id,
          label: 'Easy family opener',
        ),
        const ProgramTemplateEntry(text: Program.breakSlotText),
        const ProgramTemplateEntry(text: 'Last waltz'),
      ]);
    });

    testWidgets('two quick taps on Edit open one dialog', (tester) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      final template = ProgramTemplate(
        id: 'a',
        name: 'Family',
        entries: [
          ProgramTemplateEntry.rule(
            savedSearchId: family.id,
            label: 'Easy family opener',
          ),
        ],
      );
      await _seed(repos, [template]);
      await _pump(
        tester,
        repos,
        ProgramTemplateEditorScreen(template: template),
      );
      // Two presses before the saved searches are read and the dialog opens.
      // Pressed directly: two simulated taps on this button reach it once.
      final edit = tester.widget<IconButton>(
        find.byKey(const ValueKey('program-template-rule-edit-0')),
      );
      edit.onPressed!();
      edit.onPressed!();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('program-template-rule-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('a rule cannot be labelled Break, in any case: the field says '
        'why and Save stays off', (tester) async {
      final repos = openTestRepositories();
      final family = await saveSearch(repos, 'Family dances');
      const template = ProgramTemplate(id: 'a', name: 'Family');
      await _seed(repos, const [template]);
      await _pump(
        tester,
        repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      await tester.tap(find.byKey(const ValueKey('program-template-add-rule')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('program-template-rule-search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('program-template-rule-search-${family.id}')).last,
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('program-template-rule-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      final label = find.byKey(const ValueKey('program-template-rule-label'));
      await tester.enterText(label, ' break ');
      await tester.pumpAndSettle();
      expect(
        find.text(
          '"Break" marks a break in the program, so a slot rule can\'t use '
          'it as its label.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect((await _stored(repos)).byId('a')!.entries, isEmpty);

      await tester.enterText(label, 'Break-free opener');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });
  });

  group('dance titles and the full collection load', () {
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
      await repos.dances.create(_dance('d1', 'First dance'));
      dances.fullLoads = 0;
      dances.titleLoads = 0;
      return (repos: repos, dances: dances);
    }

    const template = ProgramTemplate(
      id: 'a',
      name: 'Family',
      entries: [ProgramTemplateEntry(danceId: 'd1')],
    );

    Future<void> rebuildThrice(WidgetTester tester) async {
      // Each break insertion calls the editor's setState, i.e. rebuilds it.
      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.byKey(const ValueKey('program-template-insert-break')),
        );
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a failing titles load is logged once across rebuilds', (
      tester,
    ) async {
      final opened = await open(failTitles: true);
      await _pump(
        tester,
        opened.repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      await rebuildThrice(tester);
      expect(
        sink.sources.where((s) => s == 'program_templates_screen.dance_titles'),
        hasLength(1),
      );
      expect(opened.dances.titleLoads, 1);
    });

    testWidgets('the slot list shows titles without loading the collection, '
        'and rebuilding never loads it', (tester) async {
      final opened = await open(failFullLoad: true);
      await _pump(
        tester,
        opened.repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      expect(find.text('First dance'), findsOneWidget);
      await rebuildThrice(tester);
      expect(opened.dances.fullLoads, 0);
      expect(sink.sources, isEmpty);
    });

    testWidgets('opening the dance picker loads the full collection once', (
      tester,
    ) async {
      final opened = await open();
      await _seed(opened.repos, const [template]);
      await _pump(
        tester,
        opened.repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      await tester.tap(
        find.byKey(const ValueKey('program-template-add-dance')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CollectionPicker), findsOneWidget);
      expect(opened.dances.fullLoads, 1);
    });

    testWidgets('a failed picker load is logged per tap and retried on the '
        'next tap', (tester) async {
      final opened = await open(failFullLoad: true);
      await _pump(
        tester,
        opened.repos,
        const ProgramTemplateEditorScreen(template: template),
      );
      final add = find.byKey(const ValueKey('program-template-add-dance'));

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(CollectionPicker), findsNothing);
      expect(
        sink.sources.where((s) => s == 'program_templates_screen.picker'),
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
