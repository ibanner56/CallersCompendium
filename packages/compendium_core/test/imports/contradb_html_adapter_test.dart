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
<p class="dance-show-choreographer">by: <strong><a href="/choreographers/4">Dan Pearl</a></strong></p>
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

Future<StructuredDraft> _importOne(String payload, {String? uri}) async {
  final adapter = ContraDbHtmlAdapter();
  final discovered = await adapter.discover(
    ImportRequest(payload: payload, uri: uri),
  );
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

/// The custom-figure text ([customFigure] stores it in `params['text']`).
String _text(Figure f) => f.params['text'] as String;

int _beats(Figure f) => (f.params['beats'] as int?) ?? 0;

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
      expect(draft.dance.callingNotes, isNot(contains('Dan Pearl')));
      expect(draft.dance.callingNotes, contains('Imported from ContraDB.'));
    });

    test(
      'sanitizes control/bidi chars in title, choreographer, formation (#444)',
      () async {
        final draft = await _importOne(
          _page(
            '<h1 class="dance-show-title">Petro\u202Enella\u0007</h1>'
            '<p class="dance-show-choreographer">by: '
            '<strong><a href="/choreographers/9">Dan\u200B Pearl</a></strong></p>'
            '<p class="dance-show-formation">formation: impro\u202Eper</p>',
          ),
          uri: 'https://contradb.com/dances/1',
        );
        // Stored title/author/formation are stripped of the spoofing characters.
        expect(draft.dance.title, 'Petronella');
        expect(draft.authorNames, ['Dan Pearl']);
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
      'choreographer → authorNames; empty authorIds; no info issue',
      () async {
        final draft = await _importOne(_page(_rendezvousBody));
        expect(draft.dance.authorIds, isEmpty);
        expect(draft.authorNames, ['Dan Pearl']);
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
      // Row 3: "<u>swing</u>" — progression flag set, tag unwrapped to text.
      expect(figures[2].progression, isTrue);
      expect(_text(figures[2]), contains('swing to partner'));
      expect(_text(figures[2]), isNot(contains('<u>')));
      // Row 6: trailing "⁋" — progression flag set, marker stripped.
      expect(figures[5].progression, isTrue);
      expect(_text(figures[5]), isNot(contains('⁋')));
      expect(_text(figures[5]).trim(), 'slide left along set');
      // A row with no marker is not flagged.
      expect(figures[0].progression, isFalse);
    });

    test('scrubs gendered role terms through the canonical dialect', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      // "ladles" -> "role2s" (Row 3 continuation).
      expect(_text(draft.dance.figures[2]), contains('role2s do si do'));
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
}
