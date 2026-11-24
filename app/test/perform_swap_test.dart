import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/perform_swap_sheet.dart';
import 'package:compendium_app/src/search/collection_data.dart';

import 'support/test_repositories.dart';
import 'support/fake_wakelock.dart';
import 'support/l10n_harness.dart';

/// Perform's **Swap a dance** (#2346): Swap on the dance being called and on
/// upcoming dances, the swap sheet's Keep items and results, and what a pick
/// does to the program.
final _now = DateTime.utc(2026, 1, 1);
final _renderer = FigureRenderer(contraTaxonomy);

Figure _fig(String move, int beats) =>
    testFigure(move: move, params: {'beats': beats});

/// A 64-beat contra: circle and hey in A1/A2, balance and swing in B1, long
/// lines and allemande in B2.
final _figures = [
  _fig('circle', 16),
  _fig('hey', 16),
  _fig('balance', 4),
  _fig('swing', 12),
  _fig('long_lines', 8),
  _fig('allemande', 8),
];

Dance _dance(
  String id,
  String title, {
  DanceForm form = DanceForm.contra,
  FormationShape shape = FormationShape.becketCw,
  String? level = DifficultyLevel.intermediateId,
  List<Figure>? figures,
}) => Dance(
  id: id,
  title: title,
  form: form,
  formation: Formation(shape),
  difficultyLevelId: level,
  figures: figures ?? _figures,
  status: DanceStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

/// The collection: the program's dances, and candidates that each fail one
/// Keep item but [_match], which keeps them all.
final _match = _dance('match', 'Match Reel', level: DifficultyLevel.beginnerId);
final _harder = _dance(
  'harder',
  'Harder Reel',
  level: DifficultyLevel.advancedId,
);
final _improper = _dance(
  'improper',
  'Improper Reel',
  shape: FormationShape.dupleImproper,
  level: DifficultyLevel.beginnerId,
);
final _noHey = _dance(
  'nohey',
  'No Hey Reel',
  level: DifficultyLevel.beginnerId,
  figures: [
    _fig('circle', 16),
    _fig('do_si_do', 16),
    _fig('balance', 4),
    _fig('swing', 12),
    _fig('long_lines', 8),
    _fig('allemande', 8),
  ],
);
final _alt = _dance(
  'alt',
  'Backup Jig',
  shape: FormationShape.dupleImproper,
  level: DifficultyLevel.advancedId,
);

final _played = DateTime.utc(2025, 12, 31, 20);

/// earlier (performed) · current · current's alternate · note · break ·
/// upcoming · upcoming performed.
List<ProgramSlot> _slots() => [
  ProgramSlot(id: 's0', position: 0, danceId: 'd0', performedAt: _played),
  ProgramSlot(
    id: 's1',
    position: 1,
    danceId: 'd1',
    text: 'band: slow reel',
    guestCaller: 'Sam',
    walkthroughMinutes: 3,
    danceMinutes: 9,
  ),
  ProgramSlot(id: 's1-alt', position: 2, danceId: 'alt', isAlt: true),
  ProgramSlot(id: 's2', position: 3, text: 'Announce the potluck'),
  ProgramSlot(id: 's3', position: 4, text: Program.breakSlotText),
  ProgramSlot(id: 's4', position: 5, danceId: 'd4'),
  ProgramSlot(id: 's5', position: 6, danceId: 'd5', performedAt: _played),
];

Program _program([List<ProgramSlot>? slots]) => Program(
  id: 'p1',
  title: 'Spring Dance',
  slots: slots ?? _slots(),
  createdAt: _now,
  updatedAt: _now,
);

final _programDances = [
  _dance('d0', 'Opener'),
  _dance('d1', 'Current Reel'),
  _dance('d4', 'Upcoming Reel'),
  _dance('d5', 'Played Reel'),
];

typedef _Harness = ({List<Program> persisted, CompendiumRepositories repos});

/// Program Perform on the current slot `s1` (group 1), with an adjust sheet
/// whose pickers search a real repository.
Future<_Harness> _pump(
  WidgetTester tester, {
  Program? program,
  List<Dance>? extra,
  int initialGroup = 1,
  Object? storedDefaults,
  Set<String> hiddenFacets = const {},
  SettingsRepository Function(CompendiumDatabase db)? settings,
  DialectsByForm? dialects,
  Future<PerformAdjustmentResult?> Function(Program before, Program updated)?
  onProgramChanged,
  bool pushed = false,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = openWidgetTestDatabase();
  final repos = CompendiumRepositories(
    db,
    contraTaxonomy,
    settings: settings?.call(db),
  );
  for (final d in [
    ..._programDances,
    ...(extra ?? [_match, _harder, _improper, _noHey, _alt]),
  ]) {
    await repos.dances.create(d);
  }
  if (storedDefaults != null) {
    await repos.settings.set(kPerformSwapDefaultsKey, storedDefaults);
  }
  final data = await CollectionData.load(repos);
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  final byForm = ValueNotifier<DialectsByForm>(
    dialects ?? DialectsByForm.all(Dialect.larksRobins),
  );
  addTearDown(byForm.dispose);
  final hidden = ValueNotifier<Set<String>>(hiddenFacets);
  addTearDown(hidden.dispose);
  final persisted = <Program>[];
  final perform = PerformProgramScreen(
    program: program ?? _program(),
    data: data,
    renderer: _renderer,
    initialGroup: initialGroup,
    onProgramChanged: (before, updated) async {
      persisted.add(updated);
      return onProgramChanged?.call(before, updated);
    },
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: CollectionFacetsScope(
          notifier: hidden,
          child: dialects == null
              ? ActiveDialectScope(notifier: notifier, child: child!)
              : ActiveDialectScope.byForm(dialects: byForm, child: child!),
        ),
      ),
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const ValueKey('open-perform'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => perform)),
                  child: const Text('open'),
                ),
              ),
            )
          : perform,
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) await _tap(tester, find.byKey(const ValueKey('open-perform')));
  return (persisted: persisted, repos: repos);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openAdjust(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('perform-adjust')));

Finder _inSwap(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('adjust-swap-sheet')),
  matching: matching,
);

Finder _tile(String id) => _inSwap(find.byKey(ValueKey('picker-tile-$id')));

Finder _pick(String id) => _inSwap(find.byKey(ValueKey('picker-add-$id')));

FilterChip _chip(WidgetTester tester, String key) =>
    tester.widget<FilterChip>(_inSwap(find.byKey(ValueKey(key))));

/// Settings whose reads of the Swap a dance defaults wait for [release].
class _HeldSwapSettings extends SettingsRepository {
  _HeldSwapSettings(super.db);

  final release = Completer<void>();

  @override
  Future<Object?> get(String key) async {
    if (key == kPerformSwapDefaultsKey) await release.future;
    return super.get(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installFakeWakelock);

  group('where Swap is offered', () {
    testWidgets('on the current dance and every upcoming dance not marked '
        'performed; never on a note, a break, an earlier slot or a performed '
        'one', (tester) async {
      await _pump(tester);
      await _openAdjust(tester);

      expect(find.byKey(const ValueKey('adjust-swap-current')), findsOneWidget);
      expect(find.byKey(const ValueKey('adjust-swap-s4')), findsOneWidget);
      for (final id in ['s0', 's1', 's2', 's3', 's5']) {
        expect(
          find.byKey(ValueKey('adjust-swap-$id')),
          findsNothing,
          reason: id,
        );
      }
      expect(
        tester.getSemantics(find.byKey(const ValueKey('adjust-swap-s4'))),
        isSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          tooltip: 'Swap Upcoming Reel',
        ),
      );
    });

    testWidgets('not on the current dance once it is marked performed', (
      tester,
    ) async {
      await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-mark-performed')));
      expect(find.byKey(const ValueKey('adjust-swap-current')), findsNothing);
    });

    testWidgets('not on a shown alternate whose planned dance is marked '
        'performed', (tester) async {
      final slots = _slots();
      slots[1] = slots[1].copyWith(performedAt: _played);
      await _pump(tester, program: _program(slots));
      await _tap(tester, find.byKey(const ValueKey('perform-alt-swap')));
      expect(find.text('Backup Jig'), findsWidgets);
      await _openAdjust(tester);
      expect(find.byKey(const ValueKey('adjust-swap-current')), findsNothing);
    });

    testWidgets('not on an upcoming dance moved above the current one', (
      tester,
    ) async {
      // Current s1, then s4 and s6 upcoming; move the current dance down past
      // s4, which then comes before it.
      await _pump(
        tester,
        program: _program([
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 's4', position: 1, danceId: 'd4'),
          ProgramSlot(id: 's6', position: 2, danceId: 'match'),
        ]),
        initialGroup: 0,
      );
      await _openAdjust(tester);
      expect(find.byKey(const ValueKey('adjust-swap-s4')), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('adjust-move-down-0')));
      expect(find.byKey(const ValueKey('adjust-swap-s4')), findsNothing);
      expect(find.byKey(const ValueKey('adjust-swap-s6')), findsOneWidget);
    });
  });

  group('the swap sheet', () {
    testWidgets('opens already searched from the default Keep items, with '
        'the slot\'s alternates first', (tester) async {
      await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));

      // Same formation, this level or easier, not already in the program.
      expect(_chip(tester, 'swap-keep-formation').selected, isTrue);
      expect(_chip(tester, 'swap-keep-level').selected, isTrue);
      expect(_chip(tester, 'swap-keep-not-in-program').selected, isTrue);
      // An all-contra program: no Same type.
      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-type'))),
        findsNothing,
      );

      expect(_tile('match'), findsOneWidget);
      expect(_tile('nohey'), findsOneWidget);
      expect(_tile('harder'), findsNothing, reason: 'harder than this level');
      expect(_tile('improper'), findsNothing, reason: 'another formation');
      expect(_tile('d4'), findsNothing, reason: 'already in the program');
      expect(_tile('d1'), findsNothing, reason: 'the dance being swapped');

      // The alternate matches no Keep item but heads the list.
      final alternates = _inSwap(
        find.byKey(const ValueKey('picker-pinned-heading')),
      );
      final results = _inSwap(
        find.byKey(const ValueKey('picker-results-heading')),
      );
      expect(alternates, findsOneWidget);
      expect(
        find.descendant(of: alternates, matching: find.text('Your alternates')),
        findsOneWidget,
      );
      expect(_tile('alt'), findsOneWidget);
      final altY = tester.getTopLeft(_tile('alt')).dy;
      expect(tester.getTopLeft(alternates).dy, lessThan(altY));
      expect(altY, lessThan(tester.getTopLeft(results).dy));
      expect(
        tester.getTopLeft(results).dy,
        lessThan(tester.getTopLeft(_tile('match')).dy),
      );
    });

    testWidgets('results update as Keep items change, with no Search button', (
      tester,
    ) async {
      await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));

      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-formation'))),
      );
      expect(_tile('improper'), findsOneWidget);
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-level'))),
      );
      expect(_tile('harder'), findsOneWidget);
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-not-in-program'))),
      );
      expect(_tile('d4'), findsOneWidget);
      expect(_tile('d1'), findsNothing, reason: 'never its own replacement');

      // Keep the hey: the dance without one drops out.
      expect(_tile('nohey'), findsOneWidget);
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-figure-1'))),
      );
      expect(_tile('nohey'), findsNothing);
      expect(_tile('match'), findsOneWidget);
    });

    testWidgets('never lists the dance being swapped, as a result or under '
        'Your alternates, whatever the Keep items', (tester) async {
      // An alternate that holds the slot's own dance.
      final slots = _slots()
        ..insert(
          3,
          ProgramSlot(id: 's1-dup', position: 3, danceId: 'd1', isAlt: true),
        );
      await _pump(tester, program: _program(slots));
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      for (final key in [
        'swap-keep-formation',
        'swap-keep-level',
        'swap-keep-not-in-program',
      ]) {
        await _tap(tester, _inSwap(find.byKey(ValueKey(key))));
        expect(_chip(tester, key).selected, isFalse, reason: key);
      }
      expect(_tile('d4'), findsOneWidget, reason: 'every Keep item is off');
      expect(_tile('alt'), findsOneWidget);
      expect(_tile('d1'), findsNothing);
    });

    testWidgets('a kept figure offers In the same phrase and With what comes '
        'before it', (tester) async {
      await _pump(
        tester,
        extra: [
          _match,
          // A hey in B1, not A2.
          _dance(
            'latehey',
            'Late Hey Reel',
            level: DifficultyLevel.beginnerId,
            figures: [
              _fig('circle', 16),
              _fig('do_si_do', 16),
              _fig('hey', 16),
              _fig('long_lines', 8),
              _fig('allemande', 8),
            ],
          ),
        ],
      );
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-figure-1'))),
      );
      expect(_tile('latehey'), findsOneWidget);

      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-same-phrase-1'))),
      );
      expect(_tile('latehey'), findsNothing, reason: 'its hey is in B1');
      expect(_tile('match'), findsOneWidget);

      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-same-phrase-1'))),
      );
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-with-before-1'))),
      );
      expect(
        _tile('latehey'),
        findsNothing,
        reason: 'its hey follows a do si do',
      );
      expect(_tile('match'), findsOneWidget);
    });

    testWidgets('More filters shows the same criteria in the panels, '
        'editable', (tester) async {
      await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-figure-1'))),
      );
      expect(
        _inSwap(find.byKey(const ValueKey('picker-search'))),
        findsNothing,
      );

      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-more-filters'))),
      );
      expect(
        _inSwap(find.byKey(const ValueKey('picker-search'))),
        findsOneWidget,
      );
      // The Filters panel opens, with this dance's formation and the levels
      // at or below its own selected.
      final formation = _inSwap(
        find.byKey(const ValueKey('formation-becketCw')),
      );
      expect(tester.widget<FilterChip>(formation).selected, isTrue);
      final easier = _inSwap(find.byKey(const ValueKey('level-beginner')));
      expect(tester.widget<FilterChip>(easier).selected, isTrue);
      expect(
        tester
            .widget<FilterChip>(
              _inSwap(find.byKey(const ValueKey('level-advanced'))),
            )
            .selected,
        isFalse,
      );
      // The chips that live in the panels are put away; not-in-program stays.
      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-formation'))),
        findsNothing,
      );
      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-not-in-program'))),
        findsOneWidget,
      );

      // Editable: drop the formation in the panel.
      expect(_tile('improper'), findsNothing);
      await _tap(tester, formation);
      expect(_tile('improper'), findsOneWidget);

      // The kept hey is an Advanced row.
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('picker-advanced-panel'))),
      );
      expect(_inSwap(find.textContaining('hey')), findsWidgets);
      expect(_tile('nohey'), findsNothing);
    });

    testWidgets('a Keep change keeps the sort the caller picked', (
      tester,
    ) async {
      await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      double top(String id) => tester.getTopLeft(_tile(id)).dy;
      expect(top('match'), lessThan(top('nohey')), reason: 'by title, A–Z');
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('picker-sort-direction'))),
      );
      expect(top('nohey'), lessThan(top('match')), reason: 'Z–A');

      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-formation'))),
      );
      expect(_tile('improper'), findsOneWidget, reason: 'searched again');
      expect(top('nohey'), lessThan(top('match')), reason: 'still Z–A');
    });

    testWidgets('after More filters, Not already in tonight\'s program changes '
        'only the dances left out, keeping the panel edits', (tester) async {
      await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-more-filters'))),
      );
      final formation = _inSwap(
        find.byKey(const ValueKey('formation-becketCw')),
      );
      await _tap(tester, formation);
      expect(_tile('improper'), findsOneWidget);
      expect(_tile('d4'), findsNothing);

      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-not-in-program'))),
      );
      expect(_tile('d4'), findsOneWidget);
      expect(tester.widget<FilterChip>(formation).selected, isFalse);
      expect(_tile('improper'), findsOneWidget, reason: 'the edit is kept');
    });
  });

  group('picking a replacement', () {
    testWidgets('with the defaults, two taps swap the dance being called: it '
        'keeps its note, guest caller and lengths, the old dance becomes its '
        'alternate, and Undo restores the slot exactly', (tester) async {
      final h = await _pump(tester);
      await _openAdjust(tester);

      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      await _tap(tester, _pick('match'));

      expect(find.byKey(const ValueKey('adjust-swap-sheet')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('adjust-done')));

      final swapped = h.persisted.single;
      final slot = swapped.slots.firstWhere((s) => s.id == 's1');
      expect(slot.danceId, 'match');
      expect(slot.text, 'band: slow reel');
      expect(slot.guestCaller, 'Sam');
      expect(slot.walkthroughMinutes, 3);
      expect(slot.danceMinutes, 9);
      final group = swapped.grouped.firstWhere((g) => g.primary.id == 's1');
      expect(group.alternates.map((s) => s.danceId), ['d1', 'alt']);
      expect(group.alternates.first.performedAt, isNull);
      // Perform stays on the slot, now showing the new dance.
      expect(find.text('Match Reel'), findsWidgets);
      expect(find.text('Slot 2 of 6'), findsOneWidget);

      await _tap(tester, find.text('Undo'));
      expect(h.persisted.last.slots, _slots());
    });

    testWidgets('calling history does not count the swapped-out dance', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      await _tap(tester, _pick('match'));
      await _tap(tester, find.byKey(const ValueKey('adjust-done')));

      await h.repos.programs.create(h.persisted.single);
      final data = await CollectionData.load(h.repos);
      int calls(String id) =>
          data.callCounts[id]?.countFor(false, requireEventDate: false) ?? 0;
      expect(calls('match'), 1);
      expect(calls('d1'), 0, reason: 'kept as an unmarked alternate');
      expect(calls('d4'), 1, reason: 'the history is read at all');
    });

    testWidgets('on a shown alternate, choosing the planned dance counts '
        'that dance and not the alternate bailed on', (tester) async {
      final h = await _pump(tester);
      await _tap(tester, find.byKey(const ValueKey('perform-alt-swap')));
      expect(find.text('Backup Jig'), findsWidgets);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      // The planned dance is one of Your alternates here.
      await _tap(tester, _pick('d1'));
      await _tap(tester, find.byKey(const ValueKey('adjust-done')));

      final group = h.persisted.single.slots.take(3).toList();
      expect(group.map((s) => s.id), ['s0', 's1-alt', 's1']);
      expect(group[1].danceId, 'd1');
      expect(group[1].isAlt, isFalse);
      expect(group[2].danceId, 'alt');
      expect(group[2].isAlt, isTrue);

      await h.repos.programs.create(h.persisted.single);
      final data = await CollectionData.load(h.repos);
      int calls(String id) =>
          data.callCounts[id]?.countFor(false, requireEventDate: false) ?? 0;
      expect(calls('d1'), 1);
      expect(calls('alt'), 0, reason: 'bailed on: an unmarked alternate');
    });

    testWidgets('choosing one of Your alternates trades the two dances', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
      await _tap(tester, _pick('alt'));
      await _tap(tester, find.byKey(const ValueKey('adjust-done')));

      final slots = h.persisted.single.slots;
      expect(slots.firstWhere((s) => s.id == 's1').danceId, 'alt');
      expect(slots.firstWhere((s) => s.id == 's1-alt').danceId, 'd1');
      expect(slots, hasLength(_slots().length));
    });

    testWidgets('swapping an upcoming dance leaves the current slot and '
        'Perform\'s place unchanged', (tester) async {
      final h = await _pump(tester);
      expect(find.text('Current Reel'), findsWidgets);
      expect(find.text('Slot 2 of 6'), findsOneWidget);

      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-s4')));
      await _tap(tester, _pick('match'));
      await _tap(tester, find.byKey(const ValueKey('adjust-done')));

      final slots = h.persisted.single.slots;
      expect(slots.firstWhere((s) => s.id == 's4').danceId, 'match');
      expect(
        slots.firstWhere((s) => s.id == 's1'),
        _slots().firstWhere((s) => s.id == 's1'),
      );
      expect(find.text('Current Reel'), findsWidgets);
      expect(find.text('Upcoming Reel'), findsNothing);
      expect(find.text('Slot 2 of 6'), findsOneWidget);
    });
  });

  testWidgets('a Filters section hidden in Settings is not offered as a Keep '
      'item and adds no criterion', (tester) async {
    await _pump(tester, hiddenFacets: {CollectionFacetIds.formation});
    await _openAdjust(tester);
    await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
    expect(
      _inSwap(find.byKey(const ValueKey('swap-keep-formation'))),
      findsNothing,
    );
    expect(_chip(tester, 'swap-keep-level').selected, isTrue);
    expect(_tile('improper'), findsOneWidget, reason: 'another formation');
    expect(_tile('harder'), findsNothing, reason: 'level is still kept');
  });

  testWidgets('a second tap on Swap while the defaults are read opens one '
      'sheet', (tester) async {
    late _HeldSwapSettings held;
    await _pump(tester, settings: (db) => held = _HeldSwapSettings(db));
    await _openAdjust(tester);
    final swap = find.byKey(const ValueKey('adjust-swap-current'));
    await tester.ensureVisible(swap);
    await tester.pumpAndSettle();
    await tester.tap(swap);
    await tester.pump();
    await tester.tap(swap);
    await tester.pump();
    held.release.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('adjust-swap-sheet'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('an upcoming dance of another type is named in its own type\'s '
      'dialect', (tester) async {
    final slots = _slots();
    slots[5] = ProgramSlot(id: 's4', position: 5, danceId: 'sq');
    await _pump(
      tester,
      program: _program(slots),
      extra: [
        _dance('sq', 'Square Hey', form: DanceForm.square),
        _match,
      ],
      dialects: DialectsByForm({
        DanceForm.contra: Dialect.larksRobins,
        DanceForm.square: Dialect.larksRobins.copyWith(
          moves: {'hey': 'grand weave'},
        ),
      }),
    );
    await _openAdjust(tester);
    await _tap(tester, find.byKey(const ValueKey('adjust-swap-s4')));
    expect(
      _inSwap(
        find.descendant(
          of: find.byKey(const ValueKey('swap-keep-figure-1')),
          matching: find.textContaining('grand weave'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a refused swap leaves a later adjustment, still being written, '
      'on screen, and offers no Undo', (tester) async {
    final firstWrite = Completer<PerformAdjustmentResult?>();
    var writes = 0;
    final h = await _pump(
      tester,
      onProgramChanged: (_, _) =>
          writes++ == 0 ? firstWrite.future : Future.value(),
    );
    // A: swap the dance being called.
    await _openAdjust(tester);
    await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
    await _tap(tester, _pick('match'));
    await _tap(tester, find.byKey(const ValueKey('adjust-done')));
    expect(find.text('Match Reel'), findsWidgets);
    // B, while A's write is held: add a note after the current slot.
    await _openAdjust(tester);
    await tester.enterText(
      find.byKey(const ValueKey('adjust-note-field')),
      'Announce the raffle',
    );
    await _tap(tester, find.byKey(const ValueKey('adjust-add-note')));
    await _tap(tester, find.byKey(const ValueKey('adjust-done')));
    expect(find.text('Slot 2 of 7'), findsOneWidget);
    expect(find.byKey(const ValueKey('perform-adjusted-undo')), findsOneWidget);

    // A is refused: the program as stored is the one Perform opened with.
    firstWrite.complete(PerformAdjustmentResult.refused(_program()));
    await tester.pumpAndSettle();

    expect(find.text('Current Reel'), findsWidgets, reason: 'no swap');
    expect(find.text('Slot 2 of 7'), findsOneWidget, reason: 'B stays');
    expect(find.byKey(const ValueKey('perform-swap-refused')), findsOneWidget);
    expect(find.byKey(const ValueKey('perform-adjusted-undo')), findsNothing);
    expect(h.persisted, hasLength(2));
  });

  testWidgets('a swap refused after Perform has closed takes down the Undo '
      'prompt and says so on the screen Perform was opened from', (
    tester,
  ) async {
    final write = Completer<PerformAdjustmentResult?>();
    await _pump(tester, pushed: true, onProgramChanged: (_, _) => write.future);
    await _openAdjust(tester);
    await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
    await _tap(tester, _pick('match'));
    await _tap(tester, find.byKey(const ValueKey('adjust-done')));
    await _tap(tester, find.byKey(const ValueKey('perform-program-exit')));
    final confirm = find.byKey(const ValueKey('perform-exit-confirm'));
    if (confirm.evaluate().isNotEmpty) await _tap(tester, confirm);
    expect(find.byType(PerformProgramScreen), findsNothing);
    expect(find.byKey(const ValueKey('perform-adjusted-undo')), findsOneWidget);

    write.complete(PerformAdjustmentResult.refused(_program()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('perform-adjusted-undo')), findsNothing);
    expect(find.byKey(const ValueKey('perform-swap-refused')), findsOneWidget);
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        ).performSwapRefused,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a Keep item turned off in Swap a dance defaults opens off', (
    tester,
  ) async {
    await _pump(
      tester,
      storedDefaults: {
        'version': 1,
        'keep': {'formation': false},
      },
    );
    await _openAdjust(tester);
    await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
    expect(_chip(tester, 'swap-keep-formation').selected, isFalse);
    expect(_chip(tester, 'swap-keep-level').selected, isTrue);
    expect(_tile('improper'), findsOneWidget);
  });

  testWidgets('controls are 44 pt or larger, and Keep chips have '
      'screen-reader labels', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await _openAdjust(tester);

    void atLeast44(Finder finder, String what) {
      final size = tester.getSize(finder);
      expect(
        size.height,
        greaterThanOrEqualTo(kPerformSwapMinTarget),
        reason: what,
      );
      expect(
        size.width,
        greaterThanOrEqualTo(kPerformSwapMinTarget),
        reason: what,
      );
    }

    atLeast44(
      find.byKey(const ValueKey('adjust-swap-current')),
      'Swap this dance',
    );
    atLeast44(find.byKey(const ValueKey('adjust-swap-s4')), 'row Swap');
    await _tap(tester, find.byKey(const ValueKey('adjust-swap-current')));
    await _tap(
      tester,
      _inSwap(find.byKey(const ValueKey('swap-keep-figure-1'))),
    );
    for (final key in [
      'swap-keep-formation',
      'swap-keep-level',
      'swap-keep-not-in-program',
      'swap-keep-figure-0',
      'swap-keep-figure-1',
      'swap-keep-same-phrase-1',
      'swap-keep-with-before-1',
      'swap-more-filters',
    ]) {
      atLeast44(_inSwap(find.byKey(ValueKey(key))), key);
    }
    atLeast44(_pick('match'), 'a result');

    expect(find.bySemanticsLabel('Keep hey in A2'), findsOneWidget);
    expect(find.bySemanticsLabel('Keep circle in A1'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Keep hey in the same phrase, A2'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Keep hey right after circle'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('^Same formation: ')), findsOneWidget);
    semantics.dispose();
  });

  group('English (ECD)', () {
    testWidgets('offers type, level, not-in-program and figures without '
        'refinements, and says so', (tester) async {
      final english = _dance(
        'e1',
        'English Air',
        form: DanceForm.ecd,
        shape: FormationShape.dupleMinor,
        level: DifficultyLevel.beginnerId,
        figures: [_fig('ecd_forward_and_back', 8), _fig('ecd_circle', 8)],
      );
      await _pump(
        tester,
        extra: [english, _match],
        program: _program([
          ProgramSlot(id: 's1', position: 0, danceId: 'd1'),
          ProgramSlot(id: 'e', position: 1, danceId: 'e1'),
        ]),
        initialGroup: 0,
      );
      await _openAdjust(tester);
      await _tap(tester, find.byKey(const ValueKey('adjust-swap-e')));

      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-formation'))),
        findsNothing,
      );
      expect(_chip(tester, 'swap-keep-type').selected, isTrue);
      expect(_chip(tester, 'swap-keep-level').selected, isTrue);
      expect(_chip(tester, 'swap-keep-not-in-program').selected, isTrue);
      await _tap(
        tester,
        _inSwap(find.byKey(const ValueKey('swap-keep-figure-1'))),
      );
      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-same-phrase-1'))),
        findsNothing,
      );
      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-with-before-1'))),
        findsNothing,
      );
      expect(
        _inSwap(find.byKey(const ValueKey('swap-keep-english-note'))),
        findsOneWidget,
      );
    });
  });
}
