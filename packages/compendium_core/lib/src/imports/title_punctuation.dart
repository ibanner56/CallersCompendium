/// Punctuation folding for text sent to, and compared against, the online
/// dance sources' title search.
///
/// Both sources match a title query as a **substring with exact punctuation**
/// (case-insensitive for ASCII letters; The Caller's Box is case-sensitive for
/// accented ones), so a title that is otherwise correct misses when the user's
/// keyboard typed a different apostrophe, quote or dash than the source
/// stored. What each source stores was measured live (2026-10-08):
///
/// - **The Caller's Box** stores only ASCII `'` and `"`. Over its ~16,900
///   titles, `?title=` queries for `’` `‘` `“` `”` `–` `—` `…` `` ` `` and `´`
///   (sent as UTF-8 and as windows-1252 bytes) each match 0 dances, while `'`
///   matches 2,713 and `"` 38.
/// - **ContraDB** is mixed. Of 2,411 readable titles, 286 apostrophes are ASCII
///   `'` and 17 are `’` (U+2019, never `‘`); 5 double quotes are ASCII `"` and
///   one title is wrapped in `“…”`. It has no en/em dashes and spells
///   ellipses `...`. Its search does no folding of its own: `Eleanor's` does
///   not find `Eleanor’s Reel`.
///
/// So [foldTitlePunctuation] maps typographic variants onto the ASCII forms
/// (all The Caller's Box needs), and [contraDbTitleQueryVariants] adds the
/// curly-quote spelling that ContraDB also needs.
library;

/// Characters folded to ASCII `'`: right/left single quotation marks, single
/// high-reversed-9, modifier-letter apostrophe and turned comma, prime,
/// grave accent and acute accent. Neither source stores any of them in a title.
final RegExp _apostrophes = RegExp(
  '[\u2019\u2018\u201B\u02BC\u02BB\u2032`\u00B4]',
);

/// Characters folded to ASCII `"`: left/right double quotation marks, double
/// low-9 and high-reversed-9, and double prime.
final RegExp _doubleQuotes = RegExp('[\u201C\u201D\u201E\u201F\u2033]');

/// Characters folded to ASCII `-`: hyphen, non-breaking hyphen, figure dash,
/// en dash, em dash, horizontal bar and minus sign.
final RegExp _dashes = RegExp('[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]');

/// Space characters other than ASCII space that phones and word processors
/// insert: no-break space, the U+2000 block, narrow no-break space, medium
/// mathematical space and ideographic space.
final RegExp _spaces = RegExp('[\u00A0\u2000-\u200A\u202F\u205F\u3000]');

/// Replaces typographic apostrophes, quotes, dashes, the ellipsis character
/// and non-ASCII spaces in [text] with the ASCII forms the online sources
/// store (see the library comment for the measurements).
///
/// Only punctuation is touched: letters, accents and case pass through, so
/// the result is still a faithful query rather than a comparison key.
String foldTitlePunctuation(String text) => text
    .replaceAll(_apostrophes, "'")
    .replaceAll(_doubleQuotes, '"')
    .replaceAll(_dashes, '-')
    .replaceAll('\u2026', '...')
    .replaceAll(_spaces, ' ');

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Key for deciding whether a search result's title *is* the title the user
/// typed: punctuation folded by [foldTitlePunctuation], whitespace runs
/// collapsed, trimmed and lower-cased.
///
/// Deliberately narrower than `normalizeTitle` (dedupe), which drops all
/// punctuation and a leading article: an exact-title match that treats
/// `The Archive` and `Archive` as the same title would turn a genuine
/// ambiguity into a confident hit.
String titleMatchKey(String title) => foldTitlePunctuation(
  title,
).replaceAll(_whitespaceRun, ' ').trim().toLowerCase();

/// The spellings of [query] to send to ContraDB's title or choreographer
/// search so that it matches regardless of which apostrophe or quote style the
/// stored title uses.
///
/// The first variant is always the [foldTitlePunctuation]-folded (ASCII)
/// query. When that contains `'` or `"`, a second variant spells apostrophes
/// as `’` and double quotes as `“`/`”` — `“` at the start or after a space or
/// opening bracket, `”` elsewhere — which is how ContraDB's curly-quoted
/// titles are written. A title that mixes both styles within itself matches
/// neither; none of the measured titles does.
List<String> contraDbTitleQueryVariants(String query) {
  final ascii = foldTitlePunctuation(query);
  if (!ascii.contains("'") && !ascii.contains('"')) return [ascii];
  final curly = StringBuffer();
  for (var i = 0; i < ascii.length; i++) {
    final c = ascii[i];
    if (c == "'") {
      curly.write('\u2019');
    } else if (c == '"') {
      final opens = i == 0 || ' ([{'.contains(ascii[i - 1]);
      curly.write(opens ? '\u201C' : '\u201D');
    } else {
      curly.write(c);
    }
  }
  return [ascii, curly.toString()];
}
