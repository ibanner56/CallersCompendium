// Suggested in the program builder's pickers (#2343, #2344).
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/suggestions_scope.dart';
import 'package:compendium_app/src/search/collection_data.dart';
import 'package:compendium_app/src/widgets/collection_picker.dart';
import 'package:compendium_app/src/widgets/dance_list_tile.dart';
import 'package:compendium_app/src/widgets/picker_suggestions.dart';

import '../support/l10n_harness.dart';
import '../support/test_repositories.dart';

/// A fixed calendar day, so nothing here reads the real clock.
class _FixedClock extends SearchClock {
  const _FixedClock();

  @override
  DateTime today() => DateTime.utc(2026, 6, 15);
}

Dance _dance(String id, String title, {List<Figure> figures = const []}) =>
    Dance(
      id: id,
      title: title,
      form: DanceForm.contra,
      formation: const Formation(FormationShape.dupleImproper),
      status: DanceStatus.active,
      figures: figures,
      customFields: const [],
      hook: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Records each request and answers with [answer] (the reverse of the
/// candidates' order unless a test says otherwise).
class _SpyRanker {
  final requests = <SuggestionRequest>[];
  Future<SuggestionRanking> Function(SuggestionRequest request)? answer;

  Future<SuggestionRanking> call(SuggestionRequest request) {
    requests.add(request);
    final custom = answer;
    if (custom != null) return custom(request);
    return Future.value(_reversed(request));
  }
}

SuggestionRanking _reversed(SuggestionRequest request) => SuggestionRanking([
  for (final (i, dance) in request.candidates.reversed.indexed)
    RankedSuggestion(
      danceId: dance.id,
      score: -i.toDouble(),
      ranked: true,
      reasons: [
        // Largest effect first, as the ranker orders them.
        const SuggestionReason(
          SuggestionReasonKind.neverCalledHere,
          factor: SuggestionFactor.venueRecency,
          effect: 0.9,
        ),
        const SuggestionReason(
          SuggestionReasonKind.fitsCurve,
          factor: SuggestionFactor.difficultyCurve,
          effect: 0.5,
        ),
        SuggestionReason(
          SuggestionReasonKind.calledHereRecently,
          factor: SuggestionFactor.venueRecency,
          effect: -0.1,
          date: DateTime.utc(2026, 6, 1),
        ),
      ],
    ),
]);

final _context = PickerProgramContext(
  programId: 'p1',
  venue: 'The Grange',
  venueLabel: 'The Grange',
  position: SuggestionPosition.atEnd([
    ProgramSlot(id: 's0', position: 0, danceId: 'in-program'),
  ]),
);

class _Harness {
  _Harness(this.enabled, this.added, this.context);
  final ValueNotifier<bool> enabled;
  final List<String> added;

  /// The program context the picker is given; set it as the builder would
  /// after an add.
  final ValueNotifier<PickerProgramContext?> context;
}

Future<_Harness> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required _SpyRanker? ranker,
  bool enabled = true,
  required PickerProgramContext? programContext,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final enabledNotifier = ValueNotifier<bool>(enabled);
  addTearDown(enabledNotifier.dispose);
  final settings = ValueNotifier<SuggestionSettingsRead>((
    settings: const SuggestionSettings(),
    isNewer: false,
  ));
  addTearDown(settings.dispose);
  final added = <String>[];
  final contextNotifier = ValueNotifier<PickerProgramContext?>(programContext);
  addTearDown(contextNotifier.dispose);
  final data = await CollectionData.load(repos);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: RepositoriesScope(
          repositories: repos,
          child: SuggestionsEnabledScope(
            notifier: enabledNotifier,
            child: SuggestionSettingsScope(
              notifier: settings,
              child: ValueListenableBuilder(
                valueListenable: contextNotifier,
                builder: (context, programContext, _) => CollectionPicker(
                  data: data,
                  dialect: Dialect.larksRobins,
                  enrichment: SearchEnrichment.empty,
                  onAddDance: added.add,
                  programContext: programContext,
                  rankSuggestions: ranker?.call,
                  clock: const _FixedClock(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(enabledNotifier, added, contextNotifier);
}

Future<CompendiumRepositories> _seed() async {
  final repos = openTestRepositories();
  for (final (id, title) in [
    ('a', 'Alpha'),
    ('b', 'Bravo'),
    ('c', 'Charlie'),
    ('in-program', 'Zulu'),
  ]) {
    await repos.dances.create(_dance(id, title));
  }
  return repos;
}

List<String> _titles(WidgetTester tester) => tester
    .widgetList<DanceListTile>(find.byType(DanceListTile))
    .map((t) => t.entry.title)
    .toList();

Future<void> _openSortMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('picker-sort')));
  await tester.pumpAndSettle();
}

Future<void> _chooseSuggested(WidgetTester tester) async {
  await _openSortMenu(tester);
  await tester.tap(find.byKey(const ValueKey('sort-suggested')));
  await tester.pumpAndSettle();
}

final _reasonLines = find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('suggestion-reason-'),
);

void main() {
  testWidgets('with Suggestions off the Sort menu has no Suggested, rows have '
      'no reason line, and nothing is ranked', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    await _pump(
      tester,
      repos,
      ranker: ranker,
      enabled: false,
      programContext: _context,
    );

    await _openSortMenu(tester);
    expect(find.byKey(const ValueKey('sort-suggested')), findsNothing);
    expect(find.text('Title'), findsWidgets, reason: 'the menu is open');
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    expect(_reasonLines, findsNothing);
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(ranker.requests, isEmpty);
  });

  testWidgets('a picker with no position offers no Suggested', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    for (final context in const [
      null,
      PickerProgramContext(programId: 'p1', venue: 'The Grange'),
    ]) {
      await _pump(tester, repos, ranker: ranker, programContext: context);
      await _openSortMenu(tester);
      expect(find.byKey(const ValueKey('sort-suggested')), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
    expect(ranker.requests, isEmpty);
  });

  testWidgets('never opens in Suggested; choosing it reorders the same '
      'dances, with a reason line on each row', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    await _pump(tester, repos, ranker: ranker, programContext: _context);

    final plain = _titles(tester);
    expect(plain, ['Alpha', 'Bravo', 'Charlie', 'Zulu']);
    expect(ranker.requests, isEmpty, reason: 'the picker opens plain');
    expect(_reasonLines, findsNothing);

    await _chooseSuggested(tester);
    expect(ranker.requests, hasLength(1));
    final request = ranker.requests.single;
    expect(request.slotsBefore, _context.position!.slotsBefore);
    expect(request.slotsAfter, isEmpty);
    expect(request.candidateIsAlternate, isFalse);
    expect(request.hasVenue, isTrue);
    expect(request.today, DateTime.utc(2026, 6, 15));
    expect(request.candidates.map((d) => d.id), ['a', 'b', 'c', 'in-program']);

    expect(_titles(tester), ['Zulu', 'Charlie', 'Bravo', 'Alpha']);
    expect(_titles(tester).toSet(), plain.toSet());
    expect(_reasonLines, findsNWidgets(4));
    // The top two reasons that moved it.
    expect(
      find.text('Never called at The Grange · Fits the difficulty curve here'),
      findsNWidgets(4),
    );
    expect(
      find.byKey(const ValueKey('picker-sort-direction')),
      findsNothing,
      reason: 'a ranking has no direction',
    );
  });

  testWidgets('Why? lists every reason that moved the dance', (tester) async {
    final repos = await _seed();
    await _pump(tester, repos, ranker: _SpyRanker(), programContext: _context);
    await _chooseSuggested(tester);

    await tester.tap(find.byKey(const ValueKey('picker-why-b')));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('suggestion-why-dialog'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Why Bravo')),
      findsOneWidget,
    );
    for (final text in [
      'Never called at The Grange',
      'Fits the difficulty curve here',
      'Called at The Grange on',
    ]) {
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining(text, findRichText: true),
        ),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('while ranking is pending the plain order shows and a tap still '
      'adds the dance', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    final pending = Completer<SuggestionRanking>();
    ranker.answer = (_) => pending.future;
    final harness = await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: _context,
    );

    await _openSortMenu(tester);
    await tester.tap(find.byKey(const ValueKey('sort-suggested')));
    // Not pumpAndSettle: the pending spinner animates.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ranker.requests, hasLength(1));
    expect(_titles(tester), ['Alpha', 'Bravo', 'Charlie', 'Zulu']);
    expect(_reasonLines, findsNothing);

    await tester.tap(find.byKey(const ValueKey('picker-add-b')));
    await tester.pump();
    expect(harness.added, ['b']);

    pending.complete(_reversed(ranker.requests.single));
    await tester.pumpAndSettle();
    expect(_titles(tester), ['Zulu', 'Charlie', 'Bravo', 'Alpha']);
  });

  testWidgets('Suggested stays chosen across a new search, re-ranking the new '
      'results, until another sort is chosen', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    await _pump(tester, repos, ranker: ranker, programContext: _context);
    await _chooseSuggested(tester);

    await tester.enterText(
      find.byKey(const ValueKey('picker-search')),
      'Bravo',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(ranker.requests, hasLength(2));
    expect(ranker.requests.last.candidates.map((d) => d.id), ['b']);
    expect(_titles(tester), ['Bravo']);
    expect(_reasonLines, findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('picker-search')), '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(ranker.requests, hasLength(3));
    expect(_titles(tester), ['Zulu', 'Charlie', 'Bravo', 'Alpha']);

    await _openSortMenu(tester);
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    expect(_reasonLines, findsNothing);
    final titles = _titles(tester);
    expect(titles, [...titles]..sort());
  });

  testWidgets('turning Suggestions off returns an open picker to the plain '
      'order', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    final harness = await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: _context,
    );
    await _chooseSuggested(tester);
    expect(_titles(tester).first, 'Zulu');

    harness.enabled.value = false;
    await tester.pumpAndSettle();
    expect(_titles(tester), ['Alpha', 'Bravo', 'Charlie', 'Zulu']);
    expect(_reasonLines, findsNothing);
    await _openSortMenu(tester);
    expect(find.byKey(const ValueKey('sort-suggested')), findsNothing);
  });

  testWidgets('with the real ranker, a program with no venue says the venue '
      'factor was skipped', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker()
      ..answer = (request) async => rankSuggestions(request);
    await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: PickerProgramContext(
        programId: 'p1',
        position: SuggestionPosition.atEnd([
          ProgramSlot(id: 's0', position: 0, danceId: 'in-program'),
        ]),
      ),
    );
    await _chooseSuggested(tester);
    expect(ranker.requests.single.hasVenue, isFalse);
    expect(_titles(tester), hasLength(4));

    await tester.tap(find.byKey(const ValueKey('picker-why-a')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('suggestion-why-dialog')),
        matching: find.textContaining('the program has no venue'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed ranking keeps the plain order and says so', (
    tester,
  ) async {
    final repos = await _seed();
    final ranker = _SpyRanker()
      ..answer = (_) => Future.error(StateError('worker lost'));
    await _pump(tester, repos, ranker: ranker, programContext: _context);
    await _chooseSuggested(tester);

    expect(ranker.requests, hasLength(1));
    expect(_titles(tester), ['Alpha', 'Bravo', 'Charlie', 'Zulu']);
    final notice = find.byKey(const ValueKey('picker-suggested-failed'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.text(
          "Couldn't rank these dances, so they're in their usual order.",
        ),
      ),
      findsOneWidget,
    );

    // Another sort clears it.
    await _openSortMenu(tester);
    await tester.tap(find.text('Title').last);
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
  });

  testWidgets('a linked venue with no name to show reads as "a saved venue", '
      'never as a blank', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker()
      ..answer = (request) async => SuggestionRanking([
        for (final c in request.candidates)
          RankedSuggestion(
            danceId: c.id,
            score: 0,
            ranked: true,
            reasons: const [
              SuggestionReason(
                SuggestionReasonKind.neverCalledHere,
                factor: SuggestionFactor.venueRecency,
                effect: 0.9,
              ),
            ],
          ),
      ]);
    await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: PickerProgramContext(
        programId: 'p1',
        venueId: 'venue-1',
        position: SuggestionPosition.atEnd([
          ProgramSlot(id: 's0', position: 0, danceId: 'in-program'),
        ]),
      ),
    );
    await _chooseSuggested(tester);
    expect(ranker.requests.single.hasVenue, isTrue);
    expect(find.text('Never called at a saved venue'), findsNWidgets(4));
    expect(find.textContaining('Never called at ·'), findsNothing);
  });

  testWidgets('the phrase-rule overlap and the already-in-program reasons have '
      'their own words', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker()
      ..answer = (request) async => SuggestionRanking([
        for (final c in request.candidates)
          RankedSuggestion(
            danceId: c.id,
            score: 0,
            ranked: true,
            reasons: const [
              SuggestionReason(
                SuggestionReasonKind.alreadyInProgram,
                effect: alreadyInProgramEffect,
              ),
              SuggestionReason(
                SuggestionReasonKind.phraseOverlap,
                factor: SuggestionFactor.matrixVariety,
                effect: -1,
                count: 1,
                moveKey: 'circle',
                neighbor: SuggestionNeighbor.previous,
              ),
            ],
          ),
      ]);
    await _pump(tester, repos, ranker: ranker, programContext: _context);
    await _chooseSuggested(tester);
    expect(
      find.textContaining(
        RegExp(
          r'^Already in this program · .+ in the same phrase as the previous '
          r'dance$',
        ),
      ),
      findsNWidgets(4),
    );
  });

  testWidgets('the add-dance picker\'s Last called sort leaves out the program '
      'being built, as its Called filter does', (tester) async {
    final repos = await _seed();
    Program program(String id, String danceId, int month) => Program(
      id: id,
      title: id,
      eventDate: DateTime.utc(2026, month),
      slots: [ProgramSlot(id: '$id-s', position: 0, danceId: danceId)],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    // "Charlie" was called in March; "Bravo" only in the program being built.
    await repos.programs.create(program('march', 'c', 3));
    await repos.programs.create(program('p1', 'b', 5));
    await _pump(tester, repos, ranker: _SpyRanker(), programContext: _context);

    await _openSortMenu(tester);
    await tester.tap(find.text('Last called').last);
    await tester.pumpAndSettle();
    expect(_titles(tester).first, 'Charlie');
  });

  testWidgets('with no ranker given, the picker ranks on its own worker '
      'isolate', (tester) async {
    final repos = await _seed();
    await _pump(tester, repos, ranker: null, programContext: _context);
    await _openSortMenu(tester);
    await tester.tap(find.byKey(const ValueKey('sort-suggested')));
    await tester.pump();
    // The worker is a real isolate: give it real time.
    for (var i = 0; i < 100 && _reasonLines.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(_reasonLines, findsNWidgets(4));
    // "Zulu" is the program's only dance: it is already in the program.
    expect(_titles(tester).last, 'Zulu');
    expect(find.textContaining('Already in this program'), findsOneWidget);
    // Close the picker: the worker stops with it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a re-rank that fails after an add drops the earlier Suggested '
      'order, so the notice tells the truth', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    final harness = await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: _context,
    );
    await _chooseSuggested(tester);
    expect(_titles(tester), ['Zulu', 'Charlie', 'Bravo', 'Alpha']);

    // "Bravo" is added: the builder passes the longer program, the results
    // stay the same, and the re-rank fails.
    ranker.answer = (_) => Future.error(StateError('worker lost'));
    harness.context.value = PickerProgramContext(
      programId: 'p1',
      venue: 'The Grange',
      venueLabel: 'The Grange',
      position: SuggestionPosition.atEnd([
        ..._context.position!.slotsBefore,
        ProgramSlot(id: 's1', position: 1, danceId: 'b'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(ranker.requests, hasLength(2));
    expect(_titles(tester), ['Alpha', 'Bravo', 'Charlie', 'Zulu']);
    expect(_reasonLines, findsNothing);
    expect(
      find.byKey(const ValueKey('picker-suggested-failed')),
      findsOneWidget,
    );
  });

  testWidgets('a ranking replaced by a newer one is not a failure', (
    tester,
  ) async {
    final repos = await _seed();
    final ranker = _SpyRanker()
      ..answer = (_) => Future.error(const SuggestionRankSuperseded());
    await _pump(tester, repos, ranker: ranker, programContext: _context);
    await _chooseSuggested(tester);
    expect(find.byKey(const ValueKey('picker-suggested-failed')), findsNothing);
  });

  // --- A position inside the program (#2344) --------------------------------

  /// The in-program dance's slot, "Zulu".
  final s0 = ProgramSlot(id: 's0', position: 0, danceId: 'in-program');
  PickerProgramContext contextAt(SuggestionPosition position) =>
      PickerProgramContext(
        programId: 'p1',
        venue: 'The Grange',
        venueLabel: 'The Grange',
        position: position,
      );

  testWidgets('an add before a slot and Replace… send their position to the '
      'ranker', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    final alt = ProgramSlot(id: 's1', position: 1, danceId: 'c', isAlt: true);
    final harness = await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: contextAt(
        SuggestionPosition.inserting([s0], 0, after: false),
      ),
    );
    await _chooseSuggested(tester);
    expect(ranker.requests.single.slotsBefore, isEmpty);
    expect(ranker.requests.single.slotsAfter, [s0]);
    expect(ranker.requests.single.candidateIsAlternate, isFalse);
    expect(ranker.requests.single.programDances.keys, ['in-program']);

    harness.context.value = contextAt(
      SuggestionPosition.replacing([s0, alt], 1),
    );
    await tester.pumpAndSettle();
    expect(ranker.requests, hasLength(2));
    expect(ranker.requests.last.slotsBefore, [s0]);
    expect(ranker.requests.last.slotsAfter, isEmpty);
    expect(ranker.requests.last.candidateIsAlternate, isTrue);
  });

  testWidgets('a new position shows the plain order until it is ranked: a '
      'ranking for one place never shows for another', (tester) async {
    final repos = await _seed();
    final ranker = _SpyRanker();
    final pending = <Completer<SuggestionRanking>>[];
    ranker.answer = (_) {
      final completer = Completer<SuggestionRanking>();
      pending.add(completer);
      return completer.future;
    };
    const plain = ['Alpha', 'Bravo', 'Charlie', 'Zulu'];
    const reversed = ['Zulu', 'Charlie', 'Bravo', 'Alpha'];
    final harness = await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: _context,
    );
    await _openSortMenu(tester);
    await tester.tap(find.byKey(const ValueKey('sort-suggested')));
    await tester.pump();
    pending.single.complete(_reversed(ranker.requests.single));
    await tester.pump();
    expect(_titles(tester), reversed, reason: 'ranked for the end');
    expect(_reasonLines, findsNWidgets(4));

    // The builder starts an add before Zulu: same results, new position.
    harness.context.value = contextAt(
      SuggestionPosition.inserting([s0], 0, after: false),
    );
    await tester.pump();
    expect(ranker.requests, hasLength(2));
    expect(ranker.requests.last.slotsAfter, [s0]);
    expect(_titles(tester), plain, reason: 'the end ranking is not shown');
    expect(_reasonLines, findsNothing);

    // Before that ranks, the target moves to Replace… of Zulu.
    harness.context.value = contextAt(SuggestionPosition.replacing([s0], 0));
    await tester.pump();
    expect(ranker.requests, hasLength(3));
    // The add-before ranking comes back late: it is for another place.
    pending[1].complete(_reversed(ranker.requests[1]));
    await tester.pump();
    expect(_titles(tester), plain);
    expect(_reasonLines, findsNothing);
    // Ranked for the slot Replace… fills: shown.
    pending[2].complete(
      SuggestionRanking([
        for (final c in ranker.requests[2].candidates)
          RankedSuggestion(
            danceId: c.id,
            score: 0,
            ranked: true,
            reasons: const [
              SuggestionReason(SuggestionReasonKind.noFactorApplied),
            ],
          ),
      ]),
    );
    await tester.pump();
    expect(_titles(tester), plain);
    expect(_reasonLines, findsNWidgets(4));

    // Cancel: back to the end, which ranks again.
    harness.context.value = _context;
    await tester.pump();
    expect(ranker.requests, hasLength(4));
    expect(ranker.requests.last.slotsAfter, isEmpty);
    expect(_reasonLines, findsNothing);
    pending[3].complete(_reversed(ranker.requests[3]));
    await tester.pump();
    expect(_titles(tester), reversed);
  });

  testWidgets('an overlap or formation reason names the neighbour and its '
      'side, and falls back to "the previous/next dance" without a name', (
    tester,
  ) async {
    final repos = await _seed();
    SuggestionReason reason(
      SuggestionReasonKind kind,
      SuggestionNeighbor side,
      String? danceId,
    ) => SuggestionReason(
      kind,
      factor: SuggestionFactor.matrixVariety,
      effect: -1,
      count: 1,
      moveKey: 'circle',
      formation: FormationShape.becketCw,
      neighbor: side,
      neighborDanceId: danceId,
    );
    final byDance = {
      'a': [
        reason(
          SuggestionReasonKind.beatOverlap,
          SuggestionNeighbor.previous,
          'in-program',
        ),
      ],
      'b': [
        reason(
          SuggestionReasonKind.phraseOverlap,
          SuggestionNeighbor.next,
          'in-program',
        ),
      ],
      'c': [
        reason(
          SuggestionReasonKind.sameFormationAsNeighbor,
          SuggestionNeighbor.next,
          'in-program',
        ),
      ],
      'in-program': [
        reason(
          SuggestionReasonKind.beatOverlap,
          SuggestionNeighbor.next,
          'no-such-dance',
        ),
      ],
    };
    final ranker = _SpyRanker()
      ..answer = (request) async => SuggestionRanking([
        for (final c in request.candidates)
          RankedSuggestion(
            danceId: c.id,
            score: 0,
            ranked: true,
            reasons: byDance[c.id]!,
          ),
      ]);
    await _pump(
      tester,
      repos,
      ranker: ranker,
      programContext: contextAt(
        SuggestionPosition.inserting([s0], 0, after: false),
      ),
    );
    await _chooseSuggested(tester);
    String line(String id) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('suggestion-reason-$id')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(line('a'), matches(RegExp(r'^Same .+ beats as Zulu, after it$')));
    expect(
      line('b'),
      matches(RegExp(r'^.+ in the same phrase as Zulu, before it$')),
    );
    expect(line('c'), matches(RegExp(r'^.+, like Zulu, before it$')));
    expect(
      line('in-program'),
      matches(RegExp(r'^Same .+ beats as the next dance$')),
    );
  });

  testWidgets('with the real worker, moving the position re-ranks the held '
      'candidates for the new place', (tester) async {
    final repos = openTestRepositories();
    Figure fig(String move, int beats) =>
        testFigure(move: move, params: {'beats': beats});
    await repos.dances.create(
      _dance('n', 'Chorus Jig', figures: [fig('circle', 16), fig('swing', 16)]),
    );
    await repos.dances.create(
      _dance(
        'x',
        'Overlapping',
        figures: [fig('petronella', 16), fig('swing', 16)],
      ),
    );
    await repos.dances.create(
      _dance('y', 'Clean', figures: [fig('swing', 16), fig('petronella', 16)]),
    );
    final slots = [ProgramSlot(id: 'sn', position: 0, danceId: 'n')];
    final harness = await _pump(
      tester,
      repos,
      ranker: null,
      programContext: contextAt(
        SuggestionPosition.inserting(slots, 0, after: false),
      ),
    );
    await _openSortMenu(tester);
    await tester.tap(find.byKey(const ValueKey('sort-suggested')));
    await tester.pump();

    final overlapLine = find.descendant(
      of: find.byKey(const ValueKey('suggestion-reason-x')),
      matching: find.byType(Text),
    );
    String? lineOf() => overlapLine.evaluate().isEmpty
        ? null
        : tester.widget<Text>(overlapLine).data;

    /// Pumps until [done], with real time for the worker isolate, failing
    /// after a deadline rather than waiting on a fixed delay.
    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'condition not reached by the deadline');
    }

    await until(() => lineOf()?.contains('Chorus Jig, before it') ?? false);
    expect(
      _titles(tester).indexOf('Clean'),
      lessThan(_titles(tester).indexOf('Overlapping')),
    );

    // The add is cancelled: the end of the program, after Chorus Jig.
    harness.context.value = contextAt(SuggestionPosition.atEnd(slots));
    await tester.pump();
    expect(lineOf(), isNull, reason: 'the add-before ranking is not shown');
    await until(() => lineOf()?.contains('Chorus Jig, after it') ?? false);

    // Close the picker: the worker stops with it.
    await tester.pumpWidget(const SizedBox());
  });
}
