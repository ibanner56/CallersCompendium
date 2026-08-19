// Tests for #843 Part A: `star_promenade` loses its `hand` param at taxonomy
// v26, TCB imports keep their prose `who` and gain a center NOTE, ContraDB
// star promenades fall to custom, and stored figures are retired by a one-time
// pass.
//
// ## Why the note, and not a param
//
// `star_promenade.who` used to mean two different things depending on which
// adapter wrote it. ContraDB's `who`+`hand` name, AS A PAIR, the dancers with a
// hand in the CENTER; TCB's prose subject names the dancer you PICK UP on the
// side. The owner ruled on 2026-08-06 that TCB's reading is what we store, and
// removed `hand` — because rendering "Neighbor star promenade right ½" implies
// a right-hand connection with the NEIGHBOR when the right-hand connection is
// between the two dancers in the center.
//
// TCB's own flutterwheel decomposition shows both facts in one figure, which is
// why they cannot share a slot:
//
//   (8) Neighbor flutterwheel -> (4) Women allemande right 1/2
//                              + (4) Neighbor star promenade 1/2 (WR)
//
// `who` is `neighbors` (whom you promenade); `(WR)` names the women (who form
// the star). Different sets.
//
// ## Corpus figures quoted below
//
// Measured against pristine `c9a0185f` over the 24,107-file Caller's Box mirror
// (20,516 parseable dances / 11,499 `Permission: full`, both reproducing the
// documented denominators): 626 raw lines import as `star_promenade`, ALL 626
// carry an annotation, 625 of which are exactly one mapped `<code><R|L>` cell
// (`m` 358, `w` 265, `n`/`n1` 2) and 1 of which is an unmapped `c` prefix. ZERO
// carry a prose hand — so the visible change for TCB imports is the removal of
// a DEFAULTED "right" that rendered on every one of these figures.
//
// ## Folding is tested through the ADAPTER
//
// `parseFigureLines` does not run `CallersBoxAdapter`'s cross-line merge, so a
// test that only calls the parser cannot see what an import actually produces.
// The end-to-end cases below go through `CallersBoxAdapter.parse`.

import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:test/test.dart';

Map<String, Object?> _dance({
  String id = '1',
  String name = 'Test Dance',
  List<Map<String, Object?>>? phrases,
}) => {
  'ID': id,
  'Name': name,
  'Permission': 'full',
  'FormationBase': 'Duple Minor - Improper',
  'Progression': 'Single',
  'phrases': ?phrases,
};

Map<String, Object?> _phrase(String name, List<String> figures) => {
  'name': name,
  'figures': figures,
};

Future<StructuredDraft> _importTcb(List<String> lines) async {
  final adapter = CallersBoxAdapter();
  final payload = jsonEncode(_dance(phrases: [_phrase('A1', lines)]));
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

/// The single figure a one-line TCB import produces.
Future<Figure> _importTcbLine(String line) async =>
    (await _importTcb([line])).dance.figures.single;

void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  // -------------------------------------------------------------------------
  // A1 — the taxonomy change
  // -------------------------------------------------------------------------

  group('A1 — star_promenade loses `hand` (taxonomy v26)', () {
    test('contraTaxonomyVersion is 30', () {
      expect(contraTaxonomyVersion, 30);
      expect(tax.version, 30);
    });

    // Mutation caught: re-declaring the param, in any form.
    test('the MoveDef declares no hand param', () {
      final def = tax.resolve('star_promenade')!;
      expect(def.params.keys, ['who', 'turn', 'beats']);
      expect(def.params.containsKey('hand'), isFalse);
    });

    // Mutation caught: reverting the renderTemplate while leaving the param
    // removed (which would render a literal `{hand}` or nothing at all), or
    // re-adding both.
    test('the render template carries no {hand} token', () {
      final def = tax.resolve('star_promenade')!;
      expect(def.renderTemplate, '{who} {move} {turn}');
      expect(def.renderTemplate.contains('{hand}'), isFalse);
    });

    // Mutation caught: a "compatibility" default that keeps filling `hand`.
    test('effectiveParams no longer surfaces a hand', () {
      final params = tax.effectiveParams(Figure(move: 'star_promenade'));
      expect(params.containsKey('hand'), isFalse);
      expect(params['who'], 'role1s');
      expect(params['turn'], 0.5);
    });

    // Mutation caught: leaving `hand` in the template or the params, either of
    // which puts "right" back into the rendered line — the misinformation the
    // owner's ruling removes.
    test('the rendered line states no hand', () {
      final f = Figure(move: 'star_promenade', params: {'who': 'neighbors'});
      expect(renderer.renderCanonical(f), 'neighbors star promenade ½');
      // The display renderer singularizes the subject; what matters here is
      // that no hand appears in EITHER form.
      expect(
        renderer.render(f, Dialect.larksRobins),
        'neighbor star promenade ½',
      );
    });

    // A stored `hand` is INERT once the MoveDef stops declaring it, because
    // effectiveParams iterates the MoveDef's params. This is the property the
    // one-time strip relies on for being hygiene rather than a correctness fix,
    // and the property that makes skipping a redundant rebuild safe — so it is
    // asserted rather than assumed.
    test('a stored hand is ignored by rendering and by the canonical key', () {
      final bare = Figure(move: 'star_promenade', params: {'who': 'partners'});
      // invalid-fixture: pre-v26 stored data — `star_promenade` carried `hand`
      // until #843 removed it. This figure is the shape an existing database
      // holds, and the test exists to prove such a value is inert; a fixture
      // valid under the current taxonomy could not exercise that at all.
      final stale = Figure(
        move: 'star_promenade',
        params: {'who': 'partners', 'hand': 'left'},
      );
      expect(renderer.renderCanonical(stale), renderer.renderCanonical(bare));
      expect(figureCanonicalKey(stale, tax), figureCanonicalKey(bare, tax));
      expect(figureCanonicalKey(bare, tax).contains('hand'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // A3 — TCB keeps `who`, and notes the center
  // -------------------------------------------------------------------------

  group('A3 — TCB import keeps `who` and notes the center', () {
    // THE test for this part. The naive implementation — the one a reader who
    // has not internalised the ruling would write — reads `(WR)` as the
    // subject and overwrites `who` with `role2s`. This asserts both halves
    // unconditionally, so that mutation cannot pass.
    test('`(WR)` becomes a center note and never touches `who`', () async {
      final f = await _importTcbLine('(4) Neighbor star promenade 1/2 (WR)');
      expect(f.move, 'star_promenade');
      expect(f.params['who'], 'neighbors');
      expect(f.note, 'role2s by the right in the center');
    });

    test('`(ML)` decodes the other role and the other hand', () async {
      final f = await _importTcbLine('(4) Partner star promenade 1/2 (ML)');
      expect(f.move, 'star_promenade');
      expect(f.params['who'], 'partners');
      expect(f.note, 'role1s by the left in the center');
    });

    // Mutation caught: emitting the source letter (`W`/`M`) instead of the
    // canonical role token. That would render as frozen gendered text in every
    // dialect, permanently — the failure mode is invisible under the canonical
    // dialect, so the dialect render is asserted explicitly.
    test('the note holds a canonical role token, never W/M', () async {
      final f = await _importTcbLine('(4) Neighbor star promenade 1/2 (WR)');
      final note = f.note!;
      expect(note, contains('role2s'));
      expect(note, isNot(matches(RegExp(r'\b[WM]\b'))));
      // renderFreeText preserves the source's case, and the stored token is
      // lowercase — so the substitution shows up as `robins` / `follows`. The
      // point is that the WORD changes with the dialect, which a literal `W`
      // never would.
      expect(
        renderer.renderFreeText(note, Dialect.larksRobins),
        'robins by the right in the center',
      );
      expect(
        renderer.renderFreeText(note, Dialect.leadsFollows),
        'follows by the right in the center',
      );
    });

    // Mutation caught: approximating an unmapped people code onto some nearby
    // token. `c` (TCB square corners) has no taxonomy equivalent, so the
    // annotation must survive verbatim instead of being decoded. This is the
    // real corpus line 5018 in miniature — the single non-conforming
    // annotation among the 626.
    test(
      'an unmapped people code is preserved verbatim, not decoded',
      () async {
        final f = await _importTcbLine('(4) Partner star promenade 1 (CL)');
        expect(f.move, 'star_promenade');
        expect(f.params['who'], 'partners');
        expect(f.note, 'CL');
        expect(f.note, isNot(contains('in the center')));
      },
    );

    // Mutation caught: collapsing a `;`-run onto its first cell. A star
    // promenade has ONE center, so a multi-cell run states something this
    // phrasing cannot express and must stay verbatim.
    test('a multi-cell run is preserved verbatim, not collapsed', () async {
      final f = await _importTcbLine('(4) Partner star promenade 1/2 (WR;ML)');
      expect(f.move, 'star_promenade');
      expect(f.note, 'WR;ML');
      expect(f.note, isNot(contains('in the center')));
    });

    // Structuring a line must never cost information the unstructured reading
    // kept. Before v26 this line's trailing qualifier was dropped outright.
    test('an unconsumed annotation rides alongside the center note', () async {
      final f = await _importTcbLine(
        '(4) Neighbor star promenade 1/2 (WR) (hand-in-hand with neighbor)',
      );
      expect(
        f.note,
        'role2s by the right in the center; hand-in-hand with neighbor',
      );
    });

    // A line with no annotation at all must be untouched by the new
    // pre-recognizer — it has nothing to say about the center.
    test('an unannotated line gains no note', () async {
      final f = await _importTcbLine('(4) Partner star promenade 1/2');
      expect(f.move, 'star_promenade');
      expect(f.params['who'], 'partners');
      expect(f.note, isNull);
    });

    // Mutation caught: leaving `_takeSide` out of the shared recognizer after
    // dropping the param. An unconsumed token forces the whole line custom, so
    // every "star promenade right" line would silently regress from structured
    // to custom. The corpus has none of these today, but the free-text entry
    // and re-parse paths share this grammar, so a hand-typed line must still
    // structure.
    test('a prose hand still structures — and is discarded', () async {
      final f = await _importTcbLine('(4) Neighbor star promenade right 1/2');
      expect(f.move, 'star_promenade');
      expect(f.isCustom, isFalse);
      expect(f.params['who'], 'neighbors');
      expect(f.params.containsKey('hand'), isFalse);
      expect(f.params['turn'], 0.5);
    });

    // The pre-recognizer must not steal lines from the plain `promenade`
    // annotation path, whose anchor (`\bpromenades?\b`) also matches
    // "star promenade". They are separated by the resolved move id.
    test('a plain promenade annotation is unaffected', () async {
      final f = await _importTcbLine(
        '(8) Partner promenade across (single file)',
      );
      expect(f.move, 'promenade');
      expect(f.note, 'single file');
    });
  });

  // -------------------------------------------------------------------------
  // A4 — ContraDB star promenades fall to custom
  // -------------------------------------------------------------------------

  group('A4 — ContraDB star promenades decline to custom', () {
    // Mutation caught: restoring the dialect recognizer. Note that deleting it
    // is NOT sufficient on its own — the SHARED recognizer in
    // figure_parser.dart claims the line for every front-end — which is why the
    // front-end carries an explicit veto. Removing the veto reproduces the bug
    // even with the dialect recognizer gone, and this test catches that too.
    test('the HTML dialect declines the line', () {
      final f = parseFigureLine(
        'gentlespoons star promenade right 1',
        frontEnd: contraDbHtmlFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.isCustom, isTrue);
      // Nothing is lost by declining: ContraDB's own wording survives verbatim.
      expect(f.params['text'], contains('star promenade right'));
    });

    // The veto is anchored on the two-word phrase, so the unrelated
    // `promenade` move must keep structuring.
    test('a plain ContraDB promenade still structures', () {
      final f = parseFigureLine(
        'partners promenade across',
        frontEnd: contraDbHtmlFigureFrontEnd,
      );
      expect(f, isNotNull);
      expect(f!.isCustom, isFalse);
      expect(f.move, 'promenade');
    });

    // The TCB front-end must NOT inherit the veto — TCB states the pick-up
    // relationship, which is exactly what we keep.
    test('the TCB front-end is unaffected by the veto', () async {
      final f = await _importTcbLine('(4) Neighbor star promenade 1/2 (WR)');
      expect(f.isCustom, isFalse);
      expect(f.move, 'star_promenade');
    });
  });

  // -------------------------------------------------------------------------
  // A2 — the one-time retirement of stored `hand`
  // -------------------------------------------------------------------------

  group('A2 — stored star_promenade.hand is retired once', () {
    late Directory dir;
    late String dbPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sp-hand-');
      dbPath = '${dir.path}/db.sqlite';
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> seed(List<Figure> figures) async {
      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();
      await repos.dances.create(
        Dance(
          id: 'd1',
          title: 'Seeded',
          figures: figures,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      // Clear the marker so the pass runs again on the next open — the seeded
      // figures stand in for rows written by an older build.
      await db.customStatement('DELETE FROM settings WHERE key = ?', [
        starPromenadeHandRemovalDoneKey,
      ]);
      // Re-introduce the retired param the way an older build stored it: the
      // model no longer writes it, so it is injected into figures_json
      // directly. Anything else would be testing the seeding code.
      final row = await db
          .customSelect(
            'SELECT figures_json FROM dances WHERE id = ?',
            variables: [Variable.withString('d1')],
          )
          .getSingle();
      final json = row.data['figures_json'] as String;
      final decoded = jsonDecode(json) as List<Object?>;
      Object? inject(Object? entry) {
        if (entry is! Map) return entry;
        final m = Map<String, Object?>.from(entry);
        if (m['move'] == 'star_promenade') {
          m['params'] = <String, Object?>{
            ...Map<String, Object?>.from(m['params'] as Map),
            'hand': 'left',
          };
        } else if (m['move'] == 'meanwhile') {
          final p = Map<String, Object?>.from(m['params'] as Map);
          p['figures'] = [for (final s in p['figures'] as List) inject(s)];
          m['params'] = p;
        }
        return m;
      }

      await db.customStatement(
        'UPDATE dances SET figures_json = ? WHERE id = ?',
        [
          jsonEncode([for (final e in decoded) inject(e)]),
          'd1',
        ],
      );
      await db.close();
    }

    // Mutation caught: a strip that walks only top-level figures. A meanwhile
    // side is a figure too, and the v18 migration can itself create containers
    // holding one.
    test('strips the retired param, including inside a meanwhile', () async {
      await seed([
        Figure(
          move: 'star_promenade',
          params: {'who': 'neighbors', 'turn': 0.5, 'beats': 4},
        ),
        Figure.meanwhile(
          figures: [
            Figure(move: 'star_promenade', params: {'who': 'partners'}),
            Figure(move: 'orbit', params: {'who': 'ones'}),
          ],
          beats: 8,
        ),
      ]);

      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('d1'))!;
      expect(dance.figures[0].params.containsKey('hand'), isFalse);
      // Everything else about the figure survives.
      expect(dance.figures[0].params['who'], 'neighbors');
      expect(dance.figures[0].params['turn'], 0.5);

      final side = dance.figures[1].subFigures.first;
      expect(side.move, 'star_promenade');
      expect(side.params.containsKey('hand'), isFalse);
      expect(side.params['who'], 'partners');

      await db.close();
    });

    // Mutation caught: a strip keyed on the param name alone, which would
    // clear `hand` from every move that legitimately declares one.
    test('leaves another move\'s hand alone', () async {
      await seed([
        Figure(
          move: 'allemande',
          params: {'who': 'neighbors', 'hand': 'left', 'turn': 1.0},
        ),
        Figure(move: 'star_promenade', params: {'who': 'partners'}),
      ]);

      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final dance = (await repos.dances.getById('d1'))!;
      expect(dance.figures[0].move, 'allemande');
      expect(dance.figures[0].params['hand'], 'left');
      expect(dance.figures[1].params.containsKey('hand'), isFalse);

      await db.close();
    });

    // Mutation caught: writing the marker before the pass, or not writing it at
    // all (the pass would then re-run every launch, rebuilding the whole
    // derived index each time).
    test('the marker is written, so the pass runs at most once', () async {
      await seed([
        Figure(move: 'star_promenade', params: {'who': 'partners'}),
      ]);

      final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
      final repos = CompendiumRepositories(db, contraTaxonomy);
      await repos.ensureMigrated();

      final marker = await db
          .customSelect(
            'SELECT 1 FROM settings WHERE key = ?',
            variables: [Variable.withString(starPromenadeHandRemovalDoneKey)],
          )
          .get();
      expect(marker, isNotEmpty);

      await db.close();
    });

    // The derived index must be REBUILT, not merely left correct.
    //
    // The obvious version of this test cannot fail: `seed()` writes the dance
    // through the current (v26) repository, so its `dance_figures` row is
    // already right, and the `hand` injected afterwards is inert — asserting on
    // that row passes whether or not a rebuild ever runs. Verified by mutation:
    // deleting the `runDerivedRebuild` call left the obvious test green.
    //
    // So the stale row is written EXPLICITLY, exactly as a pre-v26 build would
    // have left it, and the assertion is that the pass corrects it. That is the
    // failure mode the (false) "the version bump triggers a rebuild" note in
    // the v25 doc block would have produced: a canonical-key change shipping
    // with a permanently stale FTS/dedupe index.
    test(
      'the derived canonical text is REBUILT, not just left correct',
      () async {
        await seed([
          Figure(
            move: 'star_promenade',
            params: {'who': 'neighbors', 'turn': 0.5, 'beats': 4},
          ),
        ]);

        final db = CompendiumDatabase(NativeDatabase(File(dbPath)));
        await db.customStatement(
          'UPDATE dance_figures SET canonical_text = ? WHERE dance_id = ?',
          ['neighbors star promenade right ½', 'd1'],
        );
        // Guard the guard: if this row is not actually stale going in, the
        // assertion below proves nothing.
        final before = await db
            .customSelect(
              'SELECT canonical_text FROM dance_figures WHERE dance_id = ?',
              variables: [Variable.withString('d1')],
            )
            .getSingle();
        expect(before.data['canonical_text'], contains('right'));

        final repos = CompendiumRepositories(db, contraTaxonomy);
        await repos.ensureMigrated();

        final rows = await db
            .customSelect(
              'SELECT canonical_text FROM dance_figures WHERE dance_id = ?',
              variables: [Variable.withString('d1')],
            )
            .get();
        expect(rows, hasLength(1));
        final canonical = rows.single.data['canonical_text'] as String;
        expect(canonical, 'neighbors star promenade ½');
        expect(canonical, isNot(contains('right')));
        expect(canonical, isNot(contains('left')));

        await db.close();
      },
    );
  });
}
