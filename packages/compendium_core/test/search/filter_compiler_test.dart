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

    test('author and lastCalled use the stable title base order', () {
      for (final s in [SearchSort.author, SearchSort.lastCalled]) {
        final c = compiler.compile(const FormFilter(DanceForm.contra), sort: s);
        expect(c.sql, endsWith('ORDER BY title COLLATE NOCASE'));
      }
    });
  });

  group('metadata leaves', () {
    test('FullText', () {
      final c = compiler.compile(const FullTextFilter('swing'));
      expect(
        pred(const FullTextFilter('swing')),
        'id IN (SELECT dance_id FROM dance_fts WHERE dance_fts MATCH ?)',
      );
      expect(c.binds, ['swing']);
    });

    test('Author', () {
      expect(
        pred(const AuthorFilter('c1')),
        'id IN (SELECT dance_id FROM dance_authors WHERE choreographer_id = ?)',
      );
      expect(compiler.compile(const AuthorFilter('c1')).binds, ['c1']);
    });

    test('Tag', () {
      expect(
        pred(const TagFilter('t1')),
        'id IN (SELECT dance_id FROM dance_tags WHERE tag_id = ?)',
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
        "AND v.value_text LIKE '%' || ? || '%')",
      );
      expect(compiler.compile(f).binds, ['fid', 'jig']);
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
    test('self-join on idx with before/after clauses and bind order', () {
      final f = ThenFilter(
        FigureLeaf('petronella', section: 'B1'),
        FigureLeaf('swing'),
      );
      expect(
        pred(f),
        'id IN (SELECT a.dance_id FROM dance_figures a '
        'JOIN dance_figures b ON a.dance_id = b.dance_id '
        'AND a.idx < b.idx '
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
    test('bare FullText with relevance sort orders by bm25', () {
      final c = compiler.compile(
        const FullTextFilter('reel'),
        sort: SearchSort.relevance,
      );
      expect(
        c.sql,
        'SELECT dance_fts.dance_id FROM dance_fts '
        'JOIN dances ON dances.id = dance_fts.dance_id '
        'WHERE dance_fts MATCH ? AND dances.deleted_at IS NULL '
        'ORDER BY bm25(dance_fts)',
      );
      expect(c.binds, ['reel']);
    });

    test('relevance on a non-bare tree degrades to title order', () {
      final c = compiler.compile(
        const AndFilter([FullTextFilter('reel'), FormFilter(DanceForm.contra)]),
        sort: SearchSort.relevance,
      );
      expect(c.sql, endsWith('ORDER BY title COLLATE NOCASE'));
      expect(c.sql, isNot(contains('bm25')));
    });
  });

  group('dialect canonicalization at the compiler boundary', () {
    test('FullText role terms are canonicalized', () {
      final c = FilterCompiler(
        Dialect.larksRobins,
      ).compile(const FullTextFilter('robins allemande'));
      expect(c.binds.single, 'role2s allemande');
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
