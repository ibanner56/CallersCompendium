// Flutter's accessibility guidelines, run against the real app .
//
// `docs/research/accessibility-baseline.md` promises automated checks; until
// now no test ran `meetsGuideline`. Each case here pumps the full app once,
// navigates to a core screen through the app's own UI, and checks it three
// ways:
//
//  1. `labeledTapTargetGuideline` — every tappable semantics node has a label
//     (catches an inert, unlabelled extra stop such as an right-click
//     recogniser).
//  2. A 24×24 px minimum tap target — the baseline's own floor (WCAG 2.5.8),
//     not Android's 48.
//  3. A RenderFlex-overflow sweep at 360×780 and 412×915 logical px with the
//     system text scale at 2.0×, using the bundled fonts (Ahem roughly
//     doubles some overflows and hides others).
//
// Cost: one full-app pump and navigation per screen, then a resize and a text
// scale change for the overflow passes, so each screen is a single test.
// Screens are separate `testWidgets` so a failure names its screen and CI can
// shard them.
import 'dart:async';

import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/display_defaults.dart'
    show ProgramTemplateEntry;
import 'package:compendium_app/src/data/event_rules_scope.dart';
import 'package:compendium_app/src/data/program_templates.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/diagnostics/crash_log_store.dart';
import 'package:compendium_app/src/screens/settings/diagnostics_section.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/screens/app_shell.dart';
import 'package:compendium_app/src/screens/calendar_import_screen.dart';
import 'package:compendium_app/src/screens/combined_programs_screen.dart';
import 'package:compendium_app/src/screens/ecd_migration_screen.dart';
import 'package:compendium_app/src/screens/repertoire_screen.dart';
import 'package:compendium_app/src/screens/settings/event_rules_screen.dart';
import 'package:compendium_app/src/screens/settings/perform_swap_defaults_screen.dart';
import 'package:compendium_app/src/screens/settings/program_templates_screen.dart';
import 'package:compendium_app/src/screens/settings/suggestion_settings_screen.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/import_review_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/tag_manager_screen.dart';
import 'package:compendium_app/src/widgets/advanced_query_builder.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_wakelock.dart';
import 'support/full_app_harness.dart';
import 'support/l10n_harness.dart';
import 'support/real_fonts.dart';
import 'support/test_repositories.dart';

const _phone = Size(360, 780);

/// Every page Settings opens on a phone (`settings-nav-<name>`), except
/// `diagnostics`, which reads an on-disk crash log that never completes under
/// `pumpAndSettle`; it is swept by its own test below with an in-memory store.
/// The test "the Settings sweep lists every section" holds this to the hub.
const _settingsSections = [
  'general',
  'collection',
  'program',
  'appearance',
  'dialect',
  'regional',
  'defaults',
  'updates',
  'experimental',
  'about',
];
const _bigPhone = Size(412, 915);

/// The baseline's minimum tap target, in logical px (WCAG 2.5.8).
const _minimumTapTarget = MinimumTapTargetGuideline(
  size: Size(24, 24),
  link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html',
);

/// A title long enough to wrap onto several lines at 2.0x on a phone.
const _longTitle =
    'The Extraordinarily Long Titled Dance of the Autumn Harvest Ball';

Future<AppData> _seed() async {
  final appData = openTestAppData();
  final repos = appData.repositories;
  final stamp = DateTime.utc(2026, 1, 1);
  // ignore: unused_result
  await repos.choreographers.upsert(
    Choreographer(id: 'c1', name: 'Gene Hubert'),
  );
  // ignore: unused_result
  await repos.tags.upsert(Tag(id: 't1', name: 'chestnut'));
  for (final (id, title) in [
    ('d1', 'Petronella'),
    ('d2', 'The Baby Rose'),
    ('d3', 'Rory O\'More'),
  ]) {
    await repos.dances.create(
      Dance(
        id: id,
        title: title,
        figures: [
          Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        ],
        status: DanceStatus.active,
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
  }
  await repos.dances.create(
    Dance(
      id: 'd4',
      title: _longTitle,
      authorIds: const ['c1'],
      hook: 'Slow, flowing and a favourite of the late-night dancers.',
      callingNotes:
          'Teach the progression first, then the balance and swing; a long '
          'note like this one is what a caller actually types into the box.',
      walkthrough:
          'A1 circle left three places and pass through. A2 neighbors do-si-do '
          'and swing. B1 long lines forward and back, then ladies chain. B2 '
          'half promenade across and right left through.',
      meter: '6/8',
      musicalKey: 'G major',
      rating: 4,
      tagIds: const ['t1'],
      figures: [
        Figure(move: 'chain', params: {'who': 'role1s', 'beats': 16}),
        Figure(move: 'chain', params: {'who': 'role2s', 'beats': 16}),
        Figure(move: 'chain', params: {'who': 'role1s', 'beats': 8}),
      ],
      status: DanceStatus.active,
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Autumn Ball',
      slots: [
        ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
        ProgramSlot(id: 's2', position: 1, danceId: 'd2'),
        ProgramSlot(id: 's3', position: 2, text: 'Waltz'),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  // A second program, for the combined view.
  await repos.programs.create(
    Program(
      id: 'p2',
      title: 'Winter Ball',
      slots: [
        ProgramSlot(id: 'w1', position: 0, danceId: 'd2'),
        ProgramSlot(id: 'w2', position: 1, danceId: 'd4'),
      ],
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  // Event rules (Experimental) on, with rules to list, and templates to list
  // and edit.
  await repos.settings.set(kEventRulesEnabledKey, true);
  final facets = FacetSelections()..formations.add(FormationShape.becketCcw);
  final search = await repos.savedSearches.create(
    name: 'Becket dances from the long weekend list',
    spec: SavedSearchSpec.fromPanelState(
      CollectionPanelState(facets: facets),
      today: DateTime.utc(2026, 1, 1),
    ).value!,
  );
  for (final (quantifier, scope, nickname) in [
    (EventRuleQuantifier.atMost, EventRuleScope.wholeProgram, null),
    (EventRuleQuantifier.atLeast, EventRuleScope.afterFirstBreak, null),
    (EventRuleQuantifier.none, EventRuleScope.beforeFirstBreak, 'Easy start'),
    (EventRuleQuantifier.atMost, EventRuleScope.neighbouring, null),
    (EventRuleQuantifier.atMost, EventRuleScope.beforeFirstBreak, null),
    (EventRuleQuantifier.atLeast, EventRuleScope.wholeProgram, _longTitle),
  ]) {
    await repos.eventRules.create(
      savedSearchId: search.id,
      quantifier: quantifier,
      count: quantifier == EventRuleQuantifier.none ? 0 : 1,
      scope: scope,
      nickname: nickname,
    );
  }
  await saveProgramTemplate(repos.settings, _template);
  // English dances stored with contra moves, for Convert English dances.
  for (final title in ['Upon a Summer Day', 'Wakefield Hunt']) {
    await repos.dances.create(
      Dance(
        id: title,
        title: title,
        form: DanceForm.ecd,
        formation: Formation(FormationShape.dupleProper),
        figures: [
          Figure(move: 'circle', params: const {'direction': 'left'}),
        ],
        status: DanceStatus.active,
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
  }
  return appData;
}

/// A template with a dance, a text slot and a break, for its editor.
const _template = ProgramTemplate(
  id: 'tpl-autumn',
  name: 'The Autumn Harvest Ball, long-weekend evening',
  entries: [
    ProgramTemplateEntry(danceId: 'd4'),
    ProgramTemplateEntry(text: 'Waltz'),
    ProgramTemplateEntry(text: Program.breakSlotText),
    ProgramTemplateEntry(danceId: 'd1'),
  ],
);

/// Pushes [screen] over the app, as the row that opens it does.
Future<void> _push(WidgetTester tester, Widget screen) async {
  unawaited(
    Navigator.of(
      tester.element(find.byType(AppShell)),
    ).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  await tester.pumpAndSettle();
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

/// Runs [body] collecting every framework error, so a test reports all the
/// overflows on a screen rather than only the first.
Future<List<String>> _collectErrors(Future<void> Function() body) async {
  final original = FlutterError.onError;
  final errors = <String>[];
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return errors;
}

/// Pumps the full app at [_phone], runs [navigate] to reach a screen, then
/// applies the three checks above.
void _screen(
  String name,
  Future<void> Function(WidgetTester tester) navigate, {
  required Finder landedOn,
  Future<void> Function(WidgetTester tester)? atLargeText,
}) {
  testWidgets(name, (tester) async {
    await loadBundledFonts();
    installFakeWakelock();
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final appData = await _seed();
    await _setSize(tester, _phone);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        CompendiumApp(
          appData: appData,
          windowService: NoopWindowService(appData.repositories.settings),
          integrityCheck: () async => true,
        ),
      );
      await tester.pumpAndSettle();
      await navigate(tester);
      expect(tester.takeException(), isNull, reason: 'navigating to $name');
      // Guards against a sweep that quietly checks the wrong screen.
      expect(landedOn, findsWidgets, reason: 'did not reach $name');

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(_minimumTapTarget));

      final overflows = <String>[];
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      for (final size in [_phone, _bigPhone]) {
        final errors = await _collectErrors(() => _setSize(tester, size));
        overflows.addAll([
          for (final e in errors)
            if (e.contains('overflowed')) '${size.width.toInt()}dp: $e',
        ]);
        // Anything that is not an overflow is a real failure of its own.
        expect(
          errors.where((e) => !e.contains('overflowed')),
          isEmpty,
          reason: '$name at ${size.width.toInt()}dp, 2.0x',
        );
      }
      expect(overflows, isEmpty, reason: '$name overflows at 2.0x text');
      if (atLargeText != null) {
        await _setSize(tester, _phone);
        await atLargeText(tester);
      }
    } finally {
      // Disposed in the body: the framework checks handles before teardowns
      // run, and a failing expect must not leak the handle.
      semantics.dispose();
    }
  });
}

/// Scrolls the first scrollable on screen ([list], when the first is not it,
/// such as a search field's) to its end in steps, collecting every framework
/// error on the way. A lazy list builds only what is on screen, so a sweep that
/// looks at the first screenful says nothing about the rest. It fails if the
/// list does not scroll at all, because then it swept nothing new.
Future<List<String>> _scrollThrough(
  WidgetTester tester, {
  bool mustScroll = true,
  Finder? list,
}) async {
  final scrollable = list ?? find.byType(Scrollable).first;
  ScrollPosition position() =>
      tester.state<ScrollableState>(scrollable).position;
  final start = position().pixels;
  final errors = await _collectErrors(() async {
    for (var step = 0; step < 80; step++) {
      final before = position().pixels;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      if (position().pixels == before) return;
    }
    fail('never reached the end of the list');
  });
  final moved = position().pixels - start;
  if (mustScroll) {
    expect(
      moved,
      greaterThan(_phone.height / 2),
      reason:
          'the list barely scrolled, so this swept only its first screenful',
    );
  }
  return errors;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _openProgramSummary(WidgetTester tester) async {
  await tester.tap(find.text('Programs'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Autumn Ball'));
  await tester.pumpAndSettle();
}

/// An in-memory [CrashLogStore]: the app-support store does real file I/O,
/// which never completes in a widget test's fake-async zone.
class _InMemoryCrashLogStore extends CrashLogStore {
  _InMemoryCrashLogStore(this._records)
    : super(directoryProvider: () async => throw StateError('no I/O in test'));

  final List<CrashLogRecord> _records;

  @override
  Future<List<CrashLogRecord>> readRecords({
    int? limit,
    bool newestFirst = true,
  }) async => newestFirst ? _records.reversed.toList() : List.of(_records);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _screen('Collection', (_) async {}, landedOn: find.text('Petronella'));

  _screen('Collection, selection mode', (tester) async {
    await _tapKey(tester, 'collection-more-actions');
    await _tapKey(tester, 'batch-select');
  }, landedOn: find.byKey(const ValueKey('batch-exit')));

  _screen('Advanced search', (tester) async {
    await _tapKey(tester, 'advanced-panel');
  }, landedOn: find.byType(AdvancedQueryBuilder));

  _screen('Programs list', (tester) async {
    await tester.tap(find.text('Programs'));
    await tester.pumpAndSettle();
  }, landedOn: find.byKey(const ValueKey('new-program')));

  _screen(
    'Program summary',
    _openProgramSummary,
    landedOn: find.byKey(const ValueKey('summary-screen-p1')),
  );

  _screen('Program builder', (tester) async {
    await _openProgramSummary(tester);
    await _tapKey(tester, 'open-builder');
  }, landedOn: find.byType(ProgramEditorScreen));

  // More details holds the builder's filterable drop-downs (pay currency,
  // dialect), whose arrow is a button of its own beside the field.
  _screen(
    'Program builder, more details',
    (tester) async {
      await _openProgramSummary(tester);
      await _tapKey(tester, 'open-builder');
      await tester.tap(find.byKey(const ValueKey('program-more-details-tile')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('program-pay-currency')),
      );
      await tester.pumpAndSettle();
    },
    landedOn: find.byKey(const ValueKey('program-pay-currency')).hitTestable(),
  );

  _screen('Perform', (tester) async {
    await _openProgramSummary(tester);
    await _tapKey(tester, 'summary-perform');
  }, landedOn: find.byType(PerformProgramScreen));

  _screen(
    'Perform, Adjust sheet',
    (tester) async {
      await _openProgramSummary(tester);
      await _tapKey(tester, 'summary-perform');
      // On a phone Adjust lives in the toolbar's overflow menu.
      await _tapKey(tester, 'perform-overflow-menu');
      await _tapKey(tester, 'perform-adjust-menu');
      // At normal text Done sits at the trailing edge (the header's 8dp padding
      // from the right of the 360dp screen), not beside the title.
      expect(
        tester.getRect(find.byKey(const ValueKey('adjust-done'))).right,
        closeTo(_phone.width - 8, 1),
      );
    },
    landedOn: find.byKey(const ValueKey('adjust-done')),
    atLargeText: (tester) async {
      // Done was pushed past the right edge of a 360dp screen. Done is the
      // sheet's labelled way to finish, so it must stay reachable.
      final done = find.byKey(const ValueKey('adjust-done'));
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.getRect(done).right, lessThanOrEqualTo(_phone.width));
    },
  );

  // The form is a lazy list, so on a 780dp surface this sees only its first
  // screenful; the Type and Formation dropdowns are covered on a tall surface
  // by `dance_editor_narrow_test.dart`.
  _screen('Dance editor', (tester) async {
    await _tapKey(tester, 'new-dance');
  }, landedOn: find.byType(DanceEditorScreen));

  // The seeded dance with a long title, notes, a tag and a rating, so the
  // detail screen has content to wrap, not just a title.
  _screen(
    'Dance detail',
    (tester) async {
      await tester.tap(find.text(_longTitle));
      await tester.pumpAndSettle();
    },
    landedOn: find.byType(DanceDetailScreen),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(tester),
        isEmpty,
        reason: 'Dance detail, scrolled to the end at 2.0x',
      );
    },
  );

  _screen('Settings', (tester) async {
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
  }, landedOn: find.byKey(const ValueKey('settings-nav-general')));

  // On a phone Settings is a list of sections, each its own page, so sweeping
  // the list alone would check ten rows and none of what they open.
  for (final section in _settingsSections) {
    _screen(
      'Settings, $section',
      (tester) async {
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        await _tapKey(tester, 'settings-nav-$section');
      },
      // The hub has no back button; a section page pushed over it does.
      landedOn: find.byType(BackButton),
      atLargeText: (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        await tester.pumpAndSettle();
        expect(
          await _scrollThrough(tester, mustScroll: false),
          isEmpty,
          reason: 'Settings, $section, scrolled to the end at 2.0x',
        );
      },
    );
  }

  // Settings > Appearance > Theme, a page of its own: the card gallery under a
  // search box, with a floating Custom theme button over it.
  _screen(
    'Settings, appearance, Theme',
    (tester) async {
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await _tapKey(tester, 'settings-nav-appearance');
      await _tapKey(tester, 'appearance-theme');
    },
    landedOn: find.byKey(const ValueKey('theme-search')),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(
          tester,
          list: find.descendant(
            of: find.byKey(const ValueKey('theme-list')),
            matching: find.byType(Scrollable),
          ),
        ),
        isEmpty,
        reason: 'Theme, scrolled to the end at 2.0x',
      );
    },
  );

  _screen('Tags manager', (tester) async {
    Navigator.of(
      tester.element(find.byType(AppShell)),
    ).push(MaterialPageRoute<void>(builder: (_) => const TagManagerScreen()));
    await tester.pumpAndSettle();
    // The longest sort label ("by dance count") is the one that overflowed
    // the filter row .
    await _tapKey(tester, 'tag-sort');
    await _tapKey(tester, 'tag-sort-count');
  }, landedOn: find.byType(TagManagerScreen));

  _screen('Import review', (tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).importDances();
    await tester.pumpAndSettle();
  }, landedOn: find.byType(ImportReviewScreen));

  // Screens added since v0.10.0-beta (audit L10N-09). Each is pushed as the
  // row or button that opens it does; the path to it is not what is swept.
  _screen(
    'Repertoire',
    (tester) => _push(tester, const RepertoireScreen()),
    landedOn: find.byType(RepertoireScreen),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(tester, mustScroll: false),
        isEmpty,
        reason: 'Repertoire, scrolled to the end at 2.0x',
      );
    },
  );

  _screen(
    'Combined view',
    (tester) =>
        _push(tester, const CombinedProgramsScreen(programIds: {'p1', 'p2'})),
    landedOn: find.byType(CombinedProgramsScreen),
  );

  _screen(
    'Calendar import',
    (tester) => _push(tester, const CalendarImportScreen()),
    landedOn: find.byType(CalendarImportScreen),
  );

  _screen(
    'Manage rules',
    (tester) => _push(tester, const EventRulesScreen()),
    landedOn: find.text('Easy start'),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(tester, mustScroll: false),
        isEmpty,
        reason: 'Manage rules, scrolled to the end at 2.0x',
      );
    },
  );

  _screen(
    'Rule editor',
    (tester) async {
      await _push(tester, const EventRulesScreen());
      await tester.tap(find.text('Easy start'));
      await tester.pumpAndSettle();
    },
    landedOn: find.byType(EventRuleEditorScreen),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(tester, mustScroll: false),
        isEmpty,
        reason: 'Rule editor, scrolled to the end at 2.0x',
      );
    },
  );

  _screen(
    'Program templates',
    (tester) => _push(tester, const ProgramTemplatesScreen()),
    landedOn: find.byKey(const ValueKey('program-template-tile-tpl-autumn')),
  );

  _screen(
    'Template editor',
    (tester) async {
      await _push(tester, const ProgramTemplatesScreen());
      await _tapKey(tester, 'program-template-tile-tpl-autumn');
    },
    landedOn: find.byType(ProgramTemplateEditorScreen),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(tester, mustScroll: false),
        isEmpty,
        reason: 'Template editor, scrolled to the end at 2.0x',
      );
    },
  );

  _screen(
    'Suggestion settings',
    (tester) => _push(tester, const SuggestionSettingsScreen()),
    landedOn: find.byType(SuggestionSettingsScreen),
    atLargeText: (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(
        await _scrollThrough(tester, mustScroll: false),
        isEmpty,
        reason: 'Suggestion settings, scrolled to the end at 2.0x',
      );
    },
  );

  _screen(
    'Perform swap defaults',
    (tester) => _push(tester, const PerformSwapDefaultsScreen()),
    landedOn: find.byType(PerformSwapDefaultsScreen),
  );

  _screen(
    'Convert English dances',
    (tester) => _push(tester, const EcdMigrationScreen()),
    landedOn: find.byKey(
      const ValueKey('ecd-migration-dance-Upon a Summer Day'),
    ),
  );

  // A ratchet on [_settingsSections]: a section added to the hub is swept, or
  // named here as the exception.
  testWidgets('the Settings sweep lists every section', (tester) async {
    await loadBundledFonts();
    installFakeWakelock();
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final appData = await _seed();
    // Tall, so the hub's list is built to its end.
    await _setSize(tester, const Size(360, 3000));
    await tester.pumpWidget(
      CompendiumApp(
        appData: appData,
        windowService: NoopWindowService(appData.repositories.settings),
        integrityCheck: () async => true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final onHub = {
      for (final element
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'settings-nav-',
                    ),
              )
              .evaluate())
        (element.widget.key! as ValueKey<String>).value.substring(
          'settings-nav-'.length,
        ),
    };
    // Positive control: the hub was found at all.
    expect(onHub, contains('general'));
    expect(onHub, {..._settingsSections, 'diagnostics'});
  });

  // Settings > Diagnostics, outside the full-app sweep (see `_settingsSections`).
  testWidgets('Settings, diagnostics', (tester) async {
    await loadBundledFonts();
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repos = openTestRepositories();
    final store = _InMemoryCrashLogStore([
      for (var i = 0; i < 4; i++)
        CrashLogRecord(
          timestampUtc: DateTime.utc(2026, 3, 2, i),
          appVersion: '0.10.0',
          platform: 'testos 1.0',
          source: 'FlutterError.onError',
          errorType: 'StateError',
          errorMessage:
              'A long error message that a crash log really can carry, so the '
              'list has lines to wrap at large text sizes ($i).',
          stack: '#0 render (package:compendium_app/main.dart:42:7)',
        ),
    ]);
    await _setSize(tester, _phone);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: RepositoriesScope(
            repositories: repos,
            child: Scaffold(
              appBar: AppBar(title: const Text('Diagnostics')),
              body: DiagnosticsSection(
                store: store,
                sensitiveTermsProvider: () async => const {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsSection), findsOneWidget);
      // Guards against sweeping an empty list: the seeded records are shown.
      expect(find.textContaining('A long error message'), findsWidgets);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(_minimumTapTarget));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      for (final size in [_phone, _bigPhone]) {
        final errors = await _collectErrors(() => _setSize(tester, size));
        expect(
          errors,
          isEmpty,
          reason: 'diagnostics at ${size.width.toInt()}dp, 2.0x',
        );
      }
      expect(
        await _scrollThrough(tester, mustScroll: false),
        isEmpty,
        reason: 'diagnostics, scrolled to the end at 2.0x',
      );
    } finally {
      semantics.dispose();
    }
  });
}
