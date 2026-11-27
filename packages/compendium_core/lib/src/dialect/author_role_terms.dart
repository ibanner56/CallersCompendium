/// Choreographers whose dances keep the role terms "larks" and "robins"
/// whatever dialect the reader has chosen.
///
/// A dialect is a reader's own presentation choice and normally wins
/// everywhere (`docs/design/dialect.md`). This file is the one exception:
/// Rachel ("Rae") Fifer has asked the dance community at large that her dances
/// only ever be called with larks and robins. Her dances therefore render
/// through [dialectForDance], which swaps the reader's role terms for lark and
/// robin, leaves out the reader's move names and wordings that hold a gendered
/// role word, and leaves the rest of their dialect (the other move names and
/// wordings, the other dancer words) as they chose it.
library;

import 'package:meta/meta.dart';

import 'dialect.dart';
import 'renderer.dart';

/// The role terms every dance [requiresLarksRobins] is shown with.
const Map<String, RoleTerm> _larksRobinsRoles = {
  'role1': RoleTerm('lark'),
  'role2': RoleTerm('robin'),
};

/// Choreographers, as `(given names, family name)`, who asked for the
/// larks/robins exception. A given name matches the first word of an author
/// name and the family name its last, so "Rae Fifer", "Rachel Fifer" and
/// "Rachel (Rae) Fifer" all match.
const List<({Set<String> given, String family})> _larksRobinsChoreographers = [
  (given: {'rachel', 'rae'}, family: 'fifer'),
];

/// Dances named in the request, by normalized title ([_words] joined by a
/// space). Matched only when the dance names no author, so a dance whose author
/// was not imported is still caught, and another choreographer's dance that
/// shares a title is not.
const Set<String> _larksRobinsTitles = {
  'renewed joy',
  'if i was dead and it wouldnt go to waste',
};

/// The gendered role words a dance [requiresLarksRobins] leaves out of the
/// reader's move names and wordings, lowercase. The app's own former list of
/// gendered role words, restored for this one use from gendered_terms.dart,
/// the file #2570 removed: its words
/// are the gendered ones `legacyRoleSynonyms` and the discouraged-term table
/// read as a role, plus "gentleman" and "gentlemen".
const Set<String> _genderedRoleWords = {
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

/// Gendered role words that are also everyday words in a language the app
/// ships: "man" is the impersonal pronoun in German and Danish ("one"), and
/// "men" is a word in Dutch. A move name or wording is a sentence in any of
/// those languages, so these are not taken as gendered there, and a German
/// wording such as "dann geht man vor" is kept (the former list's own rule).
/// The cost: an English wording whose only role word is "man" or "men" is
/// kept too.
const Set<String> _alsoPronouns = {'man', 'men'};

/// What separates words: anything that is not a letter or mark, so "Gents2"
/// and "Men-chain" hold a role word, and "Gent's" holds "gent".
final RegExp _nonWord = RegExp(r'[^\p{L}\p{M}]+', unicode: true);

/// Whether [text], a move name or wording, holds a gendered role word as a
/// whole word, in any case, other than [_alsoPronouns]. "Ladies chain" does;
/// "Mandy chain", "salmon" and "dann geht man vor" do not.
bool _holdsGenderedRoleWord(String text) {
  for (final word in text.toLowerCase().split(_nonWord)) {
    if (_alsoPronouns.contains(word)) continue;
    if (_genderedRoleWords.contains(word)) return true;
  }
  return false;
}

/// Author names that say nothing about who wrote the dance. "Unknown" and
/// "Traditional" are real choreographer rows, not an empty author list.
const Set<String> _anonymousAuthors = {'unknown', 'traditional', 'trad'};

/// Lowercase words of [text], with apostrophes dropped so "Wouldn't" and
/// "Wouldn’t" both read `wouldnt`.
List<String> _words(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[\'‘’ʼ`]'), '')
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((w) => w.isNotEmpty)
    .toList();

bool _isLarksRobinsChoreographer(String name) {
  final words = _words(name);
  if (words.length < 2) return false;
  for (final c in _larksRobinsChoreographers) {
    if (words.last == c.family && c.given.contains(words.first)) return true;
  }
  return false;
}

/// Whether the dance titled [title] by [authorNames] must be shown with the
/// role terms "larks" and "robins" whatever the reader's dialect.
///
/// True when any author is a choreographer who asked for it, or when the
/// title is one of the dances named in the request and no author is named
/// ([authorNames] empty, or only "Unknown"/"Traditional").
bool requiresLarksRobins({
  required String title,
  required Iterable<String> authorNames,
}) {
  final named = [
    for (final name in authorNames)
      if (_words(name).join(' ') case final n
          when n.isNotEmpty && !_anonymousAuthors.contains(n))
        name,
  ];
  if (named.any(_isLarksRobinsChoreographer)) return true;
  return named.isEmpty && _larksRobinsTitles.contains(_words(title).join(' '));
}

/// Whether [dialect]'s role terms already read lark and robin (in any case),
/// so [dialectForDance] leaves its role terms, and its single-dancer and
/// discouraged words, as they are.
bool _hasLarksRobinsRoles(Dialect dialect) {
  for (final MapEntry(:key, :value) in _larksRobinsRoles.entries) {
    final term = dialect.roles[key];
    if (term == null ||
        term.singular.toLowerCase() != value.singular ||
        term.plural.toLowerCase() != value.plural) {
      return false;
    }
  }
  return true;
}

/// Whether showing the dance titled [title] by [authorNames] sets aside the
/// role terms of [dialect]: the dance [requiresLarksRobins] and [dialect]
/// calls the roles something else. What the dance detail page tells the
/// reader about.
bool overridesRoleTerms(
  Dialect dialect, {
  required String title,
  required Iterable<String> authorNames,
}) =>
    requiresLarksRobins(title: title, authorNames: authorNames) &&
    !_hasLarksRobinsRoles(dialect);

/// The dialect to show the dance titled [title] by [authorNames] in, given the
/// reader's [dialect].
///
/// Returns [dialect] itself unless the dance [requiresLarksRobins] and
/// [dialect] either [overridesRoleTerms] or has a move name or wording that
/// holds a gendered role word. Otherwise returns a copy, under the same name.
/// When it [overridesRoleTerms], the copy:
/// - calls the roles lark and robin;
/// - drops the reader's own words for single dancers (`onesRole1` …), which
///   usually spell a role ("first gent"), so they read "first lark";
/// - stops flagging lark and robin as discouraged terms.
///
/// Either way, the copy drops each of the reader's move names
/// ([Dialect.moves]), move wordings ([Dialect.moveWordings]) and wording
/// branches ([Dialect.moveWordingBranches]) that holds a gendered role word,
/// so that move reads in the app's default wording ("ladies chain" reads as
/// the default chain): the maintainer's answer to question 35 of the
/// pre-release audit's decision sheet, 2026-11-27.
///
/// So a returned copy does not by itself mean the role terms were set aside:
/// ask [overridesRoleTerms] for that. The other move names and wordings and
/// the other dancer words are the
/// reader's. Only what is shown changes: [dialect] itself, the caller's
/// stored dialect, is never changed.
@useResult
Dialect dialectForDance(
  Dialect dialect, {
  required String title,
  required Iterable<String> authorNames,
}) {
  if (!requiresLarksRobins(title: title, authorNames: authorNames)) {
    return dialect;
  }
  final moves = {
    for (final MapEntry(:key, :value) in dialect.moves.entries)
      if (!_holdsGenderedRoleWord(value)) key: value,
  };
  final moveWordings = {
    for (final MapEntry(:key, :value) in dialect.moveWordings.entries)
      if (!_holdsGenderedRoleWord(value)) key: value,
  };
  final moveWordingBranches = {
    for (final MapEntry(key: move, value: branches)
        in dialect.moveWordingBranches.entries)
      if ({
            for (final MapEntry(:key, :value) in branches.entries)
              if (!_holdsGenderedRoleWord(value)) key: value,
          }
          case final kept when kept.isNotEmpty)
        move: kept,
  };
  final dropsWording =
      moves.length != dialect.moves.length ||
      moveWordings.length != dialect.moveWordings.length ||
      !_sameBranches(moveWordingBranches, dialect.moveWordingBranches);
  if (_hasLarksRobinsRoles(dialect)) {
    return dropsWording
        ? dialect.copyWith(
            moves: moves,
            moveWordings: moveWordings,
            moveWordingBranches: moveWordingBranches,
          )
        : dialect;
  }
  final larksRobinsWords = {
    for (final term in _larksRobinsRoles.values) ...{
      term.singular,
      term.plural,
    },
  };
  return dialect.copyWith(
    roles: _larksRobinsRoles,
    moves: moves,
    moveWordings: moveWordings,
    moveWordingBranches: moveWordingBranches,
    dancers: {
      for (final entry in dialect.dancers.entries)
        if (FigureRenderer.singleDancerDefaultTerm(entry.key, dialect) == null)
          entry.key: entry.value,
    },
    discouragedTerms: [
      for (final term in dialect.discouragedTerms)
        if (!larksRobinsWords.contains(term)) term,
    ],
  );
}

/// Whether [a] and [b] hold the same wording branches.
bool _sameBranches(
  Map<String, Map<String, String>> a,
  Map<String, Map<String, String>> b,
) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    final other = b[key];
    if (other == null || other.length != value.length) return false;
    for (final MapEntry(key: branch, value: text) in value.entries) {
      if (other[branch] != text) return false;
    }
  }
  return true;
}
