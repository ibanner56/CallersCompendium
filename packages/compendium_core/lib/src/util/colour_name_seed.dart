/// Pure-Dart colour-name matcher for the "colour-named dances tint the theme"
/// easter egg (issue #307).
///
/// This lives in the core so it stays Flutter-free and unit-testable: it maps a
/// dance title to an optional **ARGB seed value** (a plain `int`, not a Flutter
/// `Color`). The app layer turns the returned value into a `Color` and feeds it
/// to `ColorScheme.fromSeed`.
///
/// Matching is deliberately conservative and curated — we scan the title's
/// words left to right and return the seed for the first word that either
/// exactly matches a known colour name or begins with one (so compound/plural
/// forms like "Redheads" or "Blue-Haired" still match). Words are compared
/// case-insensitively and split on any non-letter character, so hyphenated and
/// possessive forms ("Blue-Haired", "Sharon's") tokenize cleanly.
library;

/// Curated colour-name → ARGB seed table.
///
/// Values are vivid, mid-toned seeds; `ColorScheme.fromSeed` derives an
/// internally contrast-consistent scheme from each, so these need only be
/// recognisable hues rather than final surface colours. Synonyms (grey/gray,
/// pink/rose, gold/yellow, purple/violet) map to a shared seed.
///
/// Kept intentionally small and unambiguous. Entries are ordered longest-first
/// only for readability; matching does not depend on map order because a word
/// is tested for an exact hit before any prefix hit.
const Map<String, int> _colourSeeds = {
  'red': 0xFFD32F2F,
  'scarlet': 0xFFD32F2F,
  'crimson': 0xFFC62828,
  'rose': 0xFFEC407A,
  'pink': 0xFFE91E63,
  'blue': 0xFF1976D2,
  'green': 0xFF388E3C,
  'gold': 0xFFF9A825,
  'golden': 0xFFF9A825,
  'yellow': 0xFFF9A825,
  'amber': 0xFFF9A825,
  'orange': 0xFFF57C00,
  'purple': 0xFF7B1FA2,
  'violet': 0xFF7B1FA2,
  'indigo': 0xFF3949AB,
  'teal': 0xFF00897B,
  'brown': 0xFF795548,
  'black': 0xFF424242,
  'white': 0xFFBDBDBD,
  'silver': 0xFF9E9E9E,
  'grey': 0xFF9E9E9E,
  'gray': 0xFF9E9E9E,
};

/// Colour names sorted longest-first, so a prefix scan prefers the most
/// specific match (e.g. "golden…" resolves via "golden" before "gold").
final List<String> _prefixOrder = _colourSeeds.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));

/// Splits [title] into lowercase alphabetic words, discarding digits,
/// punctuation, and possessive markers ("Sharon's" → "sharon", "s" dropped as
/// it is not a colour).
Iterable<String> _words(String title) =>
    title.toLowerCase().split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);

/// Returns the ARGB seed value for the first recognised colour word in [title],
/// or `null` when the title contains no colour word.
///
/// A word matches when it equals a known colour name, or is a compound that
/// *begins* with one — e.g. "Redheads" → red, "Bluebird" → blue, "Greenhouse"
/// → green. To avoid false positives on ordinary English words that merely
/// share a colour's opening letters ("Reduce", "Redeem", "Bluff"), a compound
/// match requires the remainder after the colour name to begin with a
/// consonant (a new morpheme like "-heads"/"-bird"), never a vowel
/// ("red|uce", "red|eem"). Matching is case-insensitive.
///
/// Examples that resolve to a seed: "Baby Rose", "Sharon of the Green",
/// "Blue Boy", "Red Beard Reel", "Blue-Haired Girl", "Jurassic Redheads".
int? colourSeedForTitle(String title) {
  for (final word in _words(title)) {
    // Exact hit wins outright.
    final exact = _colourSeeds[word];
    if (exact != null) return exact;
    // Otherwise the word must *begin* with a colour name and continue into a
    // new (consonant-led) morpheme. Longest colour name first so the most
    // specific hue wins.
    for (final name in _prefixOrder) {
      if (word.length > name.length && word.startsWith(name)) {
        final next = word[name.length];
        if (!_isVowel(next)) return _colourSeeds[name];
      }
    }
  }
  return null;
}

bool _isVowel(String ch) =>
    ch == 'a' || ch == 'e' || ch == 'i' || ch == 'o' || ch == 'u';
