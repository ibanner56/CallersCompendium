import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final compiler = FilterCompiler();

  String pred(DanceFilter f) {
    // Extract just the predicate between `AND (` … `) ORDER BY`.
    final sql = compiler.compile(f).sql;
    final start = sql.indexOf('AND (') + 'AND ('.length;
    final end = sql.lastIndexOf(') ORDER BY');
    return sql.substring(start, end);
  }

  group('outer shape', () {
    test('wraps predicate with deleted_at guard and default title sort', () {
      final c = compiler.compile(const FormFilter(DanceForm.contra));
      expect(
        c.sql,
        'SELECT id FROM dances WHERE deleted_at IS NULL AND (form = ?) '
        'ORDER BY title COLLATE NOCASE',
      );
      expect(c.binds, ['contra']);
    });

    test('recentlyEdited sorts by updated_at DESC', () {
      final c = compiler.compile(
        const FormFilter(DanceForm.contra),
        sort: SearchSort.recentlyEdited,
      );
      expect(c.sql, endsWith('ORDER BY updated_at DESC'));
    });

    test('recentlyAdded sorts by created_at DESC', () {
      final c = compiler.compile(
        const FormFilter(DanceForm.contra),
        sort: SearchSort.recentlyAdded,
      );
      expect(c.sql, endsWith('ORDER BY created_at DESC'));
    });

    test('author and lastCalled use the stable title base order', () {
      for (final s in [SearchSort.author, SearchSort.lastCalled]) {
        final c = compiler.compile(const FormFilter(DanceForm.contra), sort: s);
        expect(c.sql, endsWith('ORDER BY title COLLATE NOCASE'));
      }
    });

    test('rating sorts highest-first with NULLs last and a title tiebreak', () {
      final c = compiler.compile(
        const FormFilter(DanceForm.contra),
        sort: SearchSort.rating,
      );
      expect(
        c.sql,
        endsWith('ORDER BY rating IS NULL, rating DESC, title COLLATE NOCASE'),
      );
    });
  });

  group('metadata leaves', () {
    test('CalledFilter scopes caller and performed slots', () {
      const filter = CalledFilter(
        called: true,
        callerFilter: '  Alice ',
        performedOnly: true,
      );
      expect(
        pred(filter),
        'EXISTS (SELECT 1 FROM program_slots ps '
        'JOIN programs p ON p.id = ps.program_id '
        'WHERE ps.dance_id = dances.id AND p.deleted_at IS NULL '
        'AND ps.performed_at IS NOT NULL '
        'AND (p.caller IS NULL OR TRIM(p.caller) = \'\' '
        'OR LOWER(TRIM(p.caller)) = LOWER(TRIM(?))))',
      );
      expect(compiler.compile(filter).binds, ['Alice']);
    });

    test('CalledFilter negates the same existence predicate', () {
      const filter = CalledFilter(called: false);
      expect(
        pred(filter),
        'NOT (EXISTS (SELECT 1 FROM program_slots ps '
        'JOIN programs p ON p.id = ps.program_id '
        'WHERE ps.dance_id = dances.id AND p.deleted_at IS NULL))',
      );
      expect(compiler.compile(filter).binds, isEmpty);
    });

    test('CalledFilter preserves pre-order bind order in a boolean tree', () {
      final filter = AndFilter([
        const FormFilter(DanceForm.contra),
        const CalledFilter(called: true, callerFilter: 'Alice'),
        const StatusFilter(DanceStatus.active),
      ]);
      expect(compiler.compile(filter).binds, ['contra', 'Alice', 'active']);
    });

    test('FullText', () {
      final c = compiler.compile(const FullTextFilter('swing'));
      expect(
        pred(const FullTextFilter('swing')),
        '(id IN (SELECT dance_id FROM dance_substring_fts '
        'WHERE dance_substring_fts MATCH ?) '
        'OR id IN (SELECT dance_id FROM dance_substring_fts '
        'WHERE title MATCH ?))',
      );
      expect(c.binds, ['"swing"', '"swing"']);
    });

    test('Author', () {
      // Joined to `choreographers` since schema v25 (#898): soft delete leaves
      // the `dance_authors` rows behind (no FK cascade fires), so without the
      // tombstone predicate this would keep matching a deleted author's dances.
      expect(
        pred(const AuthorFilter('c1')),
        'id IN (SELECT da.dance_id FROM dance_authors da '
        'JOIN choreographers c ON c.id = da.choreographer_id '
        'WHERE da.choreographer_id = ? AND c.deleted_at IS NULL)',
      );
      expect(compiler.compile(const AuthorFilter('c1')).binds, ['c1']);
    });

    test('Source', () {
      expect(
        pred(const SourceFilter('Zesty')),
        'id IN (SELECT ds.dance_id FROM dance_sources ds '
        'JOIN published_sources ps ON ps.id = ds.source_id '
        'WHERE ps.deleted_at IS NULL AND ('
        "ps.title LIKE '%' || ? || '%' ESCAPE '\\' "
        "OR ps.author LIKE '%' || ? || '%' ESCAPE '\\'))",
      );
      // The query is bound once per LIKE clause (title, then author).
      expect(compiler.compile(const SourceFilter('Zesty')).binds, [
        'Zesty',
        'Zesty',
      ]);
    });

    test('Source escapes LIKE metacharacters in the bound value', () {
      // `%`, `_` and `\` in the user's query must survive as literals, not
      // be interpreted as SQL wildcards/escape by the static ESCAPE clause.
      expect(compiler.compile(const SourceFilter('100%')).binds, [
        r'100\%',
        r'100\%',
      ]);
      expect(compiler.compile(const SourceFilter('do_si')).binds, [
        r'do\_si',
        r'do\_si',
      ]);
      expect(compiler.compile(const SourceFilter(r'back\slash')).binds, [
        r'back\\slash',
        r'back\\slash',
      ]);
      // Plain alphanumeric queries are unaffected (regression).
      expect(compiler.compile(const SourceFilter('Zesty')).binds, [
        'Zesty',
        'Zesty',
      ]);
    });

    test('SourceId', () {
      expect(
        pred(const SourceIdFilter('s1')),
        'id IN (SELECT ds.dance_id FROM dance_sources ds '
        'JOIN published_sources ps ON ps.id = ds.source_id '
        'WHERE ds.source_id = ? AND ps.deleted_at IS NULL)',
      );
      expect(compiler.compile(const SourceIdFilter('s1')).binds, ['s1']);
    });

    test('Tag', () {
      expect(
        pred(const TagFilter('t1')),
        'id IN (SELECT dt.dance_id FROM dance_tags dt '
        'JOIN tags t ON t.id = dt.tag_id '
        'WHERE dt.tag_id = ? AND t.deleted_at IS NULL)',
      );
    });

    test('Form / Formation / Progression / Status bind enum names', () {
      expect(pred(const FormFilter(DanceForm.ecd)), 'form = ?');
      expect(compiler.compile(const FormFilter(DanceForm.ecd)).binds, ['ecd']);
      expect(
        pred(const FormationFilter(FormationShape.becketCw)),
        'formation_shape = ?',
      );
      expect(
        compiler.compile(const FormationFilter(FormationShape.becketCw)).binds,
        ['becketCw'],
      );
      expect(
        pred(const ProgressionFilter(Progression.double)),
        'progression = ?',
      );
      expect(pred(const StatusFilter(DanceStatus.broken)), 'status = ?');
      expect(compiler.compile(const StatusFilter(DanceStatus.broken)).binds, [
        'broken',
      ]);
    });
  });

  group('level leaves', () {
    test('LevelFilter eq is a plain name match', () {
      expect(pred(const LevelFilter(DanceLevel.intermediate)), 'level = ?');
      expect(
        compiler.compile(const LevelFilter(DanceLevel.intermediate)).binds,
        ['intermediate'],
      );
    });

    test('LevelFilter lte compiles an ordered CASE with a NULL guard', () {
      expect(
        pred(const LevelFilter(DanceLevel.intermediate, LevelOp.lte)),
        'level IS NOT NULL AND (CASE level '
        "WHEN 'beginner' THEN 0 "
        "WHEN 'intermediate' THEN 1 "
        "WHEN 'advanced' THEN 2 END) <= ?",
      );
      expect(
        compiler
            .compile(const LevelFilter(DanceLevel.intermediate, LevelOp.lte))
            .binds,
        [DanceLevel.intermediate.index],
      );
    });

    test('LevelFilter gte compiles an ordered CASE with a NULL guard', () {
      expect(
        pred(const LevelFilter(DanceLevel.advanced, LevelOp.gte)),
        'level IS NOT NULL AND (CASE level '
        "WHEN 'beginner' THEN 0 "
        "WHEN 'intermediate' THEN 1 "
        "WHEN 'advanced' THEN 2 END) >= ?",
      );
      expect(
        compiler
            .compile(const LevelFilter(DanceLevel.advanced, LevelOp.gte))
            .binds,
        [DanceLevel.advanced.index],
      );
    });

    test('MixedLevelFilter matches mixed_level with a 1/0 bind', () {
      expect(pred(const MixedLevelFilter(true)), 'mixed_level = ?');
      expect(compiler.compile(const MixedLevelFilter(true)).binds, [1]);
      expect(compiler.compile(const MixedLevelFilter(false)).binds, [0]);
    });

    test('RatingFilter compiles a minimum-rating floor with the bind', () {
      expect(pred(const RatingFilter(4)), 'rating >= ?');
      expect(compiler.compile(const RatingFilter(4)).binds, [4]);
      // The scale boundaries compile fine.
      expect(compiler.compile(const RatingFilter(1)).binds, [1]);
      expect(compiler.compile(const RatingFilter(5)).binds, [5]);
    });

    test('level leaves compose under And/Or with pre-order binds', () {
      final c = compiler.compile(
        const AndFilter([
          LevelFilter(DanceLevel.beginner, LevelOp.gte),
          MixedLevelFilter(false),
        ]),
      );
      expect(c.binds, [DanceLevel.beginner.index, 0]);
    });
  });

  group('combinators', () {
    test('empty And is TRUE, empty Or is FALSE', () {
      expect(compiler.compile(const AndFilter([])).sql, contains('AND (1)'));
      expect(compiler.compile(const OrFilter([])).sql, contains('AND (0)'));
    });

    test('And joins with AND, Or with OR, Not negates', () {
      expect(
        pred(
          const AndFilter([
            FormFilter(DanceForm.contra),
            StatusFilter(DanceStatus.active),
          ]),
        ),
        '(form = ? AND status = ?)',
      );
      expect(
        pred(
          const OrFilter([
            FormFilter(DanceForm.contra),
            FormFilter(DanceForm.ecd),
          ]),
        ),
        '(form = ? OR form = ?)',
      );
      expect(
        pred(const NotFilter(FormFilter(DanceForm.square))),
        'NOT (form = ?)',
      );
    });

    test('binds are collected pre-order, left-to-right', () {
      final c = compiler.compile(
        const AndFilter([
          FormFilter(DanceForm.contra),
          OrFilter([AuthorFilter('a1'), TagFilter('t1')]),
          StatusFilter(DanceStatus.active),
        ]),
      );
      expect(c.binds, ['contra', 'a1', 't1', 'active']);
    });
  });

  group('custom fields', () {
    CustomFieldDef def(CustomFieldType t, {List<String>? choices}) =>
        CustomFieldDef(
          id: 'fid',
          key: 'k',
          label: 'K',
          type: t,
          choices: choices,
        );

    test('contains', () {
      final f = CustomFieldFilter(
        def(CustomFieldType.text),
        CustomFieldOp.contains,
        'jig',
      );
      expect(
        pred(f),
        "EXISTS (SELECT 1 FROM custom_field_values v "
        "WHERE v.dance_id = dances.id AND v.field_id = ? "
        "AND v.value_text LIKE '%' || ? || '%' ESCAPE '\\')",
      );
      expect(compiler.compile(f).binds, ['fid', 'jig']);
    });

    test('contains escapes LIKE metacharacters in the bound value', () {
      final f = CustomFieldFilter(
        def(CustomFieldType.text),
        CustomFieldOp.contains,
        '50%_off',
      );
      expect(compiler.compile(f).binds, ['fid', r'50\%\_off']);
    });

    test('equals / number ops / between', () {
      expect(
        compiler
            .compile(
              CustomFieldFilter(
                def(CustomFieldType.number),
                CustomFieldOp.between,
                [2, 8],
              ),
            )
            .binds,
        ['fid', 2, 8],
      );
      expect(
        pred(
          CustomFieldFilter(
            def(CustomFieldType.number),
            CustomFieldOp.between,
            [2, 8],
          ),
        ),
        endsWith('AND v.value_num BETWEEN ? AND ?)'),
      );
      expect(
        pred(
          CustomFieldFilter(def(CustomFieldType.number), CustomFieldOp.lt, 4),
        ),
        endsWith('AND v.value_num < ?)'),
      );
    });

    test('boolean is binds 1/0', () {
      expect(
        compiler
            .compile(
              CustomFieldFilter(
                def(CustomFieldType.boolean),
                CustomFieldOp.is_,
                true,
              ),
            )
            .binds,
        ['fid', 1],
      );
      expect(
        compiler
            .compile(
              CustomFieldFilter(
                def(CustomFieldType.boolean),
                CustomFieldOp.is_,
                false,
              ),
            )
            .binds,
        ['fid', 0],
      );
    });

    test('choice in expands placeholders and binds each value', () {
      final f = CustomFieldFilter(
        def(CustomFieldType.choice, choices: ['a', 'b', 'c']),
        CustomFieldOp.in_,
        ['a', 'c'],
      );
      expect(pred(f), endsWith('AND v.value_text IN (?, ?))'));
      expect(compiler.compile(f).binds, ['fid', 'a', 'c']);
    });
  });

  group('structural: FigureFilter', () {
    test('leaf with move only', () {
      expect(
        pred(FigureFilter.leaf('swing')),
        'id IN (SELECT f.dance_id FROM dance_figures f WHERE f.move = ?)',
      );
    });

    test('leaf with params (sorted) and section', () {
      final f = FigureFilter.leaf(
        'swing',
        params: const {'who': 'partners', 'beats': 8},
        section: 'A1',
      );
      expect(
        pred(f),
        'id IN (SELECT f.dance_id FROM dance_figures f WHERE '
        "(f.move = ? "
        "AND json_extract(f.params_json, '\$.beats') = ? "
        "AND json_extract(f.params_json, '\$.who') = ? "
        'AND f.section = ?))',
      );
      // Params emitted in sorted key order: beats before who.
      expect(compiler.compile(f).binds, ['swing', 8, 'partners', 'A1']);
    });

    test('FigureAnd combines clauses on one row', () {
      final f = FigureFilter(
        FigureAnd([FigureLeaf('swing', section: 'B1'), FigureLeaf('balance')]),
      );
      expect(
        pred(f),
        'id IN (SELECT f.dance_id FROM dance_figures f WHERE '
        '((f.move = ? AND f.section = ?) AND f.move = ?))',
      );
      expect(compiler.compile(f).binds, ['swing', 'B1', 'balance']);
    });

    test('FigureOr combines with OR', () {
      final f = FigureFilter(
        FigureOr([FigureLeaf('swing'), FigureLeaf('balance')]),
      );
      expect(pred(f), endsWith('WHERE (f.move = ? OR f.move = ?))'));
    });

    test('top-level FigureNot compiles to NOT IN', () {
      final f = FigureFilter(FigureNot(FigureLeaf('swing')));
      expect(
        pred(f),
        'id NOT IN (SELECT f.dance_id FROM dance_figures f WHERE f.move = ?)',
      );
    });

    test('FigureNot nested inside FigureAnd negates that clause', () {
      final f = FigureFilter(
        FigureAnd([FigureLeaf('swing'), FigureNot(FigureLeaf('balance'))]),
      );
      expect(
        pred(f),
        endsWith('WHERE (f.move = ? AND NOT COALESCE((f.move = ?), 0)))'),
      );
    });
  });

  group('sequence: ThenFilter', () {
    test('self-join on group_idx with before/after clauses and bind order', () {
      final f = ThenFilter(
        FigureLeaf('petronella', section: 'B1'),
        FigureLeaf('swing'),
      );
      expect(
        pred(f),
        'id IN (SELECT a.dance_id FROM dance_figures a '
        'JOIN dance_figures b ON a.dance_id = b.dance_id '
        'AND a.group_idx < b.group_idx '
        'WHERE ((a.move = ? AND a.section = ?)) AND (b.move = ?))',
      );
      expect(compiler.compile(f).binds, ['petronella', 'B1', 'swing']);
    });
  });

  group('worked example (search.md)', () {
    test('binds in emission order', () {
      final f = AndFilter([
        const FormFilter(DanceForm.contra),
        ThenFilter(
          FigureLeaf('petronella', section: 'B1'),
          FigureLeaf('swing'),
        ),
      ]);
      final c = compiler.compile(f);
      expect(c.binds, ['contra', 'petronella', 'B1', 'swing']);
      expect(c.sql, endsWith('ORDER BY title COLLATE NOCASE'));
    });
  });

  group('relevance / bm25', () {
    test('short bare FullText with relevance sort orders by bm25', () {
      final c = compiler.compile(
        const FullTextFilter('re'),
        sort: SearchSort.relevance,
      );
      expect(
        c.sql,
        'SELECT dance_fts.dance_id FROM dance_fts '
        'JOIN dances ON dances.id = dance_fts.dance_id '
        'WHERE dance_fts MATCH ? AND dances.deleted_at IS NULL '
        'ORDER BY bm25(dance_fts)',
      );
      expect(c.binds, ['("re"* OR title : "re"*)']);
    });

    test(
      'long bare FullText relevance degrades to the substring result set',
      () {
        final c = compiler.compile(
          const FullTextFilter('reel'),
          sort: SearchSort.relevance,
        );
        expect(c.sql, contains('dance_substring_fts'));
        expect(c.sql, isNot(contains('bm25')));
      },
    );

    test('relevance on a non-bare tree degrades to title order', () {
      final c = compiler.compile(
        const AndFilter([FullTextFilter('reel'), FormFilter(DanceForm.contra)]),
        sort: SearchSort.relevance,
      );
      expect(c.sql, endsWith('ORDER BY title COLLATE NOCASE'));
      expect(c.sql, isNot(contains('bm25')));
    });
  });

  group('sort direction', () {
    const f = FormFilter(DanceForm.contra);

    test('defaultDirection matches each key historical order', () {
      expect(SearchSort.title.defaultDirection, SortDirection.ascending);
      expect(SearchSort.author.defaultDirection, SortDirection.ascending);
      expect(SearchSort.composedOn.defaultDirection, SortDirection.ascending);
      expect(SearchSort.relevance.defaultDirection, SortDirection.ascending);
      expect(
        SearchSort.recentlyAdded.defaultDirection,
        SortDirection.descending,
      );
      expect(
        SearchSort.recentlyEdited.defaultDirection,
        SortDirection.descending,
      );
      expect(SearchSort.rating.defaultDirection, SortDirection.descending);
      expect(SearchSort.lastCalled.defaultDirection, SortDirection.descending);
    });

    test('omitted direction is byte-identical to the historical fragment', () {
      // Ascending-default keys omit the ASC keyword.
      expect(
        compiler.compile(f, sort: SearchSort.title).sql,
        endsWith('ORDER BY title COLLATE NOCASE'),
      );
      expect(
        compiler.compile(f, sort: SearchSort.composedOn).sql,
        endsWith(
          'ORDER BY composed_on IS NULL, composed_on, title COLLATE NOCASE',
        ),
      );
      // Descending-default keys keep their DESC.
      expect(
        compiler.compile(f, sort: SearchSort.recentlyAdded).sql,
        endsWith('ORDER BY created_at DESC'),
      );
      expect(
        compiler.compile(f, sort: SearchSort.rating).sql,
        endsWith('ORDER BY rating IS NULL, rating DESC, title COLLATE NOCASE'),
      );
    });

    test('title flips ASC/DESC', () {
      expect(
        compiler
            .compile(
              f,
              sort: SearchSort.title,
              direction: SortDirection.ascending,
            )
            .sql,
        endsWith('ORDER BY title COLLATE NOCASE'),
      );
      expect(
        compiler
            .compile(
              f,
              sort: SearchSort.title,
              direction: SortDirection.descending,
            )
            .sql,
        endsWith('ORDER BY title COLLATE NOCASE DESC'),
      );
    });

    test('recentlyAdded / recentlyEdited flip to ascending', () {
      expect(
        compiler
            .compile(
              f,
              sort: SearchSort.recentlyAdded,
              direction: SortDirection.ascending,
            )
            .sql,
        endsWith('ORDER BY created_at'),
      );
      expect(
        compiler
            .compile(
              f,
              sort: SearchSort.recentlyEdited,
              direction: SortDirection.ascending,
            )
            .sql,
        endsWith('ORDER BY updated_at'),
      );
    });

    test('composedOn keeps NULLs last + title tiebreak when descending', () {
      expect(
        compiler
            .compile(
              f,
              sort: SearchSort.composedOn,
              direction: SortDirection.descending,
            )
            .sql,
        endsWith(
          'ORDER BY composed_on IS NULL, composed_on DESC, title COLLATE NOCASE',
        ),
      );
    });

    test('rating keeps NULLs last + title tiebreak when ascending', () {
      expect(
        compiler
            .compile(
              f,
              sort: SearchSort.rating,
              direction: SortDirection.ascending,
            )
            .sql,
        endsWith('ORDER BY rating IS NULL, rating, title COLLATE NOCASE'),
      );
    });

    test('author / lastCalled keep the ascending title base in SQL', () {
      // Their requested direction is applied by the Dart post-sort, so the SQL
      // base order stays the stable ascending title order regardless.
      for (final s in [SearchSort.author, SearchSort.lastCalled]) {
        expect(
          compiler.compile(f, sort: s, direction: SortDirection.descending).sql,
          endsWith('ORDER BY title COLLATE NOCASE'),
        );
      }
    });

    test('relevance flips bm25 direction', () {
      expect(
        compiler
            .compile(
              const FullTextFilter('re'),
              sort: SearchSort.relevance,
              direction: SortDirection.descending,
            )
            .sql,
        endsWith('ORDER BY bm25(dance_fts) DESC'),
      );
    });
  });

  group('dialect canonicalization at the compiler boundary', () {
    test('FullText role terms are canonicalized', () {
      final c = FilterCompiler(
        Dialect.larksRobins,
      ).compile(const FullTextFilter('robins allemande'));
      // Canonicalized to role tokens while keeping the long query as one
      // literal substring phrase.
      expect(c.binds.first, '"role2s allemande"');
    });

    test('role-valued figure params are canonicalized', () {
      final c = FilterCompiler(
        Dialect.larksRobins,
      ).compile(FigureFilter.leaf('swing', params: const {'who': 'larks'}));
      expect(c.binds, ['swing', 'role1s']);
    });

    test('non-role param values pass through verbatim', () {
      final c = FilterCompiler(
        Dialect.larksRobins,
      ).compile(FigureFilter.leaf('swing', params: const {'who': 'partners'}));
      expect(c.binds, ['swing', 'partners']);
    });
  });
}
