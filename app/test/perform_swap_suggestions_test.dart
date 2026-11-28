// Perform's swap sheet ordered by suggestions (#2348): Settings ▸
// Experimental ▸ Suggestions ▸ Use in Perform's Swap this dance.
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/suggestions_scope.dart';
import 'package:compendium_app/src/screens/perform_adjust_sheet.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';

import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

Figure _fig(String move, int beats) =>
    testFigure(move: move, params: {'beats': beats});

List<Figure> _figures(String a1, String a2, String b2a, String b2b) => [
  _fig(a1, 16),
  _fig(a2, 16),
  _fig('balance', 4),
  _fig('swing', 12),
  _fig(b2a, 8),
  _fig(b2b, 8),
];

/// Every dance here is a Becket contra at or below the swapped dances'
/// level, so the default Keep items (same formation, this level or easier,
/// not already in tonight's program) keep every candidate: the ordering is
/// all that differs between the cases.
Dance _dance(
  String id,
  String title,
  List<Figure> figures, {
  String level = DifficultyLevel.intermediateId,
  DanceForm form = DanceForm.contra,
}) => Dance(
  id: id,
  title: title,
  form: form,
  formation: const Formation(FormationShape.becketCw),
  difficultyLevelId: level,
  figures: figures,
  status: DanceStatus.active,
  createdAt: _now,
  updatedAt: _now,
);

final _programDances = [
  _dance(
    'd0',
    'Opener',
    _figures('petronella', 'chain', 'long_lines', 'star'),
    level: DifficultyLevel.beginnerId,
  ),
  _dance(
    'd1',
    'Current Reel',
    _figures('circle', 'hey', 'long_lines', 'allemande'),
  ),
  _dance(
    'd2',
    'Upcoming Reel',
    _figures('mad_robin', 'gate', 'promenade', 'star'),
  ),
  _dance(
    'd3',
    'Later Reel',
    _figures('circle', 'hey', 'long_lines', 'allemande'),
    level: DifficultyLevel.advancedId,
  ),
  _dance(
    'd4',
    'Late Reel',
    _figures('do_si_do', 'pull_by', 'orbit', 'circle'),
    level: DifficultyLevel.advancedId,
  ),
  _dance(
    'd5',
    'Closer',
    _figures('roll_away', 'zig_zag', 'down_the_hall', 'pass_through'),
    level: DifficultyLevel.beginnerId,
  ),
  _dance(
    'alt',
    'Backup Jig',
    _figures('circle', 'hey', 'long_lines', 'allemande'),
  ),
];

/// The candidates, in their plain (title) order. Each shares its figures
/// with one program dance, so where the swapped slot is decides which of
/// them collide with a neighbour.
final _candidates = [
  _dance(
    'a',
    'Apple Reel',
    _figures('petronella', 'chain', 'long_lines', 'star'),
    level: DifficultyLevel.beginnerId,
  ),
  _dance(
    'b',
    'Birch Reel',
    _figures('mad_robin', 'gate', 'promenade', 'star'),
    level: DifficultyLevel.beginnerId,
  ),
  _dance('c', 'Cedar Reel', _figures('do_si_do', 'pull_by', 'orbit', 'circle')),
  _dance(
    'e',
    'Elm Reel',
    _figures('box_the_gnat', 'hey', 'long_lines', 'allemande'),
  ),
  _dance(
    'g',
    'Gum Reel',
    _figures('roll_away', 'zig_zag', 'down_the_hall', 'pass_through'),
    level: DifficultyLevel.beginnerId,
  ),
];

const _plainOrder = ['a', 'b', 'c', 'e', 'g'];

/// An English dance that passes every Keep item, titled to sort among the
/// contra candidates.
final _english = _dance(
  'eng',
  'Bishop of Bangor',
  _figures('circle', 'hey', 'long_lines', 'allemande'),
  level: DifficultyLevel.beginnerId,
  form: DanceForm.ecd,
);

/// earlier (performed) · current with an alternate · upcoming × 4.
List<ProgramSlot> _slots() => [
  ProgramSlot(id: 's0', position: 0, danceId: 'd0', performedAt: _now),
  ProgramSlot(id: 's1', position: 1, danceId: 'd1'),
  ProgramSlot(id: 's1-alt', position: 2, danceId: 'alt', isAlt: true),
  ProgramSlot(id: 's2', position: 3, danceId: 'd2'),
  ProgramSlot(id: 's3', position: 4, danceId: 'd3'),
  ProgramSlot(id: 's4', position: 5, danceId: 'd4'),
  ProgramSlot(id: 's5', position: 6, danceId: 'd5'),
];

Program _program({String? venueId, String? venue}) => Program(
  id: 'p1',
  title: 'Spring Dance',
  venueId: venueId,
  venue: venue,
  slots: _slots(),
  createdAt: _now,
  updatedAt: _now,
);

/// Records each request and answers it with the real scorer, unless
/// [answer] says otherwise.
class _Ranker {
  final requests = <SuggestionRequest>[];
  Future<SuggestionRanking> Function(SuggestionRequest request)? answer;

  Future<SuggestionRanking> call(SuggestionRequest request) {
    requests.add(request);
    return answer?.call(request) ?? Future.value(rankSuggestions(request));
  }
}

class _Harness {
  _Harness(this.ranker, this.edits, this.inPerformSwap, this.suggestions);
  final _Ranker ranker;

  /// Suggestions itself, to change while the sheet is open.
  final ValueNotifier<bool> suggestions;

  /// Use in Perform's Swap this dance, to change while the sheet is open.
  final ValueNotifier<bool> inPerformSwap;

  /// What the adjust sheet reported, latest last.
  final List<Program?> edits;
}

/// The adjust sheet on the current slot `s1`, with Suggestions and Use in
/// Perform's Swap this dance as given.
Future<_Harness> _pump(
  WidgetTester tester, {
  required bool suggestions,
  required bool inPerformSwap,
  List<Dance>? candidates,
  _Ranker? ranker,
  Program? program,
  List<Venue> venues = const [],
  Dialect Function(DanceForm form)? dialectForForm,
}) async {
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = openWidgetTestDatabase();
  final repos = CompendiumRepositories(db, contraTaxonomy);
  for (final d in [..._programDances, ...(candidates ?? _candidates)]) {
    await repos.dances.create(d);
  }
  for (final venue in venues) {
    await repos.venues.upsert(venue);
  }
  final data = await CollectionData.load(repos);
  final enabled = ValueNotifier<bool>(suggestions);
  addTearDown(enabled.dispose);
  final inSwap = ValueNotifier<bool>(inPerformSwap);
  addTearDown(inSwap.dispose);
  final spy = ranker ?? _Ranker();
  final edits = <Program?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: SuggestionsEnabledScope(
          notifier: enabled,
          child: SuggestionsInPerformSwapScope(notifier: inSwap, child: child!),
        ),
      ),
      home: Scaffold(
        body: PerformAdjustSheet(
          program: program ?? _program(),
          currentGroupIndex: 1,
          currentSlotId: 's1',
          data: data,
          dialect: Dialect.larksRobins,
          dialectForForm: dialectForForm,
          enrichment: SearchEnrichment.empty,
          rankSuggestions: spy.call,
          onEdited: edits.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(spy, edits, inSwap, enabled);
}

Finder _inSwap(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('adjust-swap-sheet')),
  matching: matching,
);

/// Opens the swap sheet from [button] and lets it settle.
Future<void> _openSwap(WidgetTester tester, String button) async {
  final finder = find.byKey(ValueKey(button));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The dance ids the swap sheet lists, top to bottom: Your alternates, then
/// the results.
List<String> _shown(WidgetTester tester) => tester
    .widgetList<DanceListTile>(_inSwap(find.byType(DanceListTile)))
    .map((tile) => tile.entry.dance.id)
    .toList();

/// The results under Your alternates, when [pinned] heads the list.
List<String> _results(WidgetTester tester, {List<String> pinned = const []}) {
  final shown = _shown(tester);
  expect(shown.take(pinned.length), pinned, reason: 'Your alternates first');
  return shown.skip(pinned.length).toList();
}

Finder _reason(String id) =>
    _inSwap(find.byKey(ValueKey('suggestion-reason-$id')));

final _anyReason = _inSwap(
  find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('suggestion-reason-'),
  ),
);

/// What the scorer ranks for [position], with everything else as [sent]:
/// the program's dances as the fixture holds them, not as the request does.
List<String> _scorerOrder(
  SuggestionRequest sent,
  SuggestionPosition position,
) => rankSuggestions(
  SuggestionRequest(
    slotsBefore: position.slotsBefore,
    slotsAfter: position.slotsAfter,
    candidateIsAlternate: position.isAlternate,
    programDances: {
      for (final dance in _programDances)
        dance.id: SuggestionCandidate.fromDance(dance),
    },
    candidates: sent.candidates,
    settings: sent.settings,
    today: sent.today,
    collisionMode: sent.collisionMode,
    taxonomy: sent.taxonomy,
    matrixConfig: sent.matrixConfig,
    userFigures: sent.userFigures,
    levels: sent.levels,
    hasVenue: sent.hasVenue,
    calledHere: sent.calledHere,
  ),
).order.map((r) => r.danceId).toList();

void main() {
  // Pre-release audit finding D1b-01: a reason named the venue from the
  // program's typed venue text, not the linked venue its history was
  // counted for.
  group('a venue reason names the linked venue', () {
    for (final typed in [null, 'Old Hall']) {
      testWidgets('typed venue: $typed', (tester) async {
        final h = await _pump(
          tester,
          suggestions: true,
          inPerformSwap: true,
          program: _program(venueId: 'v1', venue: typed),
          venues: [Venue(id: 'v1', name: 'The Grange')],
        );
        await _openSwap(tester, 'adjust-swap-current');
        expect(h.ranker.requests.last.hasVenue, isTrue);
        final picker = tester.widget<CollectionPicker>(
          _inSwap(find.byType(CollectionPicker)),
        );
        expect(picker.programContext?.venueLabel, 'The Grange');

        await tester.tap(_inSwap(find.byKey(const ValueKey('picker-why-a'))));
        await tester.pumpAndSettle();
        final rows = [
          for (final text in tester.widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('suggestion-why-dialog')),
              matching: find.byType(Text),
            ),
          ))
            ?text.data,
        ];
        expect(rows, contains('Never called at The Grange'));
        expect(rows.where((r) => r.contains('a saved venue')), isEmpty);
        expect(rows.where((r) => r.contains('Old Hall')), isEmpty);
      });
    }

    testWidgets('a link that no longer resolves falls back to the typed '
        'venue', (tester) async {
      await _pump(
        tester,
        suggestions: true,
        inPerformSwap: true,
        program: _program(venueId: 'gone', venue: 'Old Hall'),
      );
      await _openSwap(tester, 'adjust-swap-current');
      final picker = tester.widget<CollectionPicker>(
        _inSwap(find.byType(CollectionPicker)),
      );
      expect(picker.programContext?.venueLabel, 'Old Hall');
    });
  });

  // Pre-release audit finding D1b-04: the swap sheet's reasons name a
  // column by the program matrix's rule (#2451), as the builder's do.
  testWidgets("a reason names a figure in its column's dialect", (
    tester,
  ) async {
    await _pump(
      tester,
      suggestions: true,
      inPerformSwap: true,
      dialectForForm: (form) =>
          form == DanceForm.ecd ? Dialect.leadsFollows : Dialect.larksRobins,
    );
    await _openSwap(tester, 'adjust-swap-current');
    final picker = tester.widget<CollectionPicker>(
      _inSwap(find.byType(CollectionPicker)),
    );
    final forColumn = picker.suggestionDialectForColumn;
    expect(forColumn, isNotNull);
    // An English figure reads in English's dialect, though the swapped
    // dance is a contra.
    expect(
      forColumn!(
        const MatrixColumn(moveId: 'ecd_set', kind: MatrixColumnKind.known),
      ),
      same(Dialect.leadsFollows),
    );
    // A contra figure reads in the dialect of the program's dances: contra.
    expect(
      forColumn(
        const MatrixColumn(moveId: 'circle', kind: MatrixColumnKind.known),
      ),
      same(Dialect.larksRobins),
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('with either setting off the swap sheet is as #2346 ships it', () {
    for (final (suggestions, inPerformSwap) in [
      (false, false),
      (false, true),
      (true, false),
    ]) {
      testWidgets('Suggestions $suggestions, Use in Perform\'s Swap this '
          'dance $inPerformSwap: the plain order, no reasons, nothing '
          'ranked', (tester) async {
        final h = await _pump(
          tester,
          suggestions: suggestions,
          inPerformSwap: inPerformSwap,
        );
        await _openSwap(tester, 'adjust-swap-current');
        expect(_results(tester, pinned: ['alt']), _plainOrder);
        expect(_anyReason, findsNothing);
        expect(h.ranker.requests, isEmpty);

        await tester.tap(_inSwap(find.byKey(const ValueKey('picker-sort'))));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sort-suggested')),
          findsNothing,
          reason: 'no Suggested in the Sort menu',
        );
      });
    }
  });

  group('with both on, the results follow the scorer for the swapped '
      'slot\'s place', () {
    for (final (button, index, pinned) in [
      ('adjust-swap-current', 1, ['alt']),
      ('adjust-swap-s2', 3, <String>[]),
    ]) {
      testWidgets('$button: after Your alternates, with a reason on each '
          'row', (tester) async {
        final h = await _pump(tester, suggestions: true, inPerformSwap: true);
        await _openSwap(tester, button);

        final sent = h.ranker.requests.last;
        final position = SuggestionPosition.replacing(_slots(), index);
        final expected = _scorerOrder(sent, position);
        // The fixture tells the positions apart: ranked for the end of the
        // program, the order would differ.
        expect(
          expected,
          isNot(_scorerOrder(sent, SuggestionPosition.atEnd(_slots()))),
          reason: 'fixture: the end of the program ranks differently',
        );
        expect(expected, isNot(_plainOrder), reason: 'fixture: not plain');

        expect(_results(tester, pinned: pinned), expected);
        for (final id in expected) {
          expect(_reason(id), findsOneWidget, reason: id);
        }
        for (final id in pinned) {
          expect(_reason(id), findsNothing, reason: 'an alternate: $id');
        }
        // The dance being swapped out is neither a neighbour nor in the
        // program it is compared with.
        final swapped = _slots()[index].danceId;
        expect(
          [...sent.slotsBefore, ...sent.slotsAfter].map((slot) => slot.danceId),
          isNot(contains(swapped)),
        );
        expect(sent.candidates.map((c) => c.id), isNot(contains(swapped)));
      });
    }

    testWidgets('the same dances show with it on or off, also when it is '
        'turned on and off with the sheet open', (tester) async {
      final h = await _pump(tester, suggestions: true, inPerformSwap: false);
      await _openSwap(tester, 'adjust-swap-current');
      final off = _shown(tester);
      expect(off, ['alt', ..._plainOrder]);

      h.inPerformSwap.value = true;
      await tester.pumpAndSettle();
      final on = _shown(tester);
      expect(on, isNot(off), reason: 'ranked, so in another order');
      expect(on, hasLength(off.length));
      expect(on.toSet(), off.toSet());
      expect(_anyReason, findsNWidgets(_plainOrder.length));

      h.inPerformSwap.value = false;
      await tester.pumpAndSettle();
      expect(_shown(tester), off, reason: 'back to the plain order');
      expect(_anyReason, findsNothing);
    });

    testWidgets('English dances are listed after the ranked ones, each saying '
        'suggestions do not cover them yet', (tester) async {
      final h = await _pump(
        tester,
        suggestions: true,
        inPerformSwap: true,
        candidates: [..._candidates, _english],
      );
      await _openSwap(tester, 'adjust-swap-current');
      final sent = h.ranker.requests.last;
      expect(
        sent.candidates.map((c) => c.id),
        contains('eng'),
        reason: 'sent to the scorer, as every result is',
      );

      final results = _results(tester, pinned: ['alt']);
      expect(results, [
        ..._scorerOrder(sent, SuggestionPosition.replacing(_slots(), 1)),
      ]);
      expect(results.last, 'eng', reason: 'after every ranked contra');
      expect(
        find.descendant(
          of: _reason('eng'),
          matching: find.text("Suggestions don't cover English dances yet"),
        ),
        findsOneWidget,
      );
    });

    testWidgets('while ranking is unfinished the plain order shows, and a tap '
        'still swaps', (tester) async {
      final ranker = _Ranker();
      final pending = Completer<SuggestionRanking>();
      ranker.answer = (_) => pending.future;
      final h = await _pump(
        tester,
        suggestions: true,
        inPerformSwap: true,
        ranker: ranker,
      );
      final swap = find.byKey(const ValueKey('adjust-swap-current'));
      await tester.ensureVisible(swap);
      await tester.pumpAndSettle();
      await tester.tap(swap);
      // Not pumpAndSettle: the ranking spinner never stops. Wait for the
      // results to be listed and ranking to be asked for.
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (ranker.requests.isNotEmpty &&
            _shown(tester).length == _plainOrder.length + 1) {
          break;
        }
      }
      expect(ranker.requests, isNotEmpty);
      expect(_results(tester, pinned: ['alt']), _plainOrder);
      expect(_anyReason, findsNothing);

      // Wait for the sheet to finish sliding up, so the row can be tapped.
      final pick = _inSwap(find.byKey(const ValueKey('picker-add-g')));
      final view = Offset.zero & tester.view.physicalSize;
      for (var i = 0; i < 200; i++) {
        if (view.contains(tester.getCenter(pick))) break;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.getSize(pick).height,
        greaterThanOrEqualTo(44),
        reason: "Perform's target size",
      );
      await tester.tap(pick);
      await tester.pump();
      final edited = h.edits.last!;
      expect(edited.slots.firstWhere((s) => s.id == 's1').danceId, 'g');
      pending.complete(const SuggestionRanking([]));
    });
  });

  // CollectionPicker.openSuggested, as the swap sheet uses it. Every ranking
  // is held by a Completer and released by the test, so nothing depends on
  // timing: the test waits for a condition, frame by frame.
  group('the swap sheet stays in Suggested', () {
    /// A ranker whose answers wait until the test releases them.
    _Ranker held(List<Completer<SuggestionRanking>> pending) =>
        _Ranker()
          ..answer = (_) {
            final completer = Completer<SuggestionRanking>();
            pending.add(completer);
            return completer.future;
          };

    /// Pumps frames until [condition] holds (the ranking spinner never lets
    /// pumpAndSettle return while a ranking is held).
    Future<void> pumpUntil(
      WidgetTester tester,
      bool Function() condition,
    ) async {
      for (var i = 0; i < 500 && !condition(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(condition(), isTrue, reason: 'the condition never held');
    }

    /// Answers held request [i] with the real scorer, then settles when no
    /// other ranking is still held.
    Future<void> release(
      WidgetTester tester,
      _Ranker ranker,
      List<Completer<SuggestionRanking>> pending,
      int i,
    ) async {
      pending[i].complete(rankSuggestions(ranker.requests[i]));
      if (pending.every((c) => c.isCompleted)) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    /// Taps a Keep chip, which sends the picker a new panel request.
    Future<void> tapKeep(WidgetTester tester, String key) async {
      await tester.tap(_inSwap(find.byKey(ValueKey(key))));
      await tester.pump();
    }

    /// The scorer's order for the swapped current slot, for [sent]'s
    /// candidates.
    List<String> scored(SuggestionRequest sent) =>
        _scorerOrder(sent, SuggestionPosition.replacing(_slots(), 1));

    /// Opens the current slot's swap sheet with a held ranker; returns once
    /// the first ranking has been asked for, still held.
    Future<(_Harness, List<Completer<SuggestionRanking>>)> open(
      WidgetTester tester, {
      bool suggestions = true,
    }) async {
      final pending = <Completer<SuggestionRanking>>[];
      final h = await _pump(
        tester,
        suggestions: suggestions,
        inPerformSwap: true,
        ranker: held(pending),
      );
      final swap = find.byKey(const ValueKey('adjust-swap-current'));
      await tester.ensureVisible(swap);
      await tester.pumpAndSettle();
      await tester.tap(swap);
      await pumpUntil(
        tester,
        () =>
            _shown(tester).length == _plainOrder.length + 1 &&
            (!suggestions || pending.isNotEmpty),
      );
      return (h, pending);
    }

    testWidgets('after a Keep change the new results are ranked again, with '
        'their reasons', (tester) async {
      final (h, pending) = await open(tester);
      await release(tester, h.ranker, pending, 0);
      expect(_results(tester, pinned: ['alt']), scored(h.ranker.requests[0]));
      expect(_anyReason, findsNWidgets(_plainOrder.length));

      // Dances already in the program join the results.
      await tapKeep(tester, 'swap-keep-not-in-program');
      await pumpUntil(tester, () => pending.length == 2);
      final sent = h.ranker.requests[1];
      expect(sent.candidates.map((c) => c.id), containsAll(['d0', 'd2']));
      await release(tester, h.ranker, pending, 1);
      final results = _results(tester, pinned: ['alt']);
      expect(results, scored(sent));
      expect(results.toSet(), sent.candidates.map((c) => c.id).toSet());
      for (final id in results) {
        expect(_reason(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('after a plain sort is picked a Keep change stays plain; '
        'Suggested picked again ranks across later Keep changes', (
      tester,
    ) async {
      final (h, pending) = await open(tester);
      await release(tester, h.ranker, pending, 0);

      await tester.tap(_inSwap(find.byKey(const ValueKey('picker-sort'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(_results(tester, pinned: ['alt']), _plainOrder);

      await tapKeep(tester, 'swap-keep-formation');
      await tester.pumpAndSettle();
      expect(pending, hasLength(1), reason: 'not ranked again');
      expect(_results(tester, pinned: ['alt']), _plainOrder);
      expect(_anyReason, findsNothing);

      await tester.tap(_inSwap(find.byKey(const ValueKey('picker-sort'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sort-suggested')));
      await pumpUntil(tester, () => pending.length == 2);
      await release(tester, h.ranker, pending, 1);
      expect(_anyReason, findsNWidgets(_plainOrder.length));

      await tapKeep(tester, 'swap-keep-not-in-program');
      await pumpUntil(tester, () => pending.length == 3);
      await release(tester, h.ranker, pending, 2);
      final sent = h.ranker.requests[2];
      expect(_results(tester, pinned: ['alt']), scored(sent));
      expect(_anyReason, findsNWidgets(sent.candidates.length));
    });

    testWidgets('a ranking that returns after a Keep change is not shown; '
        'only the new results\' ranking is', (tester) async {
      final (h, pending) = await open(tester);
      // Still held: change the Keep items first.
      await tapKeep(tester, 'swap-keep-not-in-program');
      await pumpUntil(tester, () => pending.length == 2);
      await tester.pump(const Duration(milliseconds: 16));
      final sent = h.ranker.requests[1];
      final plain = _results(tester, pinned: ['alt']);
      expect(plain.toSet(), sent.candidates.map((c) => c.id).toSet());

      // The first ranking, for the old results, comes back late.
      await release(tester, h.ranker, pending, 0);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_results(tester, pinned: ['alt']), plain, reason: 'still plain');
      expect(_anyReason, findsNothing);

      await release(tester, h.ranker, pending, 1);
      expect(_results(tester, pinned: ['alt']), scored(sent));
      expect(_anyReason, findsNWidgets(sent.candidates.length));
    });

    testWidgets('turning Suggestions on with the sheet open ranks; turning it '
        'off goes back to the plain order', (tester) async {
      final (h, pending) = await open(tester, suggestions: false);
      await tester.pumpAndSettle();
      expect(pending, isEmpty);
      expect(_results(tester, pinned: ['alt']), _plainOrder);

      h.suggestions.value = true;
      await pumpUntil(tester, () => pending.isNotEmpty);
      await release(tester, h.ranker, pending, 0);
      expect(_results(tester, pinned: ['alt']), scored(h.ranker.requests[0]));
      expect(_anyReason, findsNWidgets(_plainOrder.length));

      h.suggestions.value = false;
      await tester.pumpAndSettle();
      expect(_results(tester, pinned: ['alt']), _plainOrder);
      expect(_anyReason, findsNothing);
    });
  });
}
