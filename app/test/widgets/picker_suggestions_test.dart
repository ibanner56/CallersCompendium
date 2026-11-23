// Suggested in the program builder's add-dance picker (#2343).
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
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
  slots: [ProgramSlot(id: 's0', position: 0, danceId: 'in-program')],
);

class _Harness {
  _Harness(this.enabled, this.added);
  final ValueNotifier<bool> enabled;
  final List<String> added;
}

Future<_Harness> _pump(
  WidgetTester tester,
  CompendiumRepositories repos, {
  required _SpyRanker ranker,
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
              child: CollectionPicker(
                data: data,
                dialect: Dialect.larksRobins,
                enrichment: SearchEnrichment.empty,
                onAddDance: added.add,
                programContext: programContext,
                rankSuggestions: ranker.call,
                clock: const _FixedClock(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(enabledNotifier, added);
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

  testWidgets('a picker that does not add at the end (Replace…, or an '
      'insertion) offers no Suggested', (tester) async {
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
    expect(request.slotsBefore, _context.slots);
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
        slots: [ProgramSlot(id: 's0', position: 0, danceId: 'in-program')],
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
}
