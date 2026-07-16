import '../model/figure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';
import 'figure_text_scrub.dart';
import 'structured_draft.dart';

/// Parses a single free-text figure line into a structured taxonomy [Figure]
/// when it can do so *confidently*, and otherwise degrades to a [customFigure]
/// carrying the (scrubbed) text. This is the ONE parser every free-text import
/// adapter routes its figure lines through, so a line reads the same no matter
/// which source it came from.
///
/// ## Contract
/// - **Parse-never-fails.** Unrecognised text ALWAYS becomes a custom figure;
///   the parser never throws and never drops text (`docs/design/imports.md`).
///   Any unexpected error while recognising falls back to custom.
/// - **Conservative matching.** A line is only structured when it maps cleanly
///   onto exactly one taxonomy move AND the whole line is accounted for — any
///   leftover, unexplained prose forces the custom fallback. A wrong structured
///   match silently misrepresents choreography, which is worse than an honest
///   custom figure: when in doubt, custom.
/// - **Validated.** Every candidate structured figure is checked against
///   [taxonomy]; if it produces any error-severity [ValidationIssue] (unknown
///   move/param, out-of-domain value) it is discarded in favour of custom.
///   Atypical-beat *warnings* are allowed through (source beats are preserved).
///
/// The parser runs AFTER [scrub] (dialect canonicalization + the
/// `gypsy → shoulder round` safety net), so gendered role terms have already
/// become canonical `role1`/`role2` tokens by the time recognition runs.
///
/// Returns `null` only when the line is empty after scrubbing (nothing to
/// store) — callers skip those, matching the previous per-adapter behaviour.
///
/// [beats] and [progression] come from the source line and are preserved on the
/// resulting figure (structured or custom). [label] is the source section label
/// (e.g. `A1`); it is applied ONLY on the custom fallback (`'$label: $text'`,
/// exactly as the adapters did before). Structured figures carry no in-text
/// label — section labels are derived from cumulative beats by the domain model
/// (`deriveSections`), identical to every other structured figure in the app.
Figure? parseFigureLine(
  String rawText, {
  int beats = 0,
  bool progression = false,
  String? label,
  Taxonomy? taxonomy,
  String Function(String)? scrub,
}) {
  final scrubFn = scrub ?? scrubFigureText;
  final tax = taxonomy ?? contraTaxonomy;

  final scrubbed = scrubFn(rawText);
  if (scrubbed.isEmpty) return null;

  Figure fallback() {
    final withLabel = (label == null || label.isEmpty)
        ? scrubbed
        : '$label: $scrubbed';
    return customFigure(withLabel, beats: beats, progression: progression);
  }

  try {
    final match = _recognize(scrubbed);
    if (match == null) return fallback();

    final params = <String, Object?>{
      ...match.params,
      if (beats > 0) 'beats': beats,
    };
    final candidate = Figure(
      move: match.moveId,
      params: params,
      progression: progression,
    );
    final hasError = tax
        .validateFigure(candidate)
        .any((i) => i.severity == ValidationSeverity.error);
    return hasError ? fallback() : candidate;
  } catch (_) {
    return fallback();
  }
}

/// A recognised move: its taxonomy [moveId] and the params extracted from the
/// text (never including `beats`, which the caller layers on from the source).
class _Match {
  const _Match(this.moveId, [this.params = const {}]);
  final String moveId;
  final Map<String, Object?> params;
}

/// Attempts to recognise [scrubbed] as one covered move. Returns `null` when no
/// recognizer accounts for the whole line (→ custom fallback).
_Match? _recognize(String scrubbed) {
  final words = _normalize(scrubbed);
  if (words.isEmpty) return null;

  for (final recognizer in _recognizers) {
    final match = recognizer(List<String>.of(words));
    if (match != null) return match;
  }
  return null;
}

/// Lowercases, maps `&`→`and` and `thru`→`through`, folds the common unicode
/// halves/quarters, strips surrounding punctuation, and splits into words.
List<String> _normalize(String text) {
  var s = text.toLowerCase();
  s = s
      .replaceAll('&', ' and ')
      .replaceAll('½', ' 1/2 ')
      .replaceAll('¼', ' 1/4 ')
      .replaceAll('¾', ' 3/4 ');
  final words = s
      .split(RegExp(r'\s+'))
      .map(_stripEdgePunct)
      .where((w) => w.isNotEmpty)
      .map((w) => w == 'thru' ? 'through' : w)
      .toList();
  return words;
}

String _stripEdgePunct(String w) =>
    w.replaceAll(RegExp(r'^[.,;:!]+'), '').replaceAll(RegExp(r'[.,;:!]+$'), '');

// --- Shared token vocabularies ----------------------------------------------

/// Single words → canonical dancer-set token. Post-scrub, gendered terms are
/// already `role1`/`role2`; this maps relationship words + those tokens.
const Map<String, String> _dancerWords = {
  'neighbor': 'neighbors',
  'neighbors': 'neighbors',
  'partner': 'partners',
  'partners': 'partners',
  'role1': 'role1s',
  'role1s': 'role1s',
  'role2': 'role2s',
  'role2s': 'role2s',
  'everyone': 'everyone',
  'ones': 'ones',
  'twos': 'twos',
};

/// Filler words that carry no structural meaning and may be dropped anywhere.
const Set<String> _filler = {'your', 'the', 'a', 'an'};

// --- Small word-list helpers ------------------------------------------------

/// Removes all leading/embedded [_filler] words in place.
void _dropFiller(List<String> w) => w.removeWhere(_filler.contains);

/// Removes the first occurrence of the consecutive [phrase] found anywhere in
/// [w] and returns true; returns false (leaving [w] untouched) if absent.
bool _consumePhrase(List<String> w, List<String> phrase) {
  for (var i = 0; i + phrase.length <= w.length; i++) {
    var hit = true;
    for (var j = 0; j < phrase.length; j++) {
      if (w[i + j] != phrase[j]) {
        hit = false;
        break;
      }
    }
    if (hit) {
      w.removeRange(i, i + phrase.length);
      return true;
    }
  }
  return false;
}

/// Removes and returns the first dancer-set word found, or null.
String? _takeDancer(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    final token = _dancerWords[w[i]];
    if (token != null) {
      w.removeAt(i);
      return token;
    }
  }
  return null;
}

/// Removes and returns the first `left`/`right` word found, or null.
String? _takeSide(List<String> w) {
  for (var i = 0; i < w.length; i++) {
    if (w[i] == 'left' || w[i] == 'right') {
      final side = w.removeAt(i);
      return side;
    }
  }
  return null;
}

/// Recognises a rotation amount (allemande/do si do/shoulder round `turn`).
/// Consumes the token(s) and returns turns in 0.25..2.5, or null if none.
double? _takeRotation(List<String> w) {
  const single = {
    'once': 1.0,
    '1x': 1.0,
    '1': 1.0,
    'twice': 2.0,
    '2x': 2.0,
    '2': 2.0,
    '1/4': 0.25,
    '1/2': 0.5,
    '3/4': 0.75,
    '1.25': 1.25,
    '1.5': 1.5,
    '1.75': 1.75,
    '2.5': 2.5,
  };
  for (var i = 0; i < w.length; i++) {
    // Two-token "1 1/2" / "1 1/4" / "1 3/4" forms.
    if (i + 1 < w.length && w[i] == '1') {
      const combo = {'1/4': 1.25, '1/2': 1.5, '3/4': 1.75};
      final v = combo[w[i + 1]];
      if (v != null) {
        w.removeRange(i, i + 2);
        return v;
      }
    }
    final v = single[w[i]];
    if (v != null) {
      w.removeAt(i);
      return v;
    }
  }
  return null;
}

/// Recognises circle/star travel and returns a `places` count (1..10), or null.
/// Handles `N places`, quarter fractions, and "once"/"all the way"/"halfway".
int? _takePlaces(List<String> w) {
  // "N places" (or "N place").
  for (var i = 0; i + 1 < w.length; i++) {
    if (w[i + 1] == 'places' || w[i + 1] == 'place') {
      final n = int.tryParse(w[i]);
      if (n != null && n >= 1 && n <= 10) {
        w.removeRange(i, i + 2);
        return n;
      }
    }
  }
  const byToken = {
    '1/4': 1,
    '2/4': 2,
    '1/2': 2,
    '3/4': 3,
    '4/4': 4,
    'once': 4,
    '1x': 4,
    '1': 4,
    'full': 4,
    'round': 4,
    'halfway': 2,
    'half': 2,
    'twice': 8,
    '2x': 8,
  };
  for (var i = 0; i < w.length; i++) {
    final v = byToken[w[i]];
    if (v != null) {
      w.removeAt(i);
      return v;
    }
  }
  // "all the way" / "all the way around" / bare "all around".
  if (_consumePhrase(w, ['all', 'the', 'way']) || _consumePhrase(w, ['all'])) {
    _consumePhrase(w, ['around']);
    return 4;
  }
  return null;
}

// --- Per-move recognizers ----------------------------------------------------
//
// Each recognizer works on a mutable copy of the word list, consuming the
// tokens it understands. It returns a [_Match] ONLY when the list is empty
// afterwards (the whole line is accounted for); otherwise it returns null and
// the next recognizer — or the custom fallback — takes over.

typedef _Recognizer = _Match? Function(List<String> words);

final List<_Recognizer> _recognizers = [
  _swing,
  _petronella,
  _balanceTheRing,
  _balance,
  _shoulderRound,
  _allemande,
  _doSiDo,
  _boxTheGnat,
  _circle,
  _star,
  _chain,
  _rightLeftThrough,
  _passThrough,
  _promenade,
  _longLines,
];

_Match? _swing(List<String> w) {
  final who = _takeDancer(w);
  String prefix = 'none';
  if (_consumePhrase(w, ['balance', 'and'])) {
    prefix = 'balance';
  } else if (_consumePhrase(w, ['meltdown'])) {
    prefix = 'meltdown';
  }
  if (!_consumePhrase(w, ['swing'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('swing', {
    'who': who2 ?? 'partners',
    if (prefix != 'none') 'prefix': prefix,
  });
}

_Match? _petronella(List<String> w) {
  // Optional leading "balance and" (petronella's balance flag defaults true).
  _consumePhrase(w, ['balance', 'and']);
  if (!_consumePhrase(w, ['petronella'])) return null;
  // Optional trailing descriptor.
  _consumePhrase(w, ['turn']);
  _consumePhrase(w, ['spin']);
  _consumePhrase(w, ['twirl']);
  _dropFiller(w);
  return w.isEmpty ? const _Match('petronella') : null;
}

_Match? _balanceTheRing(List<String> w) {
  if (!_consumePhrase(w, ['balance', 'the', 'ring'])) return null;
  _dropFiller(w);
  return w.isEmpty ? const _Match('balance_the_ring') : null;
}

_Match? _balance(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['balance'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('balance', {'who': who2 ?? 'neighbors'});
}

_Match? _shoulderRound(List<String> w) {
  final who = _takeDancer(w);
  final side = _takeSide(w); // leading "left shoulder round"
  if (!_consumePhrase(w, ['shoulder', 'round'])) return null;
  final who2 = who ?? _takeDancer(w);
  final side2 = side ?? _takeSide(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('shoulder_round', {
    'who': who2 ?? 'neighbors',
    'shoulder': ?side2,
    'turn': ?turn,
  });
}

_Match? _allemande(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['allemande'])) return null;
  final who2 = who ?? _takeDancer(w);
  final hand = _takeSide(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('allemande', {
    'who': who2 ?? 'neighbors',
    'hand': ?hand,
    'turn': ?turn,
  });
}

_Match? _doSiDo(List<String> w) {
  final who = _takeDancer(w);
  final seeSaw = _consumePhrase(w, ['see', 'saw']);
  final isDoSiDo =
      _consumePhrase(w, ['do', 'si', 'do']) ||
      _consumePhrase(w, ['do', 'sa', 'do']) ||
      _consumePhrase(w, ['dosido']);
  if (!seeSaw && !isDoSiDo) return null;
  final who2 = who ?? _takeDancer(w);
  final turn = _takeRotation(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  final moveId = seeSaw ? 'see_saw' : 'do_si_do';
  return _Match(moveId, {'who': who2 ?? 'neighbors', 'turn': ?turn});
}

_Match? _boxTheGnat(List<String> w) {
  final who = _takeDancer(w);
  final swat = _consumePhrase(w, ['swat', 'the', 'flea']);
  final box = _consumePhrase(w, ['box', 'the', 'gnat']);
  if (!swat && !box) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  final moveId = swat ? 'swat_the_flea' : 'box_the_gnat';
  return _Match(moveId, {'who': who2 ?? 'partners'});
}

_Match? _circle(List<String> w) {
  if (!_consumePhrase(w, ['circle'])) return null;
  final turn = _takeSide(w); // circle `turn` is left/right
  final places = _takePlaces(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('circle', {'turn': ?turn, 'places': ?places});
}

_Match? _star(List<String> w) {
  if (!_consumePhrase(w, ['star'])) return null;
  final hand = _takeSide(w);
  final places = _takePlaces(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('star', {'hand': ?hand, 'places': ?places});
}

_Match? _chain(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['chain'])) return null;
  final who2 = who ?? _takeDancer(w);
  // Optional direction.
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  // chain's `who` domain is role1s/role2s only. An explicit dancer set outside
  // that domain (e.g. "partners chain") must NOT be silently dropped to the
  // taxonomy default — that would misrepresent the source — so reject the
  // match and let it fall back to custom. No explicit dancer → leave `who`
  // unset so the taxonomy default (role2s) applies.
  if (who2 != null && who2 != 'role1s' && who2 != 'role2s') return null;
  return _Match('chain', {'who': ?who2, 'dir': ?dir});
}

_Match? _rightLeftThrough(List<String> w) {
  final ok =
      _consumePhrase(w, ['right', 'left', 'through']) ||
      _consumePhrase(w, ['right', 'and', 'left', 'through']);
  if (!ok) return null;
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('right_left_through', {'dir': ?dir});
}

_Match? _passThrough(List<String> w) {
  if (!_consumePhrase(w, ['pass', 'through'])) return null;
  String? dir;
  if (_consumePhrase(w, ['across'])) {
    dir = 'across';
  } else if (_consumePhrase(w, ['along'])) {
    dir = 'along';
  }
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('pass_through', {'dir': ?dir});
}

_Match? _promenade(List<String> w) {
  final who = _takeDancer(w);
  if (!_consumePhrase(w, ['promenade'])) return null;
  final who2 = who ?? _takeDancer(w);
  _dropFiller(w);
  if (w.isNotEmpty) return null;
  return _Match('promenade', {'who': ?who2});
}

_Match? _longLines(List<String> w) {
  if (!_consumePhrase(w, ['long', 'lines'])) return null;
  // Accept the canonical "[go] forward and back" descriptor (goBack default
  // true); nothing else.
  _consumePhrase(w, ['go']);
  _consumePhrase(w, ['forward', 'and', 'back']);
  _consumePhrase(w, ['forward']);
  _consumePhrase(w, ['and']);
  _consumePhrase(w, ['back']);
  _dropFiller(w);
  return w.isEmpty ? const _Match('long_lines') : null;
}
