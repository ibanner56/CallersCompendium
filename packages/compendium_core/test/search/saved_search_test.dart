import 'dart:convert';
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import 'filter_describe.dart';

void main() {
  final today = DateTime.utc(2026, 11, 22);

  final choiceField = CustomFieldDef(
    id: 'diff',
    key: 'difficulty',
    label: 'Difficulty',
    type: CustomFieldType.choice,
    choices: const ['easy', 'hard'],
  );
  final boolField = CustomFieldDef(
    id: 'teach',
    key: 'needsTeaching',
    label: 'Needs teaching',
    type: CustomFieldType.boolean,
  );
  final textField = CustomFieldDef(
    id: 'note',
    key: 'notes',
    label: 'Notes',
    type: CustomFieldType.text,
    searchable: true,
  );
  final numberField = CustomFieldDef(
    id: 'num',
    key: 'count',
    label: 'Count',
    type: CustomFieldType.number,
    searchable: true,
  );
  final defs = [choiceField, boolField, textField, numberField];

  SavedSearchContext context({
    DateTime? day,
    Set<String> tags = const {'t1', 't2', 'S'},
    Set<String> authors = const {'a1'},
    Set<String> sources = const {'s1'},
    Set<String> levels = const {'l1'},
    Set<String> venues = const {'v1'},
    Set<String> userFigures = const {'uf1'},
    List<CustomFieldDef>? fields,
    Map<SyncRecordKind, Map<String, String>> aliases = const {},
    bool performedOnly = false,
    CallingHistoryTracking tracking = CallingHistoryTracking.defaults,
    String? programId,
  }) => SavedSearchContext(
    today: day ?? today,
    taxonomy: contraTaxonomy,
    tagIds: tags,
    authorIds: authors,
    sourceIds: sources,
    levelIds: levels,
    venueIds: venues,
    userFigureIds: userFigures,
    customFieldDefs: fields ?? defs,
    aliases: aliases,
    performedOnly: performedOnly,
    tracking: tracking,
    currentProgramId: programId,
  );

  /// A state touching every part of the format.
  CollectionPanelState rich() {
    final s = CollectionPanelState(
      text: 'petronella',
      scope: FullTextScope.title,
      sort: CollectionSort.lastCalled,
      sortDirection: SortDirection.ascending,
    );
    final f = s.facets
      ..forms.add(DanceForm.contra)
      ..formations.add(FormationShape.values.first)
      ..progressions.add(Progression.double)
      ..statuses.add(DanceStatus.active)
      ..levels.add('l1')
      ..mixedLevel = true
      ..mixer = true
      ..callStatuses.add(false)
      ..setHistoryVenue(VenueKey.record('v1'))
      ..setHistoryMonths(12)
      ..minRating = 3
      ..authorIds.add('a1')
      ..sourceIds.add('s1')
      ..meters.add('6/8')
      ..musicalKeys.add('D minor')
      ..choiceValues['diff'] = {'easy', 'hard'}
      ..booleanValues['teach'] = true
      ..textValues['note'] = const TextFacetState(
        op: CustomFieldOp.contains,
        value: 'fun',
      )
      ..numberValues['num'] = const NumberFacetState(
        op: CustomFieldOp.between,
        lo: 1,
        hi: 4.5,
      );
    f.setTag('t1', selected: true);
    f.setTag('t2', selected: true);
    f.tagsMatchAll = false;
    f.untagged = true;
    f.addTune('Dmaj');
    f.addTune('6/8');
    s.byPhrase.match['A1'] = ['swing'];
    s.byPhrase.exclude['B2'] = ['star'];
    s.advanced
      ..kind = GroupKind.all
      ..children.addAll([
        BuilderFigure(move: 'balance', params: {'who': 'ones'}),
        BuilderTag(tagId: 't1'),
        BuilderThen(
          before: BuilderFigure(move: 'swing'),
          after: BuilderFigureGroup(
            kind: GroupKind.none,
            children: [BuilderFigure(move: 'star')],
          ),
        ),
        BuilderGroup(
          kind: GroupKind.none,
          children: [
            BuilderFigure(move: 'allemande', params: {'hand': 'right'}),
          ],
        ),
      ]);
    return s;
  }

  SavedSearchSpec specOf(CollectionPanelState s, {DateTime? day}) {
    final built = SavedSearchSpec.fromPanelState(s, today: day ?? today);
    expect(built.problem, isNull);
    return built.value!;
  }

  DanceFilter filterOf(CollectionPanelState s, {DateTime? day}) =>
      buildCollectionFilter(
        ftsText: s.text,
        facets: s.facets,
        defs: defs,
        scope: s.scope,
        byPhrase: s.byPhrase,
        advancedRoot: s.advanced,
        today: day ?? today,
      );

  Object? viaJson(Object? json) => jsonDecode(jsonEncode(json));

  group('saved search codec', () {
    test('round-trips every part of the panel state, and the same search', () {
      final original = rich();
      final spec = specOf(original);
      final decoded = SavedSearchSpec.decode(viaJson(spec.toJson()));
      expect(decoded.problem, isNull);
      final back = decoded.value!.toPanelState();

      expect(back.text, 'petronella');
      expect(back.scope, FullTextScope.title);
      expect(back.sort, CollectionSort.lastCalled);
      expect(back.sortDirection, SortDirection.ascending);
      expect(back.facets.tagsMatchAll, isFalse);
      expect(back.facets.untagged, isTrue);
      expect(back.facets.tunes, ['Dmaj', '6/8']);
      expect(back.facets.historyVenue, VenueKey.record('v1'));
      expect(back.facets.historyMonths, 12);
      expect(
        describeFilter(filterOf(back)),
        describeFilter(filterOf(original)),
      );
    });

    test('a state read from a saved search says so; one built does not', () {
      // A Within window outside the presets reads "12 months, saved" only
      // for a saved search.
      expect(CollectionPanelState().fromSavedSearch, isFalse);
      expect(specOf(rich()).toPanelState().fromSavedSearch, isTrue);
    });

    test('keeps sort direction (a stored Z-to-A order restores)', () {
      final s = CollectionPanelState(
        text: 'x',
        sort: CollectionSort.title,
        sortDirection: SortDirection.descending,
      );
      final back = SavedSearchSpec.decode(
        viaJson(specOf(s).toJson()),
      ).value!.toPanelState();
      expect(back.sortDirection, SortDirection.descending);
    });

    test('keeps "match any tag" (omitting it changes which dances match)', () {
      final s = CollectionPanelState();
      s.facets
        ..setTag('t1', selected: true)
        ..setTag('t2', selected: true)
        ..tagsMatchAll = false;
      final back = SavedSearchSpec.decode(
        viaJson(specOf(s).toJson()),
      ).value!.toPanelState();
      expect(back.facets.tagsMatchAll, isFalse);
      expect(describeFilter(filterOf(back)), describeFilter(filterOf(s)));
    });

    test('is byte-stable and does not depend on insertion order', () {
      CollectionPanelState build(List<String> tags) {
        final s = CollectionPanelState();
        for (final t in tags) {
          s.facets.setTag(t, selected: true);
        }
        s.facets.levels.addAll(tags.reversed);
        return s;
      }

      final a = jsonEncode(specOf(build(['t2', 't1'])).toJson());
      final b = jsonEncode(specOf(build(['t1', 't2'])).toJson());
      expect(a, b);
    });

    test('never stores builder ids (they are session counters)', () {
      final json = jsonEncode(specOf(rich()).toJson());
      expect(json, isNot(contains('"id"')));
      expect(json, isNot(matches(RegExp(r'"n\d+"|"fg\d+"'))));
      final a = SavedSearchSpec.decode(
        viaJson(specOf(rich()).toJson()),
      ).value!.toPanelState();
      final b = SavedSearchSpec.decode(
        viaJson(specOf(rich()).toJson()),
      ).value!.toPanelState();
      expect(a.advanced.children.first.id, isNot(b.advanced.children.first.id));
    });

    test('a bare name-only value has no query', () {
      final spec = specOf(CollectionPanelState());
      expect(spec.toPanelState().hasQuery, isFalse);
    });
  });

  group('history window is a distance, never a date', () {
    test('a chosen date saves as whole months back, and no date', () {
      final s = CollectionPanelState();
      s.facets
        ..callStatuses.add(false)
        ..setHistorySince(DateTime.utc(2025, 11, 22));
      final json = jsonEncode(specOf(s).toJson());
      expect((specOf(s).toJson()['facets'] as Map)['historyMonths'], 12);
      expect(json, isNot(contains('2025')));
      expect(json, isNot(contains('historySince')));
    });

    test('a preset saves as its N', () {
      final s = CollectionPanelState();
      s.facets
        ..callStatuses.add(true)
        ..setHistoryMonths(3);
      expect((specOf(s).toJson()['facets'] as Map)['historyMonths'], 3);
    });

    final cases = <(DateTime since, DateTime today, int months)>[
      (DateTime.utc(2025, 11, 22), DateTime.utc(2026, 11, 22), 12),
      // 11 months and 22 days: floor, not round.
      (DateTime.utc(2025, 11, 30), DateTime.utc(2026, 11, 22), 11),
      // Three weeks ago saves as 1, never "today only".
      (DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 22), 1),
      // A date in the future is also 1.
      (DateTime.utc(2026, 12, 1), DateTime.utc(2026, 11, 22), 1),
      // The window must not start before the chosen date (end-of-month clamp).
      (DateTime.utc(2025, 1, 31), DateTime.utc(2026, 2, 28), 12),
      (DateTime.utc(2024, 2, 29), DateTime.utc(2026, 2, 28), 23),
    ];
    for (final (since, day, months) in cases) {
      test('$since as of $day is $months months', () {
        expect(monthsBackFromDate(since, day), months);
        // Floor: the saved window never starts before the chosen date, except
        // where the minimum of 1 month widens a date that is under a month
        // back (or ahead).
        final atLeastAMonth = !calendarMonthsBefore(day, 1).isBefore(since);
        if (atLeastAMonth) {
          expect(calendarMonthsBefore(day, months).isBefore(since), isFalse);
        }
      });
    }
  });

  group('sort', () {
    test('Best match is stored and read, not rejected as a default', () {
      final s = CollectionPanelState(
        text: 'al',
        sort: CollectionSort.relevance,
      );
      final back = SavedSearchSpec.decode(
        viaJson(specOf(s).toJson()),
      ).value!.toPanelState();
      expect(back.sort, CollectionSort.relevance);
      expect(back.effectiveSort.sort, CollectionSort.relevance);
    });

    test('Best match that is no longer offered falls back to Title', () {
      final s = CollectionPanelState(
        text: 'al',
        sort: CollectionSort.relevance,
      );
      final back = SavedSearchSpec.decode(
        viaJson(specOf(s).toJson()),
      ).value!.toPanelState();
      back.text = '';
      expect(back.effectiveSort.sort, CollectionSort.title);
      expect(
        back.effectiveSort.direction,
        CollectionSort.title.searchSort.defaultDirection,
      );
      back.text = 'al';
      back.facets.mixer = true;
      expect(back.effectiveSort.sort, CollectionSort.title);
    });
  });

  group('hostile or unknown stored values are unreadable, never thrown', () {
    Map<String, Object?> valid() =>
        viaJson(specOf(rich()).toJson()) as Map<String, Object?>;

    Object? nested(int depth) {
      Object? node = {'t': 'group', 'kind': 'all'};
      for (var i = 1; i < depth; i++) {
        node = {
          't': 'group',
          'kind': 'all',
          'children': [node],
        };
      }
      return node;
    }

    final bad = <String, Object?>{
      'not an object': 'x',
      'a list': <Object?>[],
      'null': null,
      'no version': {'sort': 'title'},
      'a newer version': {'v': 2},
      'version as text': {'v': '1'},
      'an unknown top-level key': {'v': 1, 'extra': 1},
      'text that is not text': {'v': 1, 'text': 4},
      'text over the limit': {'v': 1, 'text': 'x' * 501},
      'an unknown sort': {'v': 1, 'sort': 'rainbow'},
      'an unknown scope': {'v': 1, 'scope': 'everywhere'},
      'an unknown direction': {'v': 1, 'sortDirection': 'sideways'},
      'an unknown facet key': {
        'v': 1,
        'facets': {'nope': 1},
      },
      'a facet that is not a list': {
        'v': 1,
        'facets': {'tagIds': 'x'},
      },
      'a facet list with a number': {
        'v': 1,
        'facets': {
          'tagIds': [3],
        },
      },
      'an unknown dance form': {
        'v': 1,
        'facets': {
          'forms': ['polka'],
        },
      },
      'a zero month window': {
        'v': 1,
        'facets': {'historyMonths': 0},
      },
      'a month window as text': {
        'v': 1,
        'facets': {'historyMonths': '3'},
      },
      'a venue that is not a key': {
        'v': 1,
        'facets': {'historyVenue': 'Grange'},
      },
      'a rating of 9': {
        'v': 1,
        'facets': {'minRating': 9},
      },
      'between without hi': {
        'v': 1,
        'facets': {
          'numberValues': {
            'num': {'op': 'between', 'lo': 1},
          },
        },
      },
      'hi without between': {
        'v': 1,
        'facets': {
          'numberValues': {
            'num': {'op': 'eq', 'lo': 1, 'hi': 2},
          },
        },
      },
      'a text op that is not text': {
        'v': 1,
        'facets': {
          'textValues': {
            'note': {'op': 'between', 'value': 'x'},
          },
        },
      },
      'advanced nested 9 deep': {'v': 1, 'advanced': nested(9)},
      'advanced root that is a row': {
        'v': 1,
        'advanced': {'t': 'tag', 'tagId': 't1'},
      },
      'an unknown row type': {
        'v': 1,
        'advanced': {
          't': 'group',
          'kind': 'all',
          'children': [
            {'t': 'wormhole'},
          ],
        },
      },
      'a param key the filter would reject': {
        'v': 1,
        'advanced': {
          't': 'group',
          'kind': 'all',
          'children': [
            {
              't': 'figure',
              'move': 'swing',
              'params': {'1bad': 'x'},
            },
          ],
        },
      },
      'a null param value': {
        'v': 1,
        'advanced': {
          't': 'group',
          'kind': 'all',
          'children': [
            {
              't': 'figure',
              'move': 'swing',
              'params': {'who': null},
            },
          ],
        },
      },
      'over 200 rows': {
        'v': 1,
        'advanced': {
          't': 'group',
          'kind': 'all',
          'children': [
            for (var i = 0; i < 100; i++)
              {
                't': 'group',
                'kind': 'any',
                'children': [
                  {'t': 'tag', 'tagId': 'a'},
                  {'t': 'tag', 'tagId': 'b'},
                ],
              },
          ],
        },
      },
      'over 64 KiB': {
        'v': 1,
        'facets': {'tunes': List.filled(200, 'x' * 400)},
      },
    };
    bad.forEach((name, value) {
      test(name, () {
        final result = SavedSearchSpec.decode(value);
        expect(result.isOk, isFalse, reason: name);
        expect(result.problem, isNotEmpty);
      });
    });

    test('depth 8 is still readable (the limit is exact)', () {
      expect(
        SavedSearchSpec.decode({'v': 1, 'advanced': nested(8)}).isOk,
        isTrue,
      );
    });

    test('random garbage never throws', () {
      final random = Random(2325);
      Object? junk(int depth) {
        switch (random.nextInt(depth > 3 ? 5 : 8)) {
          case 0:
            return random.nextInt(2000) - 1000;
          case 1:
            return random.nextDouble();
          case 2:
            return 'k${random.nextInt(50)}';
          case 3:
            return random.nextBool();
          case 4:
            return null;
          case 5:
            return [
              for (var i = 0; i < random.nextInt(4); i++) junk(depth + 1),
            ];
          default:
            return {
              for (var i = 0; i < random.nextInt(5); i++)
                [
                  'v',
                  'text',
                  'facets',
                  'advanced',
                  't',
                  'kind',
                  'children',
                  'tagIds',
                  'params',
                  'k${random.nextInt(9)}',
                ][random.nextInt(10)]: junk(
                  depth + 1,
                ),
            };
        }
      }

      for (var i = 0; i < 3000; i++) {
        final base = valid();
        final value = random.nextBool()
            ? junk(0)
            : (base..addAll({'junk': junk(2)}));
        expect(() => SavedSearchSpec.decode(value), returnsNormally);
        expect(() => SavedSearch.decode('id', value), returnsNormally);
      }
    });

    test('a saved search needs a usable name', () {
      final spec = specOf(rich());
      SavedSearch search(String name) =>
          SavedSearch(id: 'x', name: name, spec: spec);
      expect(
        SavedSearch.decode('x', viaJson(search('Easy mixers').toJson())).isOk,
        isTrue,
      );
      for (final name in ['', '   ', 'n' * 101]) {
        expect(
          SavedSearch.decode('x', viaJson(search(name).toJson())).isOk,
          isFalse,
          reason: '"$name"',
        );
      }
      expect(SavedSearch.decode('x', {...valid(), 'name': 4}).isOk, isFalse);
      final read = SavedSearch.decode('x', viaJson(search('A').toJson()));
      expect(read.value!.id, 'x');
      expect(read.value!.name, 'A');
    });
  });

  group('VenueKey.fromStorageKey', () {
    test('reads what storageKey writes', () {
      for (final key in [VenueKey.record('v1'), VenueKey.typed('The Grange')]) {
        expect(VenueKey.fromStorageKey(key.storageKey), key);
      }
    });

    test('refuses anything else', () {
      for (final s in [
        '',
        'id:',
        'id: ',
        'text:',
        'Grange',
        'x:1',
        'text:The Grange',
      ]) {
        expect(VenueKey.fromStorageKey(s), isNull, reason: '"$s"');
      }
    });
  });

  group('resolving a saved search', () {
    ResolvedSavedSearch resolve(
      CollectionPanelState s, [
      SavedSearchContext? c,
    ]) => resolveSavedSearch(specOf(s), c ?? context());

    Set<String> missing(ResolvedSavedSearch r) => {
      for (final m in (r as UnresolvableSavedSearch).missing)
        '${m.kind.name}:${m.id}',
    };

    test('builds the same filter the panel does', () {
      final s = rich();
      final r = resolve(s);
      expect(r, isA<ResolvedFilter>());
      expect(
        describeFilter((r as ResolvedFilter).filter),
        describeFilter(filterOf(s)),
      );
    });

    test('a "within 3 months" search counts back from the day it runs', () {
      final s = CollectionPanelState();
      s.facets
        ..callStatuses.add(false)
        ..setHistoryMonths(3);
      DateTime? since(DateTime day) =>
          ((resolve(s, context(day: day)) as ResolvedFilter).filter
                  as CalledFilter)
              .since;
      expect(since(DateTime.utc(2026, 11, 22)), DateTime.utc(2026, 8, 22));
      expect(since(DateTime.utc(2027, 1, 31)), DateTime.utc(2026, 10, 31));
      // Month ends clamp.
      expect(since(DateTime.utc(2026, 5, 31)), DateTime.utc(2026, 2, 28));
    });

    test('a window saved from a date moves with the date it runs on', () {
      final s = CollectionPanelState();
      s.facets
        ..callStatuses.add(false)
        ..setHistorySince(DateTime.utc(2025, 11, 22));
      final spec = specOf(s, day: DateTime.utc(2026, 11, 22));
      DateTime? since(DateTime day) =>
          ((resolveSavedSearch(spec, context(day: day)) as ResolvedFilter)
                      .filter
                  as CalledFilter)
              .since;
      expect(since(DateTime.utc(2026, 11, 22)), DateTime.utc(2025, 11, 22));
      expect(since(DateTime.utc(2027, 3, 10)), DateTime.utc(2026, 3, 10));
    });

    test('settings that are not part of a search stay live', () {
      final s = CollectionPanelState();
      s.facets.callStatuses.add(true);
      final spec = specOf(s);
      CalledFilter called(SavedSearchContext c) =>
          (resolveSavedSearch(spec, c) as ResolvedFilter).filter
              as CalledFilter;
      expect(called(context()).performedOnly, isFalse);
      expect(called(context(performedOnly: true)).performedOnly, isTrue);
      const tracking = CallingHistoryTracking(recencyRequirePerformed: true);
      expect(called(context(tracking: tracking)).tracking, tracking);
      expect(called(context(programId: 'p9')).currentProgramId, 'p9');
      expect(called(context()).currentProgramId, isNull);
    });

    test('a venue typed by name never goes missing; a record can', () {
      final typed = CollectionPanelState();
      typed.facets
        ..callStatuses.add(false)
        ..setHistoryVenue(VenueKey.typed('The Grange'));
      expect(resolve(typed, context(venues: const {})), isA<ResolvedFilter>());

      final record = CollectionPanelState();
      record.facets
        ..callStatuses.add(false)
        ..setHistoryVenue(VenueKey.record('gone'));
      expect(missing(resolve(record)), {'venue:gone'});
    });

    group('names what is gone instead of dropping it', () {
      void expectMissing(
        String why,
        void Function(CollectionPanelState s) setUp,
        Set<String> expected, {
        SavedSearchContext? c,
      }) {
        test(why, () {
          final s = CollectionPanelState();
          setUp(s);
          expect(missing(resolve(s, c)), expected);
        });
      }

      expectMissing(
        'a tag facet',
        (s) => s.facets.setTag('gone', selected: true),
        {'tag:gone'},
      );
      expectMissing(
        'a tag row in the Advanced tree',
        (s) => s.advanced.children.add(BuilderTag(tagId: 'gone')),
        {'tag:gone'},
      );
      expectMissing('an author', (s) => s.facets.authorIds.add('gone'), {
        'author:gone',
      });
      expectMissing('a source', (s) => s.facets.sourceIds.add('gone'), {
        'source:gone',
      });
      expectMissing('a level', (s) => s.facets.levels.add('gone'), {
        'level:gone',
      });
      expectMissing(
        'a custom field definition',
        (s) => s.facets.booleanValues['gone'] = true,
        {'customField:gone'},
      );
      expectMissing(
        'a custom field whose type changed (it would throw to build)',
        (s) => s.facets.choiceValues['num'] = {'easy'},
        {'customFieldType:num'},
      );
      expectMissing(
        'a choice option that was removed',
        (s) => s.facets.choiceValues['diff'] = {'easy', 'fiendish'},
        {'customFieldChoice:diff=fiendish'},
      );
      expectMissing(
        'a figure parameter outside its domain',
        (s) => s.advanced.children.add(
          BuilderFigure(move: 'allemande', params: {'hand': 'sideways'}),
        ),
        {'figureParam:allemande.hand=sideways'},
      );
      expectMissing(
        'the "unspecified" sentinel, which the panel will not show either',
        (s) => s.advanced.children.add(
          BuilderFigure(move: 'balance', params: {'hand': 'unspecified'}),
        ),
        {'figureParam:balance.hand=unspecified'},
      );
      expectMissing(
        'a figure of your own that was deleted',
        (s) => s.advanced.children.add(
          BuilderFigure(move: 'customMove', params: {userFigureRefKey: 'gone'}),
        ),
        {'userFigure:gone'},
      );
      expectMissing(
        'every missing reference at once, sorted, without repeats',
        (s) {
          s.facets
            ..authorIds.add('gone-a')
            ..setTag('gone-t', selected: true);
          s.advanced.children.add(BuilderTag(tagId: 'gone-t'));
        },
        {'tag:gone-t', 'author:gone-a'},
      );

      test(
        'inside None of, where dropping the leaf would invert the result',
        () {
          final s = CollectionPanelState();
          s.advanced.children.add(
            BuilderGroup(
              kind: GroupKind.none,
              children: [BuilderTag(tagId: 'gone')],
            ),
          );
          // Dropped, this group builds no filter and the search matches every
          // dance — the opposite of "not tagged X".
          expect(s.advanced.toFilter(), isNotNull);
          expect(resolve(s), isA<UnresolvableSavedSearch>());
          expect(missing(resolve(s)), {'tag:gone'});
        },
      );
    });

    test('things that are present resolve', () {
      final s = CollectionPanelState();
      s.facets.setTag('t1', selected: true);
      s.advanced.children
        ..add(BuilderFigure(move: 'allemande', params: {'hand': 'right'}))
        ..add(
          BuilderFigure(move: 'customMove', params: {userFigureRefKey: 'uf1'}),
        );
      expect(resolve(s), isA<ResolvedFilter>());
    });

    test('a saved search that a peer edited with a merged-away id', () {
      final s = CollectionPanelState();
      s.facets.setTag('L', selected: true);
      s.advanced.children.add(BuilderTag(tagId: 'L'));
      final aliases = {
        SyncRecordKind.tag: {'L': 'M', 'M': 'S'},
      };
      final r = resolve(s, context(aliases: aliases));
      expect(r, isA<ResolvedFilter>());
      final state = (r as ResolvedFilter).state;
      expect(state.facets.tagIds, {'S'});
      expect((state.advanced.children.single as BuilderTag).tagId, 'S');
    });

    test('an alias cycle does not loop or throw; the id reads as missing', () {
      final s = CollectionPanelState();
      s.facets.setTag('A', selected: true);
      final aliases = {
        SyncRecordKind.tag: {'A': 'B', 'B': 'A'},
      };
      expect(missing(resolve(s, context(aliases: aliases))), {'tag:A'});
    });

    test('an alias to something that is also gone is still reported', () {
      final s = CollectionPanelState();
      s.facets.setTag('L', selected: true);
      final aliases = {
        SyncRecordKind.tag: {'L': 'dead'},
      };
      expect(missing(resolve(s, context(aliases: aliases))), {'tag:dead'});
    });
  });

  group('the search day is the caller\'s own', () {
    test('calendarDayAt reads the local calendar day, not the UTC one', () {
      // Just after local midnight, far ahead of UTC: already tomorrow there.
      final instant = DateTime.utc(2026, 11, 22, 11, 5);
      expect(
        calendarDayAt(instant, const Duration(hours: 13)),
        DateTime.utc(2026, 11, 23),
      );
      expect(calendarDayAt(instant, Duration.zero), DateTime.utc(2026, 11, 22));
      // Far behind UTC the other way round.
      final late = DateTime.utc(2026, 11, 23, 5, 5);
      expect(
        calendarDayAt(late, const Duration(hours: -11)),
        DateTime.utc(2026, 11, 22),
      );
      expect(calendarDayAt(late, Duration.zero), DateTime.utc(2026, 11, 23));
    });

    test('a window run just after midnight at +13:00 counts from that day', () {
      final clock = FixedSearchClock(
        DateTime.utc(2026, 11, 22, 11, 5),
        const Duration(hours: 13),
      );
      final s = CollectionPanelState();
      s.facets
        ..callStatuses.add(false)
        ..setHistoryMonths(3);
      final called =
          (resolveSavedSearch(specOf(s), context(day: clock.today()))
                      as ResolvedFilter)
                  .filter
              as CalledFilter;
      // 23 Nov minus 3 months, not 22 Nov minus 3 months.
      expect(called.since, DateTime.utc(2026, 8, 23));
    });

    test('the real clock reads one instant and its own offset', () {
      final before = DateTime.now().toUtc();
      final reading = const SearchClock().read();
      final after = DateTime.now().toUtc();
      expect(reading.instantUtc.isBefore(before), isFalse);
      expect(reading.instantUtc.isAfter(after), isFalse);
      expect(const SearchClock().today().isUtc, isTrue);
    });
  });

  group('text is stored canonical and shown in the active dialect', () {
    final renderer = FigureRenderer(contraTaxonomy);
    final swapped = Dialect(
      name: 'Robins/Larks',
      roles: const {'role1': RoleTerm('Robin'), 'role2': RoleTerm('Lark')},
    );

    test(
      '"robins chain" saved under Robins/Larks reads the same elsewhere',
      () {
        final codec = savedSearchTextCodec(
          saveDialect: swapped,
          showDialect: swapped,
          enrichment: SearchEnrichment.empty,
          renderer: renderer,
        );
        final state = CollectionPanelState(text: 'robins chain');
        final spec = SavedSearchSpec.fromPanelState(
          state,
          today: today,
          text: codec,
        ).value!;
        expect(spec.toJson()['text'], 'role1s chain');

        // Shown in the dialect it was typed in: the same words. (The renderer
        // capitalizes the first letter; a search ignores case.)
        final back = spec.toPanelState(text: codec).text;
        expect(back.toLowerCase(), 'robins chain');
        expect(canonicalizeText(back, swapped), 'role1s chain');

        // Shown after a switch to a dialect with other role words: the same
        // roles, in that dialect's words, not "robins" meaning role2.
        final other = savedSearchTextCodec(
          saveDialect: Dialect.leadsFollows,
          showDialect: Dialect.leadsFollows,
          enrichment: SearchEnrichment.empty,
          renderer: renderer,
        );
        final shown = spec.toPanelState(text: other).text;
        expect(shown, isNot(contains('robin')));
        // ...and it searches for the same thing it did.
        expect(canonicalizeText(shown, Dialect.leadsFollows), 'role1s chain');
      },
    );
  });

  group('decodeAsStored reads a value as the settings store keeps it', () {
    SavedSearch search(String name) => SavedSearch(
      id: 'x',
      name: name,
      spec: specOf(CollectionPanelState(text: 'a')),
    );

    test('a name of only invisible characters is unreadable', () {
      final json = viaJson(search('\u200B').toJson());
      expect(SavedSearch.decode('x', json).isOk, isTrue);
      expect(SavedSearch.decodeAsStored('x', json).isOk, isFalse);
    });

    test('a value with no id is unreadable, as stored or not', () {
      final json = viaJson(search('Easy mixers').toJson());
      for (final id in ['', '  ']) {
        expect(SavedSearch.decode(id, json).isOk, isFalse, reason: '"$id"');
        expect(SavedSearch.decodeAsStored(id, json).isOk, isFalse);
      }
    });

    test('an ordinary value reads the same either way', () {
      final json = viaJson(search('Easy mixers').toJson());
      expect(SavedSearch.decodeAsStored('x', json).value!.name, 'Easy mixers');
    });

    test('colliding keys are unreadable, never thrown', () {
      final panel = CollectionPanelState();
      panel.byPhrase.match['A1'] = ['swing'];
      panel.byPhrase.match['A1\u200B'] = ['star'];
      final json = viaJson(
        SavedSearch(id: 'x', name: 'n', spec: specOf(panel)).toJson(),
      );
      expect(() => SavedSearch.decodeAsStored('x', json), returnsNormally);
      expect(SavedSearch.decodeAsStored('x', json).isOk, isFalse);
    });

    test('anything else is unreadable and never thrown', () {
      for (final v in <Object?>[null, 3, 'x', <Object?>[]]) {
        expect(SavedSearch.decodeAsStored('x', v).isOk, isFalse);
      }
    });
  });

  group('what the compiler sees: the resolved search is the panel\'s search', () {
    final dialect = Dialect.larksRobins;
    final renderer = FigureRenderer(contraTaxonomy);
    final codec = savedSearchTextCodec(
      saveDialect: dialect,
      showDialect: dialect,
      enrichment: SearchEnrichment.empty,
      renderer: renderer,
    );
    final compiler = FilterCompiler(
      dialect,
      SearchEnrichment.empty,
      contraTaxonomy,
    );

    List<Object?> binds(DanceFilter f) => compiler.compile(f).binds;

    DanceFilter resolved(CollectionPanelState panel) {
      final spec = SavedSearchSpec.fromPanelState(
        panel,
        today: today,
        text: codec,
      ).value!;
      final r = resolveSavedSearch(
        spec,
        SavedSearchContext(today: today, taxonomy: contraTaxonomy, text: codec),
      );
      return (r as ResolvedFilter).filter;
    }

    for (final scope in [FullTextScope.title, FullTextScope.author]) {
      test('${scope.name} text is stored as typed and compiles as typed', () {
        final panel = CollectionPanelState(text: 'ladies chain', scope: scope);
        final spec = SavedSearchSpec.fromPanelState(
          panel,
          today: today,
          text: codec,
        ).value!;
        // A title that says "Ladies Chain" must still match.
        expect(spec.toJson()['text'], 'ladies chain');
        expect(binds(resolved(panel)), binds(filterOf(panel)));
      });
    }

    test('Figures text is stored canonical and compiles the same', () {
      final panel = CollectionPanelState(
        text: 'ladies chain',
        scope: FullTextScope.figure,
      );
      final spec = SavedSearchSpec.fromPanelState(
        panel,
        today: today,
        text: codec,
      ).value!;
      expect(spec.toJson()['text'], 'role2s chain');
      expect(binds(resolved(panel)), binds(filterOf(panel)));
    });

    test(
      'All fields: the resolved search is what the reloaded panel searches',
      () {
        final panel = CollectionPanelState(text: 'ladies chain');
        final spec = SavedSearchSpec.fromPanelState(
          panel,
          today: today,
          text: codec,
        ).value!;
        final reloaded = spec.toPanelState(text: codec);
        // Not the text first typed ("ladies"), but the word the dialect shows for
        // the role, which is what the panel holds after loading.
        expect(reloaded.text.toLowerCase(), 'robins chain');
        expect(binds(resolved(panel)), binds(filterOf(reloaded)));
      },
    );

    test('All fields text is stored canonical', () {
      final panel = CollectionPanelState(text: 'ladies chain');
      final spec = SavedSearchSpec.fromPanelState(
        panel,
        today: today,
        text: codec,
      ).value!;
      expect(spec.toJson()['text'], 'role2s chain');
    });
  });

  group('more of the format', () {
    test('false flags are stored (the filter acts on false too)', () {
      final s = CollectionPanelState();
      s.facets.mixedLevel = false;
      s.facets.mixer = false;
      final back = SavedSearchSpec.decode(
        viaJson(specOf(s).toJson()),
      ).value!.toPanelState();
      expect(back.facets.mixedLevel, isFalse);
      expect(back.facets.mixer, isFalse);
      expect(describeFilter(filterOf(back)), describeFilter(filterOf(s)));
    });

    test('every custom field operator round-trips', () {
      final s = CollectionPanelState();
      s.facets.textValues['note'] = const TextFacetState(
        op: CustomFieldOp.equals,
        value: 'x',
      );
      for (final op in [CustomFieldOp.eq, CustomFieldOp.lt, CustomFieldOp.gt]) {
        s.facets.numberValues['num'] = NumberFacetState(op: op, lo: 2.5);
        final back = SavedSearchSpec.decode(
          viaJson(specOf(s).toJson()),
        ).value!.toPanelState();
        expect(back.facets.numberValues['num']!.op, op);
        expect(back.facets.numberValues['num']!.lo, 2.5);
        expect(back.facets.textValues['note']!.op, CustomFieldOp.equals);
      }
    });

    test('bytes do not depend on the order maps were filled', () {
      CollectionPanelState build(List<String> keys) {
        final s = CollectionPanelState();
        for (final k in keys) {
          s.facets.booleanValues[k] = true;
          s.facets.choiceValues[k] = {'b', 'a'};
          s.facets.textValues[k] = const TextFacetState(
            op: CustomFieldOp.contains,
            value: 'v',
          );
          s.facets.numberValues[k] = const NumberFacetState(
            op: CustomFieldOp.eq,
            lo: 1,
          );
          s.byPhrase.match[k] = ['swing'];
          s.byPhrase.exclude[k] = ['star'];
        }
        // A figure row's params are filled in the order the user picks them.
        final params = <String, Object?>{};
        for (final k in keys) {
          params[k] = 'v$k';
        }
        s.advanced.children.add(BuilderFigure(move: 'swing', params: params));
        return s;
      }

      expect(
        jsonEncode(specOf(build(['x', 'y', 'z'])).toJson()),
        jsonEncode(specOf(build(['z', 'x', 'y'])).toJson()),
      );
    });

    test('exactly 200 rows are readable, 201 are not', () {
      Map<String, Object?> rows(int n) => {
        'v': 1,
        'advanced': {
          't': 'group',
          'kind': 'all',
          // The root is one row.
          'children': [
            for (var i = 0; i < n - 1; i++) {'t': 'tag', 'tagId': 'a$i'},
          ],
        },
      };
      expect(SavedSearchSpec.decode(rows(200)).isOk, isTrue);
      expect(SavedSearchSpec.decode(rows(201)).isOk, isFalse);
    });

    test('the size limit counts bytes, not characters', () {
      // 28,000 characters but 84,000 bytes of UTF-8.
      final json = {
        'v': 1,
        'facets': {'tunes': List.filled(200, '€' * 140)},
      };
      expect(SavedSearchSpec.decode(json).isOk, isFalse);
    });

    test('"advanced": null is unreadable, like every other null', () {
      expect(SavedSearchSpec.decode({'v': 1, 'advanced': null}).isOk, isFalse);
    });

    test('two field ids read as one keep both fields\' choices', () {
      final spec = SavedSearchSpec.decode({
        'v': 1,
        'facets': {
          'choiceValues': {
            'L': ['easy'],
            'S': ['hard'],
          },
        },
      }).value!;
      final state = spec.toPanelState(
        map: (kind, id) =>
            kind == SyncRecordKind.customFieldDef && id == 'L' ? 'S' : id,
      );
      expect(state.facets.choiceValues, {
        'S': {'easy', 'hard'},
      });
    });

    test('random damage inside a valid search never throws', () {
      final random = Random(2326);
      Object? damage() => [
        null,
        -1,
        3.5,
        true,
        '',
        'x' * 600,
        <Object?>[],
        <String, Object?>{},
        'nope',
      ][random.nextInt(9)];

      // Replaces one random value, anywhere in the tree, with damage.
      Object? hit(Object? node, int budget) {
        if (node is Map &&
            node.isNotEmpty &&
            budget > 0 &&
            random.nextInt(3) > 0) {
          final keys = node.keys.toList();
          final k = keys[random.nextInt(keys.length)];
          return {...node, k: hit(node[k], budget - 1)};
        }
        if (node is List &&
            node.isNotEmpty &&
            budget > 0 &&
            random.nextInt(3) > 0) {
          final copy = List<Object?>.of(node);
          final i = random.nextInt(copy.length);
          copy[i] = hit(copy[i], budget - 1);
          return copy;
        }
        return damage();
      }

      final base = viaJson(specOf(rich()).toJson());
      var reachedInnerReader = 0;
      for (var i = 0; i < 4000; i++) {
        final value = hit(base, 6);
        late SavedSearchDecoded<SavedSearchSpec> r;
        expect(() => r = SavedSearchSpec.decode(value), returnsNormally);
        // The damage landed inside the object, past the key and version checks.
        if (!r.isOk && !r.problem!.startsWith('saved search')) {
          reachedInnerReader++;
        }
        if (r.isOk) {
          // Whatever still reads must also resolve without throwing.
          expect(
            () => resolveSavedSearch(r.value!, context()),
            returnsNormally,
          );
        }
      }
      expect(reachedInnerReader, greaterThan(1000));
    });
  });

  group('more references', () {
    SavedSearchContext ctx({
      Set<String> userFigures = const {'uf1'},
      List<CustomFieldDef>? fields,
      Map<SyncRecordKind, Map<String, String>> aliases = const {},
    }) => SavedSearchContext(
      today: today,
      taxonomy: contraTaxonomy,
      tagIds: const {'t1'},
      authorIds: const {'a1'},
      sourceIds: const {'s1'},
      levelIds: const {'l1'},
      venueIds: const {'v1'},
      userFigureIds: userFigures,
      customFieldDefs: fields ?? defs,
      aliases: aliases,
    );

    Set<String> names(ResolvedSavedSearch r) => {
      for (final m in (r as UnresolvableSavedSearch).missing)
        '${m.kind.name}:${m.id}',
    };

    test('a figure of your own inside a "then" operand group', () {
      final s = CollectionPanelState();
      s.advanced.children.add(
        BuilderThen(
          before: BuilderFigure(move: 'swing'),
          after: BuilderFigureGroup(
            kind: GroupKind.none,
            children: [
              BuilderFigure(
                move: 'customMove',
                params: {userFigureRefKey: 'gone'},
              ),
            ],
          ),
        ),
      );
      expect(names(resolveSavedSearch(specOf(s), ctx())), {'userFigure:gone'});
      expect(
        resolveSavedSearch(specOf(s), ctx(userFigures: const {'gone'})),
        isA<ResolvedFilter>(),
      );
    });

    test('a param the move does not declare, or that has no closed domain', () {
      final s = CollectionPanelState();
      s.advanced.children
        ..add(BuilderFigure(move: 'allemande', params: {'nonsense': 'x'}))
        ..add(BuilderFigure(move: 'swing', params: {'beats': '8'}));
      expect(names(resolveSavedSearch(specOf(s), ctx())), {
        'figureParam:allemande.nonsense=x',
        'figureParam:swing.beats=8',
      });
    });

    test(
      'a move written with stray spaces is judged as the filter reads it',
      () {
        final s = CollectionPanelState();
        s.advanced.children.add(
          BuilderFigure(move: ' allemande ', params: {'hand': 'sideways'}),
        );
        expect(names(resolveSavedSearch(specOf(s), ctx())), {
          'figureParam:allemande.hand=sideways',
        });
      },
    );

    test('a text and a number field that are gone', () {
      final s = CollectionPanelState();
      s.facets
        ..textValues['gone-t'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: 'x',
        )
        ..numberValues['gone-n'] = const NumberFacetState(
          op: CustomFieldOp.eq,
          lo: 1,
        );
      expect(names(resolveSavedSearch(specOf(s), ctx())), {
        'customField:gone-t',
        'customField:gone-n',
      });
    });

    test('every kind of reference is read through its own aliases', () {
      final s = CollectionPanelState();
      s.facets
        ..authorIds.add('A-old')
        ..sourceIds.add('S-old')
        ..levels.add('L-old')
        ..callStatuses.add(false)
        ..setHistoryVenue(VenueKey.record('V-old'))
        ..booleanValues['F-old'] = true;
      final r = resolveSavedSearch(
        specOf(s),
        ctx(
          aliases: {
            SyncRecordKind.choreographer: {'A-old': 'a1'},
            SyncRecordKind.publishedSource: {'S-old': 's1'},
            SyncRecordKind.difficultyLevel: {'L-old': 'l1'},
            SyncRecordKind.venue: {'V-old': 'v1'},
            SyncRecordKind.customFieldDef: {'F-old': 'teach'},
          },
        ),
      );
      expect(r, isA<ResolvedFilter>());
      final f = (r as ResolvedFilter).state.facets;
      expect(f.authorIds, {'a1'});
      expect(f.sourceIds, {'s1'});
      expect(f.levels, {'l1'});
      expect(f.historyVenue, VenueKey.record('v1'));
      expect(f.booleanValues.keys, ['teach']);
    });

    test('an alias of one kind is not applied to another', () {
      final s = CollectionPanelState();
      s.facets.authorIds.add('X');
      final r = resolveSavedSearch(
        specOf(s),
        ctx(
          aliases: {
            SyncRecordKind.tag: {'X': 'a1'},
          },
        ),
      );
      expect(names(r), {'author:X'});
    });
  });
  group(
    'movingReferences (a merge of tags, authors, sources, levels or custom fields)',
    () {
      List<Object?> tagRows(SavedSearchSpec spec) {
        final rows = <Object?>[];
        void walk(Object? n) {
          if (n is Map) {
            if (n['t'] == 'tag') rows.add(n['tagId']);
            n.values.forEach(walk);
          } else if (n is List) {
            n.forEach(walk);
          }
        }

        walk(spec.toJson()['advanced']);
        return rows;
      }

      test('moves a tag row in a nested group, and leaves figure and then rows '
          'alone', () {
        final s = CollectionPanelState();
        s.advanced.children.addAll([
          BuilderTag(tagId: 'L'),
          BuilderGroup(
            kind: GroupKind.none,
            children: [
              BuilderTag(tagId: 'L'),
              BuilderTag(tagId: 'K'),
            ],
          ),
          BuilderThen(),
        ]);
        final spec = specOf(s);
        final moved = spec.movingReferences(SyncRecordKind.tag, {'L': 'S'})!;
        expect(tagRows(moved), ['S', 'S', 'K']);
        expect(
          (moved.toJson()['advanced'] as Map)['children'].toString(),
          contains('then'),
        );
      });

      test('is null for a search naming none of the moved ids, a kind that has '
          'no such reference, and an empty move', () {
        final s = CollectionPanelState();
        s.facets.tagIds.add('K');
        s.advanced.children.add(BuilderTag(tagId: 'K'));
        final spec = specOf(s);
        expect(spec.movingReferences(SyncRecordKind.tag, {'L': 'S'}), isNull);
        expect(spec.movingReferences(SyncRecordKind.tag, {}), isNull);
        expect(
          spec.movingReferences(SyncRecordKind.difficultyLevel, {'K': 'S'}),
          isNull,
          reason: 'a level id is not a tag id',
        );
        expect(
          spec.movingReferences(SyncRecordKind.choreographer, {'K': 'S'}),
          isNull,
          reason: 'an author id is not a tag id',
        );
      });

      test('moves the Level filter and every custom-field filter, which only '
          "sync's reconciliation merges", () {
        final s = CollectionPanelState();
        s.facets.levels.addAll(['L', 'K']);
        s.facets.choiceValues['F'] = {'jig'};
        s.facets.booleanValues['F'] = true;
        s.facets.textValues['F'] = const TextFacetState(
          op: CustomFieldOp.contains,
          value: 'reel',
        );
        s.facets.numberValues['F'] = const NumberFacetState(
          op: CustomFieldOp.gt,
          lo: 3,
        );
        final spec = specOf(s);
        final levels = spec.movingReferences(SyncRecordKind.difficultyLevel, {
          'L': 'A',
        })!;
        expect((levels.toJson()['facets'] as Map)['levels'], ['A', 'K']);
        expect(
          spec.movingReferences(SyncRecordKind.customFieldDef, {'L': 'A'}),
          isNull,
          reason: 'no field named L',
        );
        final fields = spec.movingReferences(SyncRecordKind.customFieldDef, {
          'F': 'E',
        })!;
        final facets = fields.toJson()['facets'] as Map;
        expect(facets['choiceValues'], {
          'E': ['jig'],
        });
        expect(facets['booleanValues'], {'E': true});
        expect(facets['textValues'], {
          'E': {'op': 'contains', 'value': 'reel'},
        });
        expect(facets['numberValues'], {
          'E': {'op': 'gt', 'lo': 3},
        });
        expect(SavedSearchSpec.decode(fields.toJson()).isOk, isTrue);
      });

      test(
        'a custom field filter on both the loser and the survivor keeps what '
        'reading the loser through the alias gives: both choices, and the '
        'later field in stored order for a single value',
        () {
          final s = CollectionPanelState();
          // Stored in key order: A (the survivor) before Z (the loser).
          s.facets.choiceValues['A'] = {'jig'};
          s.facets.choiceValues['Z'] = {'reel'};
          s.facets.booleanValues['A'] = true;
          s.facets.booleanValues['Z'] = false;
          final spec = specOf(s);
          final aliased = spec.toPanelState(
            map: (kind, id) =>
                kind == SyncRecordKind.customFieldDef && id == 'Z' ? 'A' : id,
          );
          final moved = spec.movingReferences(SyncRecordKind.customFieldDef, {
            'Z': 'A',
          })!;
          final facets = moved.toJson()['facets'] as Map;
          expect(facets['choiceValues'], {
            'A': ['jig', 'reel'],
          });
          expect(facets['booleanValues'], {'A': false});
          final rewritten = moved.toPanelState();
          expect(rewritten.facets.choiceValues, aliased.facets.choiceValues);
          expect(rewritten.facets.booleanValues, aliased.facets.booleanValues);
        },
      );

      test('the result is readable and its bytes do not depend on the order '
          'the ids were chosen in', () {
        final s1 = CollectionPanelState();
        s1.facets.tagIds.addAll(['C', 'L', 'A']);
        final s2 = CollectionPanelState();
        s2.facets.tagIds.addAll(['A', 'L', 'C']);
        final m1 = specOf(s1).movingReferences(SyncRecordKind.tag, {'L': 'B'})!;
        final m2 = specOf(s2).movingReferences(SyncRecordKind.tag, {'L': 'B'})!;
        expect(jsonEncode(m1.toJson()), jsonEncode(m2.toJson()));
        expect((m1.toJson()['facets'] as Map)['tagIds'], ['A', 'B', 'C']);
        expect(SavedSearchSpec.decode(m1.toJson()).isOk, isTrue);
      });
    },
  );
}
