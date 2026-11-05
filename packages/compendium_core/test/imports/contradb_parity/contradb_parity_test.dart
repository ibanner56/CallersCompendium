// Differential parity suite: for the same dances, an Advanced query must select
// the same dances in the Collection (FilterCompiler over `dance_figures`) as it
// does on ContraDB (translator + ContraDB's filter semantics).
//
//   ContraDB truth : each dance's `move` list -> [contradb_reference.dart]
//   Collection     : the rendered lines, imported by the real
//                    ContraDbHtmlAdapter, stored in an in-memory database and
//                    searched by FilterCompiler.
//
// Where the two sides cannot agree because of HOW THE DATA ARRIVES (the importer
// restructures a ContraDB figure), a query cannot be refused up front; those
// dances are pinned in the 'structural differences' group rather than hidden.
import 'dart:math';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../../storage/test_database.dart';
import 'contradb_reference.dart';
import 'corpus.dart';

/// A dance on both sides.
class ParityDance {
  ParityDance(this.id, this.figures);
  final String id;
  final List<ContraFig> figures;

  ContraDbDance get contra => ContraDbDance(
    id: id,
    moves: [for (final f in figures) f.move],
    aliases: [for (final f in figures) f.alias],
    title: id,
  );
}

String describe(Object? n) => switch (n) {
  AndFilter(:final children) => 'all(${children.map(describe).join(', ')})',
  OrFilter(:final children) => 'any(${children.map(describe).join(', ')})',
  NotFilter(:final child) => 'none(${describe(child)})',
  FigureFilter(:final query) => 'has(${describe(query)})',
  ThenFilter(:final before, :final after) =>
    'then(${describe(before)}, ${describe(after)})',
  FigureLeaf(:final move) => move,
  FigureAnd(:final children) => '&(${children.map(describe).join(', ')})',
  FigureOr(:final children) => '|(${children.map(describe).join(', ')})',
  FigureNot(:final child) => '!${describe(child)}',
  _ => '$n',
};

Future<void> main() async {
  final db = openTestDatabase();
  final dances = DanceRepository(db, contraTaxonomy);
  final contraDances = <ParityDance>[];

  Future<void> store(ParityDance d) async {
    final figures = await importedFigures(contraDbPage(d.id, 'C', d.figures));
    await dances.create(
      Dance(
        id: d.id,
        title: d.id,
        figures: figures,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    contraDances.add(d);
  }

  final byKey = {for (final f in cleanFigures) f.key: f};
  ContraFig fig(String key) => byKey[key]!;

  // ---- the clean corpus --------------------------------------------------
  // Hand-picked edge shapes first, then seeded random dances over a small
  // alphabet (repeats and collisions are what exercise the set semantics).
  const alphabet = [
    'swing',
    'balance',
    'chain',
    'circle',
    'do-si-do',
    'long-lines',
    'petronella',
    'rlt',
    'star',
    'allemande',
    'pass-through',
    'box-the-gnat',
  ];
  setUpAll(() async {
    final named = <String, List<String>>{
      'zero': [],
      'one-chain': ['chain'],
      'one-swing': ['swing'],
      'chain-swing': ['chain', 'swing'],
      'swing-chain': ['swing', 'chain'],
      'swing-x-chain': ['swing', 'balance', 'chain'],
      'chain-x-swing': ['chain', 'balance', 'swing'],
      'wrap-ends': ['swing', 'balance', 'circle', 'chain'],
      'chain-chain': ['chain', 'chain'],
      'swing-swing-swing': ['swing', 'swing', 'swing'],
      'all-different': ['chain', 'swing', 'circle', 'star', 'allemande'],
    };
    for (final e in named.entries) {
      await store(ParityDance(e.key, [for (final k in e.value) fig(k)]));
    }
    // One single-figure dance per catalogue figure: every mapped move is
    // queried against a dance that has exactly it.
    for (final f in cleanFigures) {
      await store(ParityDance('v-${f.key}', [f]));
    }
    final rnd = Random(20261105);
    for (var i = 0; i < 240; i++) {
      final n = rnd.nextInt(7); // 0..6 figures
      await store(
        ParityDance('r$i', [
          for (var j = 0; j < n; j++)
            fig(alphabet[rnd.nextInt(alphabet.length)]),
        ]),
      );
    }
  });
  tearDownAll(() => db.close());

  // ---- tree generation ----------------------------------------------------
  final localIds = [for (final f in cleanFigures) ...f.local!].toSet().toList()
    ..sort();

  FigureLeaf leaf(Random r, List<String> pool) =>
      FigureLeaf(pool[r.nextInt(pool.length)]);

  FigureQuery figureQuery(Random r, List<String> pool, int depth) {
    if (depth <= 0 || r.nextInt(3) == 0) return leaf(r, pool);
    final k = 2 + r.nextInt(2);
    final kids = [for (var i = 0; i < k; i++) figureQuery(r, pool, depth - 1)];
    return switch (r.nextInt(3)) {
      0 => FigureAnd(kids),
      1 => FigureOr(kids),
      _ => FigureNot(kids.first),
    };
  }

  DanceFilter danceFilter(Random r, List<String> pool, int depth) {
    final c = depth <= 0 ? 0 : r.nextInt(6);
    switch (c) {
      case 0:
      case 1:
        return FigureFilter(figureQuery(r, pool, 2));
      case 2:
      case 3:
        final k = 2 + r.nextInt(2);
        final kids = [
          for (var i = 0; i < k; i++) danceFilter(r, pool, depth - 1),
        ];
        return r.nextBool() ? AndFilter(kids) : OrFilter(kids);
      case 4:
        return NotFilter(danceFilter(r, pool, depth - 1));
      default:
        return ThenFilter(figureQuery(r, pool, 1), figureQuery(r, pool, 1));
    }
  }

  /// Runs [filter] both ways. Returns null when the translator refuses.
  Future<({List<String> local, List<String> contra})?> both(
    DanceFilter filter,
  ) async {
    final t = translateDanceFilterToContraDb(filter);
    if (t is! ContraDbAdvancedExpression) return null;
    final local = (await dances.search(filter)).toList()..sort();
    final contra = contraDbMatchingIds(
      t.expression,
      contraDances.map((d) => d.contra),
    ).toList()..sort();
    return (local: local, contra: contra);
  }

  group('clean corpus: Collection and ContraDB select the same dances', () {
    test(
      'every catalogue line imports to the Collection move recorded for it',
      () async {
        for (final f in cleanFigures) {
          final got = [
            for (final x in await importedFigures(contraDbPage('t', 'c', [f])))
              x.move,
          ];
          expect(got, f.local, reason: f.key);
        }
      },
    );

    test('the corpus has the shapes the audit needs', () {
      expect(contraDances.where((d) => d.figures.isEmpty), isNotEmpty);
      expect(contraDances.where((d) => d.figures.length == 1), isNotEmpty);
      expect(
        contraDances.where(
          (d) => d.figures.map((f) => f.key).toSet().length < d.figures.length,
        ),
        isNotEmpty,
        reason: 'repeated moves',
      );
    });

    test('hand-picked constructs agree', () async {
      final swing = FigureFilter.leaf('swing');
      final chain = FigureFilter.leaf('chain');
      final cases = <String, DanceFilter>{
        'figure': swing,
        'figure (multi-word id)': FigureFilter.leaf('do_si_do'),
        'figure (pull_by -> or)': FigureFilter.leaf('pull_by'),
        'all of': AndFilter([swing, chain]),
        'any of': OrFilter([swing, chain]),
        'none of': NotFilter(OrFilter([swing, chain])),
        'not (dance)': NotFilter(swing),
        'has no figure': FigureFilter(FigureNot(FigureLeaf('swing'))),
        'figure and': FigureFilter(
          FigureAnd([FigureLeaf('swing'), FigureLeaf('balance')]),
        ),
        'figure and (same figure, never)': FigureFilter(
          FigureAnd([FigureLeaf('swing'), FigureLeaf('chain')]),
        ),
        'figure or': FigureFilter(
          FigureOr([FigureLeaf('swing'), FigureLeaf('chain')]),
        ),
        'figure and not': FigureFilter(
          FigureAnd([FigureLeaf('swing'), FigureNot(FigureLeaf('chain'))]),
        ),
        'figure not not': FigureFilter(
          FigureNot(FigureNot(FigureLeaf('swing'))),
        ),
        'all(none, figure)': AndFilter([NotFilter(chain), swing]),
        'any(none, none)': OrFilter([NotFilter(chain), NotFilter(swing)]),
        'none(all)': NotFilter(AndFilter([swing, chain])),
      };
      for (final e in cases.entries) {
        final r = await both(e.value);
        expect(r, isNotNull, reason: '${e.key} was refused');
        expect(r!.local, r.contra, reason: '${e.key}: ${describe(e.value)}');
      }
    });

    test('randomised trees agree (seeded)', () async {
      final r = Random(7);
      var compared = 0;
      var refused = 0;
      var sequence = 0;
      final failures = <String>[];
      for (var i = 0; i < 1500; i++) {
        final tree = danceFilter(r, localIds, 3);
        final both_ = await both(tree);
        if (both_ == null) {
          refused++;
          if (describe(tree).contains('then(')) sequence++;
          continue;
        }
        compared++;
        if (both_.local.join(',') != both_.contra.join(',')) {
          failures.add(
            '${describe(tree)}\n  collection-only: ${both_.local.toSet().difference(both_.contra.toSet())}'
            '\n  contradb-only : ${both_.contra.toSet().difference(both_.local.toSet())}',
          );
        }
      }
      // ignore: avoid_print
      print(
        'randomised: compared=$compared refused=$refused (then: $sequence) '
        'over ${contraDances.length} dances',
      );
      expect(failures, isEmpty, reason: failures.take(5).join('\n'));
      expect(
        compared,
        greaterThan(500),
        reason: 'too few trees were translatable',
      );
    });
  });

  group('vocabulary: every translatable Collection move agrees', () {
    test('each mapped move id, alone and negated', () async {
      for (final id in localIds) {
        for (final filter in <DanceFilter>[
          FigureFilter.leaf(id),
          NotFilter(FigureFilter.leaf(id)),
          FigureFilter(FigureNot(FigureLeaf(id))),
        ]) {
          final r = await both(filter);
          expect(r, isNotNull, reason: '$id was refused');
          expect(r!.local, r.contra, reason: describe(filter));
        }
      }
    });

    test(
      'every ContraDB move is reached by a mapped id or is a documented gap',
      () {
        final reached = <String>{};
        for (final id in contraTaxonomy.moves.keys) {
          final t = translateDanceFilterToContraDb(FigureFilter.leaf(id));
          if (t is ContraDbAdvancedExpression) {
            void walk(Object? e) {
              if (e is List && e.isNotEmpty && e.first == 'figure')
                reached.add(e[1] as String);
              if (e is List) e.forEach(walk);
            }

            walk(t.expression);
          }
        }
        const documentedGaps = {
          'meltdown swing', // alias of swing{prefix: meltdown}: refused
          'custom', 'star promenade', 'allemande orbit',
          'pull by dancers', 'pull by direction', // only via pull_by (or)
        };
        final missing = contraDbDefinedMoves.keys.toSet()
          ..removeAll(reached)
          ..removeAll(documentedGaps);
        expect(
          missing,
          isEmpty,
          reason: 'ContraDB moves with no Collection id',
        );
        // ...and nothing the translator emits is a name ContraDB lacks.
        expect(reached.difference(contraDbDefinedMoves.keys.toSet()), isEmpty);
        // Every accepted id is a real Collection move.
        for (final id in localIds) {
          expect(
            contraTaxonomy.moves.containsKey(id) ||
                contraTaxonomy.aliases.containsKey(id),
            isTrue,
            reason: id,
          );
        }
      },
    );
  });
}
