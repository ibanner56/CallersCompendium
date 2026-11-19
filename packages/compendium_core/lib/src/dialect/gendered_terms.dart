/// Gendered role words, which the app never shows (ADR-006 §9.1, point 7:
/// "Don't. show. gendered. role. terms. They're discouraged, explicitly.").
///
/// The app still *recognizes* them in text it reads (imports, typed figures,
/// discouraged-term conversion) and stores what they mean, a canonical role.
/// What this file guards is the other direction: a dialect may not use one
/// as the words it shows, for any dance form.
library;

import 'dialect.dart' show Dialect;

/// The gendered role words a dialect may not show, lowercase: every gendered
/// word [legacyRoleSynonyms] and the discouraged-term table already read as a
/// role, plus "gentleman" and "gentlemen".
const Set<String> genderedRoleWords = {
  'gent',
  'gents',
  'gentleman',
  'gentlemen',
  'man',
  'men',
  'lady',
  'ladies',
  'woman',
  'women',
};

/// What separates words: anything that is not a letter or mark. Digits and
/// connectors separate too, so "Gents2" and "Gents_Night" hold the word
/// "gents"; an apostrophe does, so "Gent's" holds "gent".
final RegExp _nonWord = RegExp(r'[^\p{L}\p{M}]+', unicode: true);

/// The gendered role words that are also everyday words in a language the
/// app ships: "man" is the impersonal pronoun in German and Danish ("one"),
/// and "men" in Dutch. In a sentence (a move wording, a substitution, a
/// dialect's name) they are not taken as gendered; as a role term on their
/// own, they are.
const Set<String> _alsoPronouns = {'man', 'men'};

/// The first gendered role word that [text] holds as a whole word
/// (lowercase), or null when it holds none. "Ladies" and "first gent" hold
/// one; "Robin", "Mandy" and "salmon" do not.
///
/// [inProse] is for text that may be a sentence in any shipped language: it
/// skips [_alsoPronouns], so a German wording such as "dann geht man vor" is
/// not refused or dropped.
String? genderedRoleWordIn(String text, {bool inProse = false}) {
  for (final word in text.toLowerCase().split(_nonWord)) {
    if (inProse && _alsoPronouns.contains(word)) continue;
    if (genderedRoleWords.contains(word)) return word;
  }
  return null;
}

/// What a dialect named [name] is called on screen: [name], or [replacement]
/// when [name] holds a gendered role word. A name like that can still reach
/// the app (an older build, a backup, another device) before the library
/// renames it on load, so a screen that shows a stored dialect name directly,
/// rather than one from the loaded library, goes through this.
String shownDialectName(
  String name, {
  String replacement = Dialect.customName,
}) => genderedRoleWordIn(name, inProse: true) == null ? name : replacement;
