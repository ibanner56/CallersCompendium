import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Fixtures + tests for [parseCallersBoxSearchResults].
///
/// The happy-path fixture is trimmed **verbatim** from the live Caller's Box
/// search results page (mirrored code at
/// `ibiblio.org/contradance/thecallersbox/?title=Money+Musk`, captured
/// 2026-07-16): a bare `<table>` whose result `<tr>`s carry three leading icon
/// `<td>`s (`&#x24bb;`/`&#x24c1;`/`&#x24cb;`, any of which may be empty), then a
/// `<td><a href='dance.php?id=N' target='_blank'>NAME</a></td>`, then author and
/// formation cells. No live network is used.

/// The results `<table>` for a `?title=Money+Musk` query (subset of the 9 rows,
/// preserving the empty-icon-cell and non-`Traditional` author variety).
const String _moneyMuskResults = '''
<p>Of 16874 dances in the db, your query matches 9.</p>
<table>
<tr>
<td><span style='color: green'>&#x24bb;</span></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td><span style='color: green'>&#x24cb;</span></td>
<td><a href='dance.php?id=10600' target='_blank'>Money Musk</a></td>
<td>Traditional</td>
<td>Triple Minor</td>
</tr>
<tr>
<td><span style='color: green'>&#x24bb;</span></td>
<td></td>
<td></td>
<td><a href='dance.php?id=3913' target='_blank'>Money Musk {variant}</a></td>
<td>Traditional</td>
<td>Triple Minor</td>
</tr>
<tr>
<td></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td></td>
<td><a href='dance.php?id=3326' target='_blank'>Money Musk Triplet</a></td>
<td>Walter Lenk</td>
<td>Triplet</td>
</tr>
</table>
<hr>
<p>Modify your query: (or <a href='.'>clear the form</a>)</p>
<form method='GET'>
Title contains: <input name='title' value='Money Musk'>
</form>
''';

void main() {
  group('parseCallersBoxSearchResults', () {
    test('extracts id / name / author / formation for each result row', () {
      final results = parseCallersBoxSearchResults(_moneyMuskResults);
      expect(results, hasLength(3));

      expect(
        results[0],
        const CallersBoxSearchResult(
          id: '10600',
          name: 'Money Musk',
          author: 'Traditional',
          formation: 'Triple Minor',
          figuresAvailable: true,
        ),
      );
      expect(
        results[1],
        const CallersBoxSearchResult(
          id: '3913',
          name: 'Money Musk {variant}',
          author: 'Traditional',
          formation: 'Triple Minor',
          figuresAvailable: true,
        ),
      );
      expect(
        results[2],
        const CallersBoxSearchResult(
          id: '3326',
          name: 'Money Musk Triplet',
          author: 'Walter Lenk',
          formation: 'Triplet',
          // Ⓛ only, no Ⓕ: TCB knows an external source for the figures but
          // will not serve them itself (issue #845).
          figuresAvailable: false,
        ),
      );
    });

    test('preserves document order', () {
      final ids = parseCallersBoxSearchResults(
        _moneyMuskResults,
      ).map((r) => r.id).toList();
      expect(ids, ['10600', '3913', '3326']);
    });

    test('ignores the "clear the form" link (not a dance.php link)', () {
      // The modify-query form contains an <a href='.'> that must not be parsed
      // as a result; only dance.php?id=N anchors count.
      final results = parseCallersBoxSearchResults(_moneyMuskResults);
      expect(results.every((r) => r.id.isNotEmpty), isTrue);
      expect(results.map((r) => r.name), isNot(contains('clear the form')));
    });

    test('decodes HTML entities in the dance name', () {
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=42'>Salmon &amp; Chips {A1 &lt;fast&gt;}</a></td>
<td>Jane &amp; Joe</td>
<td>Duple Minor</td>
</tr></table>''';
      final results = parseCallersBoxSearchResults(html);
      expect(results, hasLength(1));
      expect(results.single.name, 'Salmon & Chips {A1 <fast>}');
      expect(results.single.author, 'Jane & Joe');
    });

    test('collapses internal whitespace / newlines in cell text', () {
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=7'>Money
   Musk</a></td>
<td>  Traditional  </td>
<td>Triple   Minor</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.name, 'Money Musk');
      expect(r.author, 'Traditional');
      expect(r.formation, 'Triple Minor');
    });

    test('tolerates a differing number of leading icon cells', () {
      // No icon cells at all: link is the first cell.
      const html = '''
<table><tr>
<td><a href='dance.php?id=9'>No Icons</a></td>
<td>Somebody</td>
<td>Becket</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.id, '9');
      expect(r.author, 'Somebody');
      expect(r.formation, 'Becket');
    });

    test('missing author / formation cells default to empty strings', () {
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=11'>Lonely Link</a></td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.author, isEmpty);
      expect(r.formation, isEmpty);
    });

    test('a page with no dance links yields an empty list (zero results)', () {
      const html = '''
<p>Of 16874 dances in the db, your query matches 0.</p>
<hr>
<form method='GET'><input name='title' value='zzzznope'></form>''';
      expect(parseCallersBoxSearchResults(html), isEmpty);
    });

    test('empty / whitespace input yields an empty list', () {
      expect(parseCallersBoxSearchResults(''), isEmpty);
      expect(parseCallersBoxSearchResults('   '), isEmpty);
    });

    test('a full search page (with head/meta chrome) parses its rows', () {
      final html =
          "<html><head><meta charset='windows-1252'><title>The Caller's Box"
          '</title></head><body><h1>Search</h1>$_moneyMuskResults</body></html>';
      expect(parseCallersBoxSearchResults(html), hasLength(3));
    });
  });

  // Issue #845. TCB's results page publishes three independent leading icon
  // columns, whose legend (verbatim from the live page, 2026-08-06) is:
  //
  //   &#x24bb; = we have permission to show the dance's figures
  //   &#x24c1; = we have a link to a source for the dance's figures
  //   &#x24cb; = we have one or more links to videos of the dance
  //
  // Only Ⓕ (U+24BB) means TCB will serve the figures. Ⓛ (U+24C1) merely says an
  // external source is known, so an Ⓛ-only row still imports as a figureless
  // stub — verified live against the JSON endpoint: id 5419 ("Cabin Contra")
  // carries Ⓛ but not Ⓕ and reports `Permission: search` with zero phrases,
  // while id 12037 carries Ⓕ and reports `Permission: full` with four.
  //
  // Every assertion below is unconditional: none is nested inside a guard that
  // could go false and skip the check it exists to make.
  group('parseCallersBoxSearchResults — figures-permission marker (#845)', () {
    // The decoded codepoints. The source bytes are windows-1252, which cannot
    // encode any of these, so TCB has no choice but to emit them as entities —
    // and `html_parser` decodes them before the parser ever sees them.
    const markerFigures = '\u24bb'; // Ⓕ
    const markerSourceLink = '\u24c1'; // Ⓛ
    const markerVideo = '\u24cb'; // Ⓥ

    test('a row carrying Ⓕ is marked as having figures', () {
      const html = '''
<table><tr>
<td><span style='color: green'>&#x24bb;</span></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td></td>
<td><a href='dance.php?id=18906'>42 minutes of Puffin Pablo</a></td>
<td>Moose Flores</td><td>Duple Minor - Becket</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.id, '18906');
      expect(r.figuresAvailable, isTrue);
    });

    test('an absent marker is an EMPTY cell, not a missing cell', () {
      // Trimmed verbatim from the live `?title=moon` page (2026-08-06): the
      // figures cell is present and empty rather than omitted, so a parser that
      // treats "fewer cells" as the absence signal would never fire.
      const html = '''
<table><tr>
<td></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td></td>
<td><a href='dance.php?id=5419' target='_blank'>Cabin Contra</a></td>
<td>Bob Howell</td><td>Triple Minor</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.id, '5419');
      expect(r.figuresAvailable, isFalse);
    });

    test('a row with Ⓛ and Ⓥ but no Ⓕ has NO figures', () {
      // Catches "any green icon means figures" and any codepoint-RANGE match:
      // U+24C1 and U+24CB both sit in the same enclosed-alphanumerics block as
      // U+24BB, so only an exact-codepoint test distinguishes them.
      const html = '''
<table><tr>
<td></td>
<td><span style='color: green'>&#x24c1;</span></td>
<td><span style='color: green'>&#x24cb;</span></td>
<td><a href='dance.php?id=2191'>Circling the Moon</a></td>
<td>Somebody</td><td>Becket</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.figuresAvailable, isFalse);
    });

    test('the marker is found at any leading-icon-cell count', () {
      // The parser documents tolerance for a differing number of leading icon
      // cells, so the marker must be SCANNED for rather than read at a fixed
      // index. Four counts, each asserted unconditionally.
      String row(String icons, String id) =>
          '<table><tr>$icons<td><a href="dance.php?id=$id">D</a></td>'
          '<td>A</td><td>F</td></tr></table>';

      expect(
        parseCallersBoxSearchResults(
          row('<td>$markerFigures</td>', '1'),
        ).single.figuresAvailable,
        isTrue,
      );
      expect(
        parseCallersBoxSearchResults(
          row('<td></td><td>$markerFigures</td>', '2'),
        ).single.figuresAvailable,
        isTrue,
      );
      expect(
        parseCallersBoxSearchResults(
          row('<td></td><td></td><td>$markerFigures</td>', '3'),
        ).single.figuresAvailable,
        isTrue,
      );
      // No icon cells at all: nothing to scan, so nothing claims figures.
      expect(
        parseCallersBoxSearchResults(row('', '4')).single.figuresAvailable,
        isFalse,
      );
    });

    test('an entity that never decodes is not matched as literal text', () {
      // `&#x24bb` (no semicolon, inside an attribute-free text node) and the
      // bare strings "24bb" / "&#x24bb;" must not be mistaken for the marker.
      // This is what makes a raw-HTML substring match wrong: it would fire here.
      const html = '''
<table><tr>
<td>24bb</td><td>&amp;#x24bb;</td><td></td>
<td><a href='dance.php?id=5'>Not Really Permitted</a></td>
<td>A</td><td>F</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.figuresAvailable, isFalse);
    });

    test('a dance whose TITLE contains Ⓕ cannot spoof the marker', () {
      // The realistic spoof. TCB stores author-submitted titles and must
      // entity-encode any non-windows-1252 character, so a title containing Ⓕ
      // arrives decoded and indistinguishable from a real marker — unless
      // detection is scoped to the cells BEFORE the dance link.
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=3'>$markerFigures Sneaky Contra</a></td>
<td>A</td><td>F</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.name, '$markerFigures Sneaky Contra');
      expect(r.figuresAvailable, isFalse);
    });

    test('an Ⓕ in the author or formation cell cannot spoof the marker', () {
      // Both cells FOLLOW the link, so a whole-row text scan would fire.
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=6'>Plain Contra</a></td>
<td>$markerFigures</td><td>$markerVideo$markerSourceLink</td>
</tr></table>''';
      final r = parseCallersBoxSearchResults(html).single;
      expect(r.figuresAvailable, isFalse);
    });

    test('a nested table cannot shift the author / formation columns', () {
      // `row.querySelectorAll('td')` is DESCENDANT-scoped, so a nested table
      // inside the title cell interleaves its cells into the list in document
      // order. Measured against the real parser: the descendant walk yields
      // ['', '', '', 'EvilⒻPhantom', 'Ⓕ', 'Phantom', 'Auth', 'Form'], so the
      // author reads as 'Ⓕ' and the formation as 'Phantom'. Enumerating only
      // DIRECT-CHILD cells yields ['', '', '', 'EvilⒻPhantom', 'Auth', 'Form']
      // and both columns stay correct.
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=7'>Evil</a>
  <table><tr><td>$markerFigures</td><td>Phantom</td></tr></table></td>
<td>Auth</td><td>Form</td>
</tr></table>''';
      final rows = parseCallersBoxSearchResults(html);
      final r = rows.firstWhere((x) => x.id == '7');
      expect(r.author, 'Auth');
      expect(r.formation, 'Form');
      expect(r.figuresAvailable, isFalse);
    });

    test('a <tr> nested inside another row is not a result at all', () {
      // A pre-existing hazard (`querySelectorAll('tr')` matches nested rows
      // too) that #845 would otherwise AMPLIFY: the injected row is shaped so
      // its own leading cell carries Ⓕ, so it would enter the results claiming
      // figures it does not have. A real TCB result row is never nested inside
      // another row, so rows with a <tr> ancestor are skipped.
      const html = '''
<table><tr>
<td></td><td></td><td></td>
<td><a href='dance.php?id=8'>Host Dance</a>
  <table><tr>
    <td>$markerFigures</td>
    <td><a href='dance.php?id=666'>Phantom Dance</a></td>
  </tr></table></td>
<td>Auth</td><td>Form</td>
</tr></table>''';
      final rows = parseCallersBoxSearchResults(html);
      expect(rows.map((r) => r.id), ['8']);
      expect(rows.single.figuresAvailable, isFalse);
    });

    test('malformed HTML still yields an empty list rather than throwing', () {
      expect(parseCallersBoxSearchResults('<table><tr><td'), isEmpty);
      expect(parseCallersBoxSearchResults('\u0000<<<>>>'), isEmpty);
    });

    test('id / name / author / formation are unaffected by the scan', () {
      // Guards the direct-child enumeration change against regressing the flat
      // happy path that every real TCB page uses.
      final rows = parseCallersBoxSearchResults(_moneyMuskResults);
      expect(rows.map((r) => r.id), ['10600', '3913', '3326']);
      expect(rows.map((r) => r.author), [
        'Traditional',
        'Traditional',
        'Walter Lenk',
      ]);
      expect(rows.map((r) => r.formation), [
        'Triple Minor',
        'Triple Minor',
        'Triplet',
      ]);
      expect(rows.map((r) => r.figuresAvailable), [true, true, false]);
    });
  });
}
