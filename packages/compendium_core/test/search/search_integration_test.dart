import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Builds a dance whose figures land in known phrase sections under the
/// standard 4x16 structure (A1@0, A2@16, B1@32, B2@48).
Dance _dance({
  required String id,
  required String title,
  List<String> authorIds = const [],
  List<String> tagIds = const [],
  List<CustomFieldValue> customFields = const [],
  List<Figure>? figures,
  DanceForm form = DanceForm.contra,
  FormationShape formation = FormationShape.dupleImproper,
  Progression progression = Progression.single,
  DanceStatus status = DanceStatus.active,
  DanceLevel? level,
  bool mixedLevel = false,
  PartialDate? composedOn,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Dance(
    id: id,
    title: title,
    authorIds: authorIds,
    tagIds: tagIds,
    customFields: customFields,
    form: form,
    formation: Formation(formation),
    progression: progression,
    status: status,
    level: level,
    mixedLevel: mixedLevel,
    composedOn: composedOn,
    figures:
        figures ??
        [
          Figure(move: 'petronella', params: const {'beats': 16}), // A1
          Figure(move: 'swing', params: const {'who': 'partners', 'beats': 16}),
          Figure(move: 'balance', params: const {'beats': 16}), // B1
          Figure(move: 'long_lines', params: const {'beats': 16}), // B2
        ],
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    deletedAt: deletedAt,
  );
}

void main() {
  late CompendiumDatabase db;
  late DanceRepository dances;
  late ChoreographerRepository choreographers;
  late TagRepository tags;
  late CustomFieldDefRepository customFieldDefs;
  late ProgramRepository programs;

  setUp(() {
    db = openTestDatabase();
    dances = DanceRepository(db, contraTaxonomy);
    choreographers = ChoreographerRepository(db);
    tags = TagRepository(db);
    customFieldDefs = CustomFieldDefRepository(db);
    programs = ProgramRepository(db);
  });

  tearDown(() => db.close());

  group('metadata leaves', () {
    test('Form', () async {
      await dances.create(
        _dance(id: 'c', title: 'Contra', form: DanceForm.contra),
      );
      await dances.create(_dance(id: 'e', title: 'ECD', form: DanceForm.ecd));
      expect(await dances.search(const FormFilter(DanceForm.ecd)), ['e']);
    });

    test('Formation, Progression, Status', () async {
      await dances.create(
        _dance(
          id: 'a',
          title: 'A',
          formation: FormationShape.becketCw,
          progression: Progression.double,
          status: DanceStatus.broken,
        ),
      );
      await dances.create(_dance(id: 'b', title: 'B'));
      expect(
        await dances.search(const FormationFilter(FormationShape.becketCw)),
        ['a'],
      );
      expect(await dances.search(const ProgressionFilter(Progression.double)), [
        'a',
      ]);
      expect(await dances.search(const StatusFilter(DanceStatus.broken)), [
        'a',
      ]);
    });

    test('Author', () async {
      await choreographers.upsert(Choreographer(id: 'c1', name: 'Alice'));
      await dances.create(_dance(id: 'a', title: 'A', authorIds: ['c1']));
      await dances.create(_dance(id: 'b', title: 'B'));
      expect(await dances.search(const AuthorFilter('c1')), ['a']);
    });

    test('Tag', () async {
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      await dances.create(_dance(id: 'a', title: 'A', tagIds: ['t1']));
      await dances.create(_dance(id: 'b', title: 'B'));
      expect(await dances.search(const TagFilter('t1')), ['a']);
    });

    test('Level: eq matches exactly, ordered ops respect the scale', () async {
      await dances.create(
        _dance(id: 'beg', title: 'Beg', level: DanceLevel.beginner),
      );
      await dances.create(
        _dance(id: 'int', title: 'Int', level: DanceLevel.intermediate),
      );
      await dances.create(
        _dance(id: 'adv', title: 'Adv', level: DanceLevel.advanced),
      );
      // Unspecified level: never matches any Level leaf.
      await dances.create(_dance(id: 'non', title: 'None'));

      expect(await dances.search(const LevelFilter(DanceLevel.intermediate)), [
        'int',
      ]);
      expect(
        await dances.search(
          const LevelFilter(DanceLevel.intermediate, LevelOp.lte),
        ),
        ['beg', 'int'],
      );
      expect(
        await dances.search(
          const LevelFilter(DanceLevel.intermediate, LevelOp.gte),
        ),
        ['adv', 'int'],
      );
    });

    test('MixedLevel matches only the flagged rows', () async {
      await dances.create(_dance(id: 'm', title: 'Mixed', mixedLevel: true));
      await dances.create(_dance(id: 'p', title: 'Plain'));
      expect(await dances.search(const MixedLevelFilter(true)), ['m']);
      expect(await dances.search(const MixedLevelFilter(false)), ['p']);
    });

    test('FullText', () async {
      await dances.create(_dance(id: 'a', title: 'Petronella Special'));
      await dances.create(
        _dance(
          id: 'b',
          title: 'Unrelated',
          figures: [
            Figure(move: 'do_si_do', params: const {'beats': 8}),
          ],
        ),
      );
      expect(await dances.search(const FullTextFilter('Petronella')), ['a']);
    });
  });

  group('combinators', () {
    test('empty And matches everything (non-deleted)', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      await dances.create(_dance(id: 'b', title: 'B'));
      expect(await dances.search(const AndFilter([])), ['a', 'b']);
    });

    test('empty Or matches nothing', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      expect(await dances.search(const OrFilter([])), isEmpty);
    });

    test('And of two facets', () async {
      await tags.upsert(Tag(id: 't1', name: 'chestnut'));
      await dances.create(
        _dance(id: 'a', title: 'A', form: DanceForm.contra, tagIds: ['t1']),
      );
      await dances.create(_dance(id: 'b', title: 'B', form: DanceForm.contra));
      expect(
        await dances.search(
          const AndFilter([FormFilter(DanceForm.contra), TagFilter('t1')]),
        ),
        ['a'],
      );
    });

    test('Or of two forms', () async {
      await dances.create(_dance(id: 'a', title: 'A', form: DanceForm.ecd));
      await dances.create(_dance(id: 'b', title: 'B', form: DanceForm.square));
      await dances.create(_dance(id: 'c', title: 'C', form: DanceForm.contra));
      expect(
        await dances.search(
          const OrFilter([
            FormFilter(DanceForm.ecd),
            FormFilter(DanceForm.square),
          ]),
        ),
        ['a', 'b'],
      );
    });

    test('Not negates a metadata leaf', () async {
      await dances.create(_dance(id: 'a', title: 'A', form: DanceForm.ecd));
      await dances.create(_dance(id: 'b', title: 'B', form: DanceForm.contra));
      expect(await dances.search(const NotFilter(FormFilter(DanceForm.ecd))), [
        'b',
      ]);
    });
  });

  group('structural: figures & sections', () {
    test('Figure leaf by move', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      await dances.create(
        _dance(
          id: 'b',
          title: 'B',
          figures: [
            Figure(move: 'do_si_do', params: const {'beats': 8}),
          ],
        ),
      );
      expect(await dances.search(FigureFilter.leaf('petronella')), ['a']);
    });

    test('Figure leaf by move + section', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      // balance starts at beat 32 -> B1 in dance 'a'.
      expect(await dances.search(FigureFilter.leaf('balance', section: 'B1')), [
        'a',
      ]);
      // No balance in A1.
      expect(
        await dances.search(FigureFilter.leaf('balance', section: 'A1')),
        isEmpty,
      );
    });

    test('Figure leaf by move + param (json natural typing)', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      expect(
        await dances.search(
          FigureFilter.leaf('swing', params: const {'who': 'partners'}),
        ),
        ['a'],
      );
      expect(
        await dances.search(
          FigureFilter.leaf('swing', params: const {'who': 'neighbors'}),
        ),
        isEmpty,
      );
      expect(
        await dances.search(
          FigureFilter.leaf('swing', params: const {'beats': 16}),
        ),
        ['a'],
      );
    });

    test('FigureAnd constrains a single row', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      // swing is in A2, not B1: an AND on the same row must fail.
      expect(
        await dances.search(
          FigureFilter(FigureAnd([FigureLeaf('swing', section: 'B1')])),
        ),
        isEmpty,
      );
      expect(
        await dances.search(
          FigureFilter(FigureAnd([FigureLeaf('swing', section: 'A2')])),
        ),
        ['a'],
      );
    });

    test('FigureOr matches any', () async {
      await dances.create(
        _dance(
          id: 'a',
          title: 'A',
          figures: [
            Figure(move: 'do_si_do', params: const {'beats': 8}),
          ],
        ),
      );
      expect(
        await dances.search(
          FigureFilter(FigureOr([FigureLeaf('swing'), FigureLeaf('do_si_do')])),
        ),
        ['a'],
      );
    });

    test('top-level FigureNot = dance has no such figure', () async {
      await dances.create(_dance(id: 'a', title: 'A')); // has swing
      await dances.create(
        _dance(
          id: 'b',
          title: 'B',
          figures: [
            Figure(move: 'do_si_do', params: const {'beats': 8}),
          ],
        ),
      );
      expect(
        await dances.search(FigureFilter(FigureNot(FigureLeaf('swing')))),
        ['b'],
      );
    });

    test(
      'nested FigureNot matches a row with an absent param (NULL-safe)',
      () async {
        // A swing with no `who` param: json_extract(who) is NULL.
        await dances.create(
          _dance(
            id: 'a',
            title: 'A',
            figures: [
              Figure(move: 'swing', params: const {'beats': 8}),
            ],
          ),
        );
        // "a swing that is NOT a who=partners swing" — the absent param must
        // negate to TRUE, not NULL, so the dance matches.
        expect(
          await dances.search(
            FigureFilter(
              FigureAnd([
                FigureLeaf('swing'),
                FigureNot(
                  FigureLeaf('swing', params: const {'who': 'partners'}),
                ),
              ]),
            ),
          ),
          ['a'],
        );
      },
    );
  });

  group('sequence: Then', () {
    test('positive: before occurs earlier than after', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      // petronella (idx0) then swing (idx1)
      expect(
        await dances.search(
          ThenFilter(FigureLeaf('petronella'), FigureLeaf('swing')),
        ),
        ['a'],
      );
    });

    test('negative: reversed order does not match', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      // swing occurs after petronella, so swing-then-petronella is false.
      expect(
        await dances.search(
          ThenFilter(FigureLeaf('swing'), FigureLeaf('petronella')),
        ),
        isEmpty,
      );
    });

    test('Then with section constraint on the before clause', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      // petronella in A1, then balance later.
      expect(
        await dances.search(
          ThenFilter(
            FigureLeaf('petronella', section: 'A1'),
            FigureLeaf('balance'),
          ),
        ),
        ['a'],
      );
    });
  });

  group('custom fields', () {
    Future<void> seed(
      CustomFieldDef def,
      Object value, {
      String id = 'a',
    }) async {
      await customFieldDefs.upsert(def);
      await dances.create(
        _dance(
          id: id,
          title: id.toUpperCase(),
          customFields: [CustomFieldValue(fieldId: def.id, value: value)],
        ),
      );
    }

    test('text contains and equals', () async {
      final def = CustomFieldDef(
        id: 'f',
        key: 'origin',
        label: 'Origin',
        type: CustomFieldType.text,
      );
      await seed(def, 'New England reel');
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.contains, 'England'),
        ),
        ['a'],
      );
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.equals, 'New England reel'),
        ),
        ['a'],
      );
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.equals, 'nope'),
        ),
        isEmpty,
      );
    });

    test('number eq/lt/gt/between', () async {
      final def = CustomFieldDef(
        id: 'f',
        key: 'diff',
        label: 'Difficulty',
        type: CustomFieldType.number,
      );
      await seed(def, 3);
      expect(await dances.search(CustomFieldFilter(def, CustomFieldOp.eq, 3)), [
        'a',
      ]);
      expect(await dances.search(CustomFieldFilter(def, CustomFieldOp.lt, 5)), [
        'a',
      ]);
      expect(
        await dances.search(CustomFieldFilter(def, CustomFieldOp.gt, 5)),
        isEmpty,
      );
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.between, [1, 4]),
        ),
        ['a'],
      );
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.between, [4, 9]),
        ),
        isEmpty,
      );
    });

    test('boolean is', () async {
      final def = CustomFieldDef(
        id: 'f',
        key: 'fav',
        label: 'Favourite',
        type: CustomFieldType.boolean,
      );
      await seed(def, true);
      expect(
        await dances.search(CustomFieldFilter(def, CustomFieldOp.is_, true)),
        ['a'],
      );
      expect(
        await dances.search(CustomFieldFilter(def, CustomFieldOp.is_, false)),
        isEmpty,
      );
    });

    test('choice is and in', () async {
      final def = CustomFieldDef(
        id: 'f',
        key: 'mood',
        label: 'Mood',
        type: CustomFieldType.choice,
        choices: ['smooth', 'fiery', 'silly'],
      );
      await seed(def, 'fiery');
      expect(
        await dances.search(CustomFieldFilter(def, CustomFieldOp.is_, 'fiery')),
        ['a'],
      );
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.in_, ['smooth', 'fiery']),
        ),
        ['a'],
      );
      expect(
        await dances.search(
          CustomFieldFilter(def, CustomFieldOp.in_, ['smooth', 'silly']),
        ),
        isEmpty,
      );
    });
  });

  group('dialect-canonicalized input', () {
    test(
      'a robins full-text term matches the canonical stored token',
      () async {
        await dances.create(
          _dance(
            id: 'a',
            title: 'Roles Dance',
            figures: [
              Figure(
                move: 'swing',
                params: const {'who': 'role2s', 'beats': 8},
              ),
            ],
          ),
        );
        // Canonical FTS stores 'role2s'; a Larks/Robins user typing 'robins'
        // must match.
        expect(
          await dances.search(
            const FullTextFilter('robins'),
            dialect: Dialect.larksRobins,
          ),
          ['a'],
        );
      },
    );

    test('a gents move-param term matches canonical role in params', () async {
      await dances.create(
        _dance(
          id: 'a',
          title: 'A',
          figures: [
            Figure(move: 'swing', params: const {'who': 'role1s', 'beats': 8}),
          ],
        ),
      );
      expect(
        await dances.search(
          FigureFilter.leaf('swing', params: const {'who': 'gents'}),
          dialect: Dialect.gentsLadies,
        ),
        ['a'],
      );
    });
  });

  group('sort options', () {
    test('title (default) case-insensitive', () async {
      await dances.create(_dance(id: 'b', title: 'banana'));
      await dances.create(_dance(id: 'a', title: 'Apple'));
      await dances.create(_dance(id: 'c', title: 'cherry'));
      expect(await dances.search(const AndFilter([])), ['a', 'b', 'c']);
    });

    test('recentlyAdded by created_at DESC', () async {
      await dances.create(
        _dance(id: 'old', title: 'Old', createdAt: DateTime.utc(2020)),
      );
      await dances.create(
        _dance(id: 'new', title: 'New', createdAt: DateTime.utc(2026)),
      );
      expect(
        await dances.search(
          const AndFilter([]),
          sort: SearchSort.recentlyAdded,
        ),
        ['new', 'old'],
      );
    });

    test('recentlyEdited by updated_at DESC', () async {
      await dances.create(
        _dance(id: 'old', title: 'Old', updatedAt: DateTime.utc(2020)),
      );
      await dances.create(
        _dance(id: 'new', title: 'New', updatedAt: DateTime.utc(2026)),
      );
      expect(
        await dances.search(
          const AndFilter([]),
          sort: SearchSort.recentlyEdited,
        ),
        ['new', 'old'],
      );
    });

    test('composedOn chronological, year-only before same-year month, '
        'NULLs last', () async {
      await dances.create(
        _dance(id: 'y1990', title: 'later', composedOn: PartialDate(1990)),
      );
      await dances.create(
        _dance(id: 'y1989', title: 'yearOnly', composedOn: PartialDate(1989)),
      );
      await dances.create(
        _dance(
          id: 'y1989m03',
          title: 'sameYearMonth',
          composedOn: PartialDate(1989, 3),
        ),
      );
      await dances.create(_dance(id: 'none', title: 'noDate'));
      expect(
        await dances.search(const AndFilter([]), sort: SearchSort.composedOn),
        ['y1989', 'y1989m03', 'y1990', 'none'],
      );
    });

    test('author by first author name', () async {
      await choreographers.upsert(Choreographer(id: 'z', name: 'Zoe'));
      await choreographers.upsert(Choreographer(id: 'am', name: 'Amy'));
      await dances.create(_dance(id: 'z', title: 'Z dance', authorIds: ['z']));
      await dances.create(_dance(id: 'a', title: 'A dance', authorIds: ['am']));
      expect(
        await dances.search(const AndFilter([]), sort: SearchSort.author),
        ['a', 'z'],
      );
    });

    test('author sort breaks ties by title (stable)', () async {
      await choreographers.upsert(Choreographer(id: 'amy', name: 'Amy'));
      await dances.create(_dance(id: 'b', title: 'Banana', authorIds: ['amy']));
      await dances.create(_dance(id: 'a', title: 'Apple', authorIds: ['amy']));
      await dances.create(_dance(id: 'c', title: 'Cherry', authorIds: ['amy']));
      // Same author for all three: fall back to title order.
      expect(
        await dances.search(const AndFilter([]), sort: SearchSort.author),
        ['a', 'b', 'c'],
      );
    });

    test('lastCalled, never-called sort last', () async {
      await dances.create(_dance(id: 'called', title: 'Called'));
      await dances.create(_dance(id: 'never', title: 'Never'));
      await programs.create(
        Program(
          id: 'p1',
          title: 'Event',
          slots: [
            ProgramSlot(
              id: 's1',
              position: 0,
              danceId: 'called',
              performedAt: DateTime.utc(2026, 5),
            ),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(
        await dances.search(const AndFilter([]), sort: SearchSort.lastCalled),
        ['called', 'never'],
      );
    });

    test('relevance orders a bare full-text search by bm25', () async {
      await dances.create(_dance(id: 'strong', title: 'swing swing swing'));
      await dances.create(_dance(id: 'weak', title: 'swing once'));
      final result = await dances.search(
        const FullTextFilter('swing'),
        sort: SearchSort.relevance,
      );
      expect(result, containsAll(['strong', 'weak']));
      expect(result.first, 'strong');
    });
  });

  group('soft-delete exclusion', () {
    test('deleted dances never appear', () async {
      await dances.create(_dance(id: 'a', title: 'A'));
      await dances.create(_dance(id: 'b', title: 'B'));
      await dances.softDelete('b', at: DateTime.utc(2026, 2));
      expect(await dances.search(const AndFilter([])), ['a']);
      expect(await dances.search(FigureFilter.leaf('petronella')), ['a']);
    });
  });

  group('searchDances convenience', () {
    test('returns hydrated dances in id order', () async {
      await dances.create(_dance(id: 'a', title: 'Apple'));
      await dances.create(_dance(id: 'b', title: 'Banana'));
      final result = await dances.searchDances(const AndFilter([]));
      expect(result.map((d) => d.id), ['a', 'b']);
      expect(result.first, isA<Dance>());
    });
  });
}
