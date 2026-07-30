import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Fixtures + tests for [ContraDbHtmlAdapter].
///
/// All fixtures are **synthetic**, hand-built to the confirmed live DOM of
/// `contradb.com/dances/1` (see the adapter doc comment): `h1.dance-show-title`,
/// `p.dance-show-choreographer`, `p.dance-show-formation`, and the
/// `table.contra-table-nonfluid` figures table with `td.dance-show-beats` +
/// `div.show-figure` cells, empty-section continuation rows, and `<u>` / `⁋`
/// progression markers. No live network is used.

/// Wraps a dance body in the minimal page chrome ContraDB serves.
String _page(String body) =>
    '<!DOCTYPE html><html><head><title>x</title></head>'
    '<body class="dances-show-body">$body</body></html>';

/// The happy-path fixture modeled verbatim on dance 1 ("The Rendezvous").
const String _rendezvousBody = '''
<h1 class="dance-show-title">The Rendezvous</h1>
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Adina Gordon</a></strong></p>
<p class="dance-show-formation">formation: improper </p>
<table class="table table-bordered table-condensed contra-table-nonfluid">
  <tr class="a1b1 dance-show-long-figure">
    <td>A1</td>
    <td class=dance-show-beats>16</td>
    <td><div class="show-figure">neighbors balance &amp; swing</div></td>
  </tr>
  <tr class="a2b2 ">
    <td>A2</td>
    <td class=dance-show-beats>8</td>
    <td><div class="show-figure">long lines forward &amp; back</div></td>
  </tr>
  <tr class="a2b2 ">
    <td></td>
    <td class=dance-show-beats>8</td>
    <td><div class="show-figure">ladles do si do 1½ or <u>swing</u> to partner</div></td>
  </tr>
  <tr class="a1b1 dance-show-long-figure">
    <td>B1</td>
    <td class=dance-show-beats>16</td>
    <td><div class="show-figure">partners balance &amp; swing</div></td>
  </tr>
  <tr class="a2b2 ">
    <td>B2</td>
    <td class=dance-show-beats>8</td>
    <td><div class="show-figure">circle left 4 places</div></td>
  </tr>
  <tr class="a2b2 ">
    <td></td>
    <td class=dance-show-beats>2</td>
    <td><div class="show-figure">slide left along set ⁋</div></td>
  </tr>
</table>
''';

/// The two Rory O'More rows from the repro dance
/// (https://contradb.com/dances/2254), captured verbatim — including ContraDB's
/// rendered `balance & ` prefix and the trailing parenthetical note. Regression
/// fixture for #578: these used to demote to custom because the `&` was left
/// behind after `balance`.
const String _rory2254Body = '''
<h1 class="dance-show-title">Repro 2254</h1>
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/88">Isaac Banner</a></strong></p>
<p class="dance-show-formation">formation: improper </p>
<table class="table table-bordered table-condensed contra-table-nonfluid">
  <tr class="a1b1 ">
    <td>A1</td>
    <td class=dance-show-beats>8</td>
    <td><div class="show-figure">balance &amp;  Rory O'More right (in long waves)</div></td>
  </tr>
  <tr class="a1b1 ">
    <td></td>
    <td class=dance-show-beats>8</td>
    <td><div class="show-figure">balance &amp;  Rory O'More left (in long waves)</div></td>
  </tr>
</table>
''';

Future<StructuredDraft> _importOne(String payload, {String? uri}) async {  final adapter = ContraDbHtmlAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: payload, uri: uri),
  );
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

int _beats(Figure f) => (f.params['beats'] as int?) ?? 0;

/// Builds a ContraDB dance page from `(beats, figureHtml)` rows for the
/// end-to-end corpus tests.
String _dancePage(String title, List<(int, String)> rows) {
  final trs = rows
      .map(
        (r) =>
            '<tr><td>A1</td><td class=dance-show-beats>${r.$1}</td>'
            '<td><div class="show-figure">${r.$2}</div></td></tr>',
      )
      .join();
  return _page(
    '<h1 class="dance-show-title">$title</h1>'
    '<table class="contra-table-nonfluid">$trs</table>',
  );
}

void main() {
  group('discover', () {
    test('emits one record and derives the id from the URL', () async {
      final adapter = ContraDbHtmlAdapter();
      final records = await adapter.discover(
        ImportRequest(
          payload: _page(_rendezvousBody),
          uri: 'https://contradb.com/dances/1',
        ),
      );
      expect(records, hasLength(1));
      expect(records.single.source, ProvenanceSource.contradb);
      expect(records.single.externalId, '1');
      expect(records.single.label, 'The Rendezvous');
    });

    test('falls back to a name-based id when the URL has none', () async {
      final adapter = ContraDbHtmlAdapter();
      final records = await adapter.discover(
        ImportRequest(payload: _page(_rendezvousBody)),
      );
      expect(records.single.externalId, 'name:the rendezvous');
    });

    test('throws on empty payload', () {
      final adapter = ContraDbHtmlAdapter();
      expect(
        () => adapter.discover(const ImportRequest(payload: '   ')),
        throwsA(isA<ImportError>()),
      );
    });

    test('throws when the page is not a ContraDB dance page', () {
      final adapter = ContraDbHtmlAdapter();
      expect(
        () => adapter.discover(
          ImportRequest(payload: _page('<p>some other page</p>')),
        ),
        throwsA(isA<ImportError>()),
      );
    });
  });

  group('fetch', () {
    test('wraps the page as an HTML RawRecord', () async {
      final adapter = ContraDbHtmlAdapter();
      final records = await adapter.discover(
        ImportRequest(
          payload: _page(_rendezvousBody),
          uri: 'https://contradb.com/dances/1',
        ),
      );
      final raw = await adapter.fetch(records.single);
      expect(raw.source, ProvenanceSource.contradb);
      expect(raw.externalId, '1');
      expect(raw.contentType, 'text/html');
      expect(raw.sourceVersion, 'contradb-html');
      expect(raw.payload, contains('dance-show-title'));
    });
  });

  group('parse — metadata', () {
    test('reads title, formation, and choreographer', () async {
      final draft = await _importOne(
        _page(_rendezvousBody),
        uri: 'https://contradb.com/dances/1',
      );
      expect(draft.dance.title, 'The Rendezvous');
      expect(draft.dance.formation.shape, FormationShape.dupleImproper);
      expect(draft.dance.formation.detail, 'improper');
      expect(draft.dance.callingNotes, isNot(contains('Adina Gordon')));
      expect(draft.dance.callingNotes, contains('Imported from ContraDB.'));
    });

    test(
      'sanitizes control/bidi chars in title, choreographer, formation (#444)',
      () async {
        final draft = await _importOne(
          _page(
            '<h1 class="dance-show-title">Petro\u202Enella\u0007</h1>'
            '<p class="dance-show-choreographer">by: '
            '<strong><a href="/choreographers/9">Adina\u200B Gordon</a></strong></p>'
            '<p class="dance-show-formation">formation: impro\u202Eper</p>',
          ),
          uri: 'https://contradb.com/dances/1',
        );
        // Stored title/author/formation are stripped of the spoofing characters.
        expect(draft.dance.title, 'Petronella');
        expect(draft.authorNames, ['Adina Gordon']);
        expect(draft.dance.formation.detail, 'improper');
        expect(containsDisallowedText(draft.dance.title), isFalse);
      },
    );

    test('discover label is sanitized (#444)', () async {
      final adapter = ContraDbHtmlAdapter();
      final records = await adapter.discover(
        ImportRequest(
          payload: _page('<h1 class="dance-show-title">Ti\u202Etle\u0000</h1>'),
        ),
      );
      expect(records.single.label, 'Title');
      // The derived external id is built from the already-clean title.
      expect(records.single.externalId, 'name:title');
    });

    test(
      'title with an embedded newline is single-line → stable externalId (#444)',
      () async {
        final adapter = ContraDbHtmlAdapter();
        // <h1> spanning two source lines yields an embedded newline in the
        // extracted text; a single-line title must strip it so the derived
        // `name:<title>` external id is stable (not `name:foo\nbar`).
        final records = await adapter.discover(
          ImportRequest(
            payload: _page('<h1 class="dance-show-title">Foo\nBar</h1>'),
          ),
        );
        expect(records.single.label, 'FooBar');
        expect(records.single.externalId, 'name:foobar');
        expect(records.single.externalId, isNot(contains('\n')));

        final draft = await _importOne(
          _page('<h1 class="dance-show-title">Foo\nBar</h1>'),
        );
        expect(draft.dance.title, 'FooBar');
        expect(draft.dance.title, isNot(contains('\n')));
      },
    );

    test(
      'choreographer → authorNames; empty authorIds; no info issue',
      () async {
        final draft = await _importOne(_page(_rendezvousBody));
        expect(draft.dance.authorIds, isEmpty);
        expect(draft.authorNames, ['Adina Gordon']);
        expect(
          draft.issues.any((i) => i.code == 'contradb_html_author_unresolved'),
          isFalse,
        );
      },
    );

    test('an unknown formation falls back to other + a warning', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">Weird</h1>'
          '<p class="dance-show-formation">formation: spiral galaxy</p>',
        ),
      );
      expect(draft.dance.formation.shape, FormationShape.other);
      expect(draft.dance.formation.detail, 'spiral galaxy');
      expect(
        draft.issues.any(
          (i) => i.code == 'contradb_html_formation_unclassified',
        ),
        isTrue,
      );
    });

    test('a becket formation classifies to becketCw', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">B</h1>'
          '<p class="dance-show-formation">formation: Becket</p>',
        ),
      );
      expect(draft.dance.formation.shape, FormationShape.becketCw);
    });

    test('a missing choreographer yields empty authorNames', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">No Author</h1>'
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">circle left</div></td></tr></table>',
        ),
      );
      expect(draft.authorNames, isEmpty);
      expect(draft.dance.callingNotes, isNot(contains('By:')));
      expect(
        draft.issues.any((i) => i.code == 'contradb_html_author_unresolved'),
        isFalse,
      );
    });

    test('a missing title uses a placeholder stub + warning', () async {
      final draft = await _importOne(
        _page(
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">circle left</div></td></tr></table>',
        ),
        uri: 'https://contradb.com/dances/99',
      );
      expect(draft.dance.title, 'ContraDB dance 99');
      expect(
        draft.issues.any((i) => i.code == 'contradb_html_missing_title'),
        isTrue,
      );
    });
  });

  group('parse — figures', () {
    test(
      'recognised rows structure; the rest stay custom with beats',
      () async {
        final draft = await _importOne(_page(_rendezvousBody));
        final figures = draft.dance.figures;
        expect(figures, hasLength(6));
        // "neighbors balance & swing" → structured swing (balance prefix).
        expect(figures[0].move, 'swing');
        expect(figures[0].params['who'], 'neighbors');
        expect(figures[0].params['prefix'], 'balance');
        expect(_beats(figures[0]), 16);
        // "partners balance & swing" likewise structures.
        expect(figures[3].move, 'swing');
        expect(figures[3].params['who'], 'partners');
        expect(figures[3].params['prefix'], 'balance');
      },
    );

    test('captures <u> and ⁋ progression markers on the figure', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      final figures = draft.dance.figures;
      // Row 3: "… or <u>swing</u> to partner" — progression flag set, tag
      // unwrapped. The do si do now structures, with the trailing alternative
      // preserved verbatim as its note.
      expect(figures[2].progression, isTrue);
      expect(figures[2].move, 'do_si_do');
      expect(figures[2].note, contains('swing to partner'));
      // Row 6: trailing "⁋" — progression flag set, marker stripped; the figure
      // structures as a slide along set.
      expect(figures[5].progression, isTrue);
      expect(figures[5].move, 'slide_along_set');
      expect(figures[5].params['slide'], 'left');
      // A row with no marker is not flagged.
      expect(figures[0].progression, isFalse);
    });

    test('scrubs gendered role terms through the canonical dialect', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      // "ladles" -> "role2s" (Row 3 continuation), carried onto the structured
      // do si do's subject.
      expect(draft.dance.figures[2].move, 'do_si_do');
      expect(draft.dance.figures[2].params['who'], 'role2s');
    });

    test(
      'repro dance 2254: "balance & Rory O\'More … (in long waves)" '
      'structures with the paren note (#578)',
      () async {
        final draft = await _importOne(_page(_rory2254Body));
        final figures = draft.dance.figures;
        expect(figures, hasLength(2));
        for (final f in figures) {
          expect(f.isCustom, isFalse, reason: 'should not fall through to custom');
          expect(f.move, 'rory_o_more');
          expect(f.params['balance'], isTrue);
          expect(f.note, '(in long waves)');
        }
        expect(figures[0].params['slide'], 'right');
        expect(figures[1].params['slide'], 'left');
      },
    );

    test(
      'splits "form an ocean wave & balance" into wave + a balance',
      () async {
        final draft = await _importOne(
          _page(
            '<h1 class="dance-show-title">OW</h1>'
            '<table class="contra-table-nonfluid">'
            '<tr><td>A1</td><td class=dance-show-beats>4</td>'
            '<td><div class="show-figure">form an ocean wave &amp; balance - '
            'ladles by right hands and neighbors by left hands</div></td>'
            '</tr></table>',
          ),
        );
        final figs = draft.dance.figures;
        expect(figs, hasLength(2));
        expect(figs[0].move, 'form_a_short_wave');
        expect(figs[0].params['center'], 'role2s');
        expect(figs[0].params['sides'], 'neighbors');
        expect(figs[0].params['beats'], 0); // 4 total − 4 balance = formation
        expect(figs[0].params.containsKey('balance'), isFalse);
        expect(figs[1].move, 'balance');
        expect(figs[1].params['who'], 'everyone');
        expect(figs[1].params['beats'], 4);
      },
    );

    test('a plain "form an ocean wave" stays a single figure', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">OW</h1>'
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td><td class=dance-show-beats>4</td>'
          '<td><div class="show-figure">form an ocean wave - '
          'ladles by right hands and neighbors by left hands</div></td>'
          '</tr></table>',
        ),
      );
      expect(draft.dance.figures, hasLength(1));
      expect(draft.dance.figures.single.move, 'form_a_short_wave');
    });

    test(
      'applies the gypsy -> shoulder round safety net before parsing',
      () async {
        final draft = await _importOne(
          _page(
            '<h1 class="dance-show-title">G</h1>'
            '<table class="contra-table-nonfluid">'
            '<tr><td>A1</td><td class=dance-show-beats>8</td>'
            '<td><div class="show-figure">gypsy your neighbor</div></td>'
            '</tr></table>',
          ),
        );
        // "gypsy" is scrubbed to "shoulder round", which the parser then
        // recognises as a structured shoulder_round with the neighbor role.
        final fig = draft.dance.figures.single;
        expect(fig.move, 'shoulder_round');
        expect(fig.params['who'], 'neighbors');
      },
    );

    test('non-numeric beats fall back to 0 with an info issue', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">NB</h1>'
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td><td class=dance-show-beats>lots</td>'
          '<td><div class="show-figure">balance</div></td></tr></table>',
        ),
      );
      expect(_beats(draft.dance.figures.single), 0);
      expect(
        draft.issues.any((i) => i.code == 'contradb_html_beats_unreadable'),
        isTrue,
      );
    });
  });

  group('parse — parse-never-fails', () {
    test('a page with no figures table imports as a metadata stub', () async {
      final draft = await _importOne(
        _page('<h1 class="dance-show-title">Stub Dance</h1>'),
      );
      expect(draft.dance.title, 'Stub Dance');
      expect(draft.dance.figures, isEmpty);
      expect(
        draft.issues.any((i) => i.code == 'contradb_html_no_figures_table'),
        isTrue,
      );
    });

    test('malformed rows are skipped, others still import', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">Messy</h1>'
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td></tr>' // no beats/figure cell
          '<tr><td>A2</td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">circle left</div></td></tr>'
          '<tr><td></td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">   </div></td></tr>' // blank figure
          '</table>',
        ),
      );
      // Only the one well-formed, non-blank figure survives; "circle left" is
      // a recognised move → structured (the label/beats live on the figure).
      expect(draft.dance.figures, hasLength(1));
      expect(draft.dance.figures.single.move, 'circle');
      expect(draft.dance.figures.single.params['turn'], 'left');
    });

    test('parse throws only when the payload is not a dance page', () {
      final adapter = ContraDbHtmlAdapter();
      final raw = RawRecord(
        source: ProvenanceSource.contradb,
        payload: _page('<p>not a dance</p>'),
        contentType: 'text/html',
      );
      expect(() => adapter.parse(raw), throwsA(isA<ImportError>()));
    });
  });

  group('parse — corpus regression (real ContraDB renders)', () {
    test('Butter (dances/94) structures every figure', () async {
      final draft = await _importOne(
        _dancePage('Butter', const [
          (2, 'slide left along set \u204B'),
          (6, 'circle left 3 places'),
          (8, 'neighbors swing'),
          (8, 'long lines forward &amp; back'),
          (8, 'ladles chain'),
          (16, 'ladles start a full hey - rights in center, lefts on ends'),
          (16, 'partners balance &amp; swing'),
        ]),
      );
      final f = draft.dance.figures;
      expect(f, hasLength(7));
      expect(
        f.every((g) => !g.isCustom),
        isTrue,
        reason: '${f.map((g) => g.move)}',
      );

      expect(f[0].move, 'slide_along_set');
      expect(f[0].params['slide'], 'left');
      expect(f[0].progression, isTrue);
      expect(f[1].move, 'circle');
      expect(f[1].params['places'], 3);
      expect(f[2].move, 'swing');
      expect(f[2].params['who'], 'neighbors');
      expect(f[3].move, 'long_lines');
      expect(f[3].params['goBack'], isTrue);
      expect(f[4].move, 'chain');
      expect(f[4].params['who'], 'role2s');
      expect(f[5].move, 'hey');
      expect(f[5].params['pass1'], 'role2s');
      expect(f[5].params['length'], 'full');
      expect(f[5].params['shoulder'], 'right');
      expect(f[6].move, 'swing');
      expect(f[6].params['who'], 'partners');
      expect(f[6].params['prefix'], 'balance');
    });

    test('dances/81 structures every figure incl. the ocean-wave split', () async {
      final draft = await _importOne(
        _dancePage('Dance 81', const [
          (6, 'gentlespoons allemande left once'),
          (10, 'neighbors swing'),
          (8, 'circle left 3 places'),
          (8, 'partners swing'),
          (8, 'long lines forward &amp; back'),
          (8, 'ladles allemande right 1\u00BD - don\'t let go'),
          (
            4,
            'form an ocean wave &amp; balance - ladles by right hands and neighbors by left hands',
          ),
          (4, 'neighbors allemande left \u00BE to long wavy lines'),
          (0, 'form long waves - ladles face in, gentlespoons face out \u204B'),
          (4, 'balance'),
          (4, 'next neighbors allemande right \u00BE'),
        ]),
      );
      final f = draft.dance.figures;
      // 11 rows, but the ocean-wave-&-balance row splits into two figures.
      expect(f, hasLength(12));
      expect(
        f.every((g) => !g.isCustom),
        isTrue,
        reason: '${f.map((g) => g.move)}',
      );

      expect(f[0].move, 'allemande');
      expect(f[0].params['hand'], 'left');
      expect(f[0].params['turn'], 1.0);
      expect(f[5].move, 'allemande');
      expect(f[5].params['turn'], 1.5);
      expect(f[5].note, "- don't let go");
      // Ocean-wave split: wave (formation, 0 beats) then a standalone balance.
      expect(f[6].move, 'form_a_short_wave');
      expect(f[6].params['center'], 'role2s');
      expect(_beats(f[6]), 0);
      expect(f[7].move, 'balance');
      expect(f[7].params['who'], 'everyone');
      expect(_beats(f[7]), 4);
      expect(f[8].move, 'allemande');
      expect(f[8].note, 'to long wavy lines');
      expect(f[9].move, 'form_long_waves');
      expect(f[9].params['who'], 'role2s');
      expect(f[9].progression, isTrue);
      expect(f[10].move, 'balance');
      expect(f[11].move, 'allemande');
      expect(f[11].params['who'], 'nextNeighbors');
    });
  });
}
