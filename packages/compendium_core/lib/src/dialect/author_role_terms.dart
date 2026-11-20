/// Choreographers whose dances keep the role terms "larks" and "robins"
/// whatever dialect the reader has chosen.
///
/// A dialect is a reader's own presentation choice and normally wins
/// everywhere (`docs/design/dialect.md`). This file is the one exception:
/// Rachel ("Rae") Fifer has asked the dance community at large that her dances
/// only ever be called with larks and robins. Her dances therefore render
/// through [dialectForDance], which swaps the reader's role terms for lark and
/// robin and leaves the rest of their dialect (move names, wordings, the other
/// dancer words) as they chose it.
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
/// so [dialectForDance] has nothing to change.
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
/// Returns [dialect] itself unless [overridesRoleTerms]. Otherwise returns a
/// copy, under the same name, that:
/// - calls the roles lark and robin;
/// - drops the reader's own words for single dancers (`onesRole1` …), which
///   usually spell a role ("first gent"), so they read "first lark";
/// - stops flagging lark and robin as discouraged terms.
///
/// Move names, move wordings and the other dancer words are the reader's.
@useResult
Dialect dialectForDance(
  Dialect dialect, {
  required String title,
  required Iterable<String> authorNames,
}) {
  if (!overridesRoleTerms(dialect, title: title, authorNames: authorNames)) {
    return dialect;
  }
  final larksRobinsWords = {
    for (final term in _larksRobinsRoles.values) ...{
      term.singular,
      term.plural,
    },
  };
  return dialect.copyWith(
    roles: _larksRobinsRoles,
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
