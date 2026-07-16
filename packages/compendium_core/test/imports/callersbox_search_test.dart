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
        ),
      );
      expect(
        results[1],
        const CallersBoxSearchResult(
          id: '3913',
          name: 'Money Musk {variant}',
          author: 'Traditional',
          formation: 'Triple Minor',
        ),
      );
      expect(
        results[2],
        const CallersBoxSearchResult(
          id: '3326',
          name: 'Money Musk Triplet',
          author: 'Walter Lenk',
          formation: 'Triplet',
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
}
