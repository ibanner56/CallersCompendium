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
      expect(draft.dance.callingNotes, contains('By: Dan Pearl'));
      expect(draft.dance.callingNotes, contains('Imported from ContraDB.'));
    });

    test('leaves authorIds empty and surfaces an info issue', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      expect(draft.dance.authorIds, isEmpty);
      expect(
        draft.issues.any((i) => i.code == 'contradb_html_author_unresolved'),
        isTrue,
      );
    });

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

    test('a missing choreographer omits the By: note', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">No Author</h1>'
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">circle left</div></td></tr></table>',
        ),
      );
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
    test('parses every row as a custom figure with beats + label', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      final figures = draft.dance.figures;
      expect(figures, hasLength(6));
      expect(figures.every((f) => f.isCustom), isTrue);
      expect(_text(figures[0]), 'A1: neighbors balance & swing');
      expect(_beats(figures[0]), 16);
      // HTML entity decoded (&amp; -> &).
      expect(_text(figures[3]), 'B1: partners balance & swing');
    });

    test('carries the section label forward onto continuation rows', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      final figures = draft.dance.figures;
      // Row 3 (index 2) has an empty <td> label; it continues A2.
      expect(_text(figures[2]), startsWith('A2: '));
      // Row 6 (index 5) has an empty <td> label; it continues B2.
      expect(_text(figures[5]), startsWith('B2: '));
    });

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
      expect(_text(figures[5]).trim(), 'B2: slide left along set');
      // A row with no marker is not flagged.
      expect(figures[0].progression, isFalse);
    });

    test('scrubs gendered role terms through the canonical dialect', () async {
      final draft = await _importOne(_page(_rendezvousBody));
      // "ladles" -> "role2s" (Row 3 continuation).
      expect(_text(draft.dance.figures[2]), contains('role2s do si do'));
    });

    test('applies the gypsy -> shoulder round safety net', () async {
      final draft = await _importOne(
        _page(
          '<h1 class="dance-show-title">G</h1>'
          '<table class="contra-table-nonfluid">'
          '<tr><td>A1</td><td class=dance-show-beats>8</td>'
          '<td><div class="show-figure">gypsy your neighbor</div></td>'
          '</tr></table>',
        ),
      );
      expect(
        _text(draft.dance.figures.single),
        'A1: shoulder round your neighbor',
      );
    });

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
      // Only the one well-formed, non-blank figure survives.
      expect(draft.dance.figures, hasLength(1));
      expect(_text(draft.dance.figures.single), 'A2: circle left');
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
