import 'figure_parser.dart';

/// The ContraDB-HTML figure front-end: a set of reverse-parsers that mirror
/// ContraDB's `libfigure` `<move>Words` renderers (as observed in the
/// server-rendered `contradb.com/dances/N` HTML) and map a rendered figure
/// string back to our taxonomy [FigureMatch].
///
/// ## Why a ContraDB-specific front-end
/// ContraDB renders each figure by a deterministic per-move function over its
/// structured parameters, in a FIXED default dialect (an empty substitution map
/// upstream, so roles render as `gentlespoons`/`ladles` — already canonicalised
/// to `role1s`/`role2s` by [scrubFigureText] before we see them). Because the
/// forward render is deterministic, the inverse is too: each recognizer matches
/// its move's exact rendered template as an ANCHORED PREFIX and reads the params
/// straight back out.
///
/// ## Notes render as a verbatim tail (the reason for the prefix match)
/// ContraDB appends a figure's free-text note to the computed render with NO
/// separator — the note carries its own punctuation (`- don't let go`,
/// `to long wavy lines`, `, hi`). There is therefore no delimiter to split on;
/// the ONLY reliable boundary is the end of the recognised template. Each
/// recognizer consumes its complete template and returns whatever verbatim text
/// trails as [FigureMatch.note], which [parseFigureLine] stores on
/// [Figure.note]. A recognizer that cannot account for its whole template
/// returns `null` and the line falls through to the shared canonical recognizer
/// and, failing that, the custom fallback — so a partial match never yields a
/// structured figure with a bogus note.
///
/// ## Security
/// The text reaching these recognizers has already passed through
/// [scrubFigureText] → [sanitizeImportedText] (control/bidi/zero-width stripping,
/// OWASP display-spoofing hygiene), so an extracted note is sanitised plain
/// data. Notes are stored as data on [Figure.note] and never interpreted or
/// rendered as HTML.
const FigureFrontEnd contraDbHtmlFigureFrontEnd = FigureFrontEnd(
  preRecognizers: _recognizers,
);

/// Order matters: the first non-null result wins. More specific templates that
/// share a prefix with a broader one are listed first (e.g. a subject `balance
/// & swing` before a plain subject `balance`, `balance the ring` before
/// `balance`).
const List<FigureMatch? Function(String)> _recognizers =
    <FigureMatch? Function(String)>[
      _swing,
      _formLongWaves,
      _longLines,
      _balanceTheRing,
      _petronella,
      _balance,
      _doSiDo,
      _allemande,
      _circle,
      _slideAlongSet,
      _chain,
      _rightLeftThrough,
      _star,
      _promenade,
      _boxTheGnat,
      _californiaTwirl,
      _butterflyWhirl,
      _standStill,
      _gyre,
      _archAndDive,
    ];

// --- Recognizers ------------------------------------------------------------

/// swingWords: `<who> [balance &] [long] swing`.
FigureMatch? _swing(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  final params = <String, Object?>{'who': who};
  if (s.eat('balance')) {
    // A bare "balance" without the "&" belongs to the `balance` move, not the
    // swing prefix — bail so the correct recognizer handles it.
    if (!s.eat('&')) return null;
    params['prefix'] = 'balance';
  }
  if (s.peek() == 'long') {
    s.take();
    params['beats'] = 16;
  }
  if (!s.eat('swing')) return null;
  return FigureMatch('swing', params: params, note: s.note());
}

/// longLinesWords: `long lines forward` (goBack=false) or
/// `long lines forward & back` (goBack=true).
FigureMatch? _longLines(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('long lines')) return null;
  if (!s.eat('forward')) return null;
  var goBack = false;
  final save = s.pos;
  if (s.eat('&') && s.eat('back')) {
    goBack = true;
  } else {
    s.reset(save);
  }
  return FigureMatch('long_lines', params: {'goBack': goBack}, note: s.note());
}

/// `balance the ring` (a distinct move from a plain `balance`).
FigureMatch? _balanceTheRing(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('balance the ring')) return null;
  return FigureMatch('balance_the_ring', note: s.note());
}

/// balanceWords: `<who> balance`, or bare `balance` when who == everyone.
FigureMatch? _balance(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (!s.eat('balance')) return null;
  // "balance the ..." / "balance & ..." belong to other moves; only guard the
  // subject-less case (a stated subject already disambiguates).
  if (who == null) {
    final next = s.peek();
    if (next == 'the' || next == '&') return null;
  }
  return FigureMatch(
    'balance',
    params: {'who': who ?? 'everyone'},
    note: s.note(),
  );
}

/// doSiDoWords: `<who> do si do [<rotation>]` (the shoulder is never rendered).
FigureMatch? _doSiDo(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('do si do')) return null;
  final params = <String, Object?>{'who': who};
  final rot = _rotation(s.peek());
  if (rot != null) {
    s.take();
    params['turn'] = rot;
  }
  return FigureMatch('do_si_do', params: params, note: s.note());
}

/// allemande (generic renderer): `<who> allemande <hand> <rotation>`.
FigureMatch? _allemande(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('allemande')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null; // allemande always renders a hand
  s.take();
  final params = <String, Object?>{'who': who, 'hand': hand};
  final rot = _rotation(s.peek());
  if (rot != null) {
    s.take();
    params['turn'] = rot;
  }
  return FigureMatch('allemande', params: params, note: s.note());
}

/// circle (generic renderer): `circle <left|right> <n> places`.
FigureMatch? _circle(String text) {
  final s = _Scan(text);
  if (!s.eat('circle')) return null;
  final turn = _leftRight(s.peek());
  if (turn == null) return null;
  s.take();
  final params = <String, Object?>{'turn': turn};
  final n = int.tryParse(s.peek() ?? '');
  if (n != null) {
    final save = s.pos;
    s.take();
    if (s.eat('places') || s.eat('place')) {
      params['places'] = n;
    } else {
      s.reset(save);
    }
  }
  return FigureMatch('circle', params: params, note: s.note());
}

/// slideAlongSetWords: `slide <left|right> along set`.
FigureMatch? _slideAlongSet(String text) {
  final s = _Scan(text);
  if (!s.eat('slide')) return null;
  final dir = _leftRight(s.peek());
  if (dir == null) return null;
  s.take();
  if (!s.eatPhrase('along set')) return null;
  return FigureMatch('slide_along_set', params: {'slide': dir}, note: s.note());
}

/// chainWords (common case): `<role1s|role2s> chain`. The leading direction and
/// `<hand>-hand` qualifiers render only for non-default values; the ubiquitous
/// form is a bare `ladles chain`.
FigureMatch? _chain(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who != 'role1s' && who != 'role2s') return null;
  if (!s.eat('chain')) return null;
  return FigureMatch('chain', params: {'who': who}, note: s.note());
}

/// formLongWavesWords: `form long waves - <who> face in, <other> face out`.
/// The mirror clause is part of the render; `who` is the "face in" subject.
FigureMatch? _formLongWaves(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('form long waves')) return null;
  final params = <String, Object?>{};
  final save = s.pos;
  if (s.eat('-')) {
    final who = _subject(s);
    if (who != null && s.eat('face') && s.eat('in')) {
      params['who'] = who;
      final mirror = s.pos;
      final other = _subject(s);
      if (!(other != null && s.eat('face') && s.eat('out'))) {
        s.reset(mirror);
      }
    } else {
      s.reset(save);
    }
  }
  return FigureMatch('form_long_waves', params: params, note: s.note());
}

/// petronellaWords: `[balance] petronella` (balance renders as a leading word).
/// Ordered before [_balance] so `balance petronella` is not read as a balance.
FigureMatch? _petronella(String text) {
  final s = _Scan(text);
  final balance = s.eat('balance');
  if (!s.eat('petronella')) return null;
  return FigureMatch(
    'petronella',
    params: {'balance': balance},
    note: s.note(),
  );
}

/// rightLeftThroughWords: `[<dir>] right left through` (across renders empty).
FigureMatch? _rightLeftThrough(String text) {
  final s = _Scan(text);
  final params = <String, Object?>{};
  final dir = _direction(s.peek());
  if (dir != null) {
    s.take();
    params['dir'] = dir;
  }
  if (!s.eatPhrase('right left through')) return null;
  return FigureMatch('right_left_through', params: params, note: s.note());
}

/// starWords (no-grip form): `star <hand> <n> places`. The grip form
/// (`star <hand> - <grip> - <n> places`) is left to the shared recognizer.
FigureMatch? _star(String text) {
  final s = _Scan(text);
  if (!s.eat('star')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null;
  s.take();
  final n = int.tryParse(s.peek() ?? '');
  if (n == null) return null; // grip form / no places → defer to shared _star
  final save = s.pos;
  s.take();
  if (!(s.eat('places') || s.eat('place'))) {
    s.reset(save);
    return null;
  }
  return FigureMatch(
    'star',
    params: {'hand': hand, 'places': n},
    note: s.note(),
  );
}

/// promenadeWords: `<who> promenade [<dir>] [<spin>]`.
FigureMatch? _promenade(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('promenade')) return null;
  final params = <String, Object?>{'who': who};
  final dir = _direction(s.peek());
  if (dir != null) {
    s.take();
    params['dir'] = dir;
  }
  return FigureMatch('promenade', params: params, note: s.note());
}

/// boxTheGnatWords (common form): `<who> box the gnat`.
FigureMatch? _boxTheGnat(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('box the gnat')) return null;
  return FigureMatch('box_the_gnat', params: {'who': who}, note: s.note());
}

/// California twirl (generic renderer): `<who> California twirl`.
FigureMatch? _californiaTwirl(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('california twirl')) return null;
  return FigureMatch('california_twirl', params: {'who': who}, note: s.note());
}

/// butterfly whirl (generic renderer, no subject): `butterfly whirl`.
FigureMatch? _butterflyWhirl(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('butterfly whirl')) return null;
  return FigureMatch('butterfly_whirl', note: s.note());
}

/// stand still (generic renderer): `stand still`.
FigureMatch? _standStill(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('stand still')) return null;
  return FigureMatch('stand_still', note: s.note());
}

/// gyreWords → our `shoulder_round`: `<who> gyre [<side> shoulders] [<rotation>]`.
/// ContraDB renders the move name `gyre` (only `gypsy` is rewritten to
/// `shoulder round` by the scrub), and shows the shoulder word only for the
/// non-default (left) side.
FigureMatch? _gyre(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('gyre')) return null;
  final params = <String, Object?>{'who': who};
  final save = s.pos;
  final side = _leftRight(s.peek());
  if (side != null) {
    s.take();
    if (s.eat('shoulders') || s.eat('shoulder')) {
      params['shoulder'] = side;
    } else {
      s.reset(save);
    }
  }
  final rot = _rotation(s.peek());
  if (rot != null) {
    s.take();
    params['turn'] = rot;
  }
  return FigureMatch('shoulder_round', params: params, note: s.note());
}

/// archAndDiveWords: `<who> arch <other> dive`.
FigureMatch? _archAndDive(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('arch')) return null;
  if (_subject(s) == null) return null; // the mirrored diving pair
  if (!s.eat('dive')) return null;
  return FigureMatch('arch_and_dive', params: {'who': who}, note: s.note());
}

// --- Scanning + token helpers -----------------------------------------------

/// A whitespace tokenizer over the (already-scrubbed) figure text that remembers
/// each token's start offset, so [note] can return the VERBATIM remaining
/// substring (original punctuation/casing intact) once a template is consumed.
class _Scan {
  _Scan(this.text) {
    for (final m in RegExp(r'\S+').allMatches(text)) {
      _tokens.add(m.group(0)!);
      _starts.add(m.start);
    }
  }

  final String text;
  final List<String> _tokens = <String>[];
  final List<int> _starts = <int>[];
  int _i = 0;

  int get pos => _i;
  void reset(int p) => _i = p;

  /// Lowercases and strips surrounding `.,;:!` for matching (ContraDB renders
  /// clause commas like `face in,` / `center,`); the fraction glyphs and `&`
  /// are preserved. The verbatim originals are kept for [note].
  static String _norm(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'^[.,;:!]+'), '')
      .replaceAll(RegExp(r'[.,;:!]+$'), '');

  /// The next token, normalized for matching, or null at end.
  String? peek() => _i < _tokens.length ? _norm(_tokens[_i]) : null;

  /// Consumes the next token if it equals [word] (normalized).
  bool eat(String word) {
    if (_i < _tokens.length && _norm(_tokens[_i]) == word) {
      _i++;
      return true;
    }
    return false;
  }

  /// Consumes a run of space-separated [phrase] words if they all match next.
  bool eatPhrase(String phrase) {
    final parts = phrase.split(' ');
    if (_i + parts.length > _tokens.length) return false;
    for (var k = 0; k < parts.length; k++) {
      if (_norm(_tokens[_i + k]) != parts[k]) return false;
    }
    _i += parts.length;
    return true;
  }

  /// Advances one token and returns it (original casing), or null at end.
  String? take() => _i < _tokens.length ? _tokens[_i++] : null;

  /// The verbatim remaining text from the current token to the end, trimmed;
  /// null when the template consumed the whole line.
  String? note() {
    if (_i >= _tokens.length) return null;
    final tail = text.substring(_starts[_i]).trim();
    return tail.isEmpty ? null : tail;
  }
}

/// Dancer-set subjects, longest phrase first so `next neighbors` wins over
/// `neighbors`. Post-scrub, gendered roles are already `role1s`/`role2s`.
const List<MapEntry<String, String>> _subjectPhrases =
    <MapEntry<String, String>>[
      MapEntry('next neighbors', 'nextNeighbors'),
      MapEntry('previous neighbors', 'prevNeighbors'),
      MapEntry('neighbors', 'neighbors'),
      MapEntry('partners', 'partners'),
      MapEntry('role1s', 'role1s'),
      MapEntry('role2s', 'role2s'),
      MapEntry('ones', 'ones'),
      MapEntry('twos', 'twos'),
      MapEntry('everyone', 'everyone'),
      MapEntry('shadows', 'shadows'),
    ];

/// Consumes a leading dancer-set subject, or returns null if none is present.
String? _subject(_Scan s) {
  for (final entry in _subjectPhrases) {
    if (s.eatPhrase(entry.key)) return entry.value;
  }
  return null;
}

/// ContraDB `degrees2rotations` strings → our rotation param (turns).
const Map<String, double> _rotationStrings = <String, double>{
  '¼': 0.25,
  '½': 0.5,
  '¾': 0.75,
  'once': 1.0,
  '1¼': 1.25,
  '1½': 1.5,
  '1¾': 1.75,
  'twice': 2.0,
  '2¼': 2.25,
  '2½': 2.5,
};

double? _rotation(String? token) =>
    token == null ? null : _rotationStrings[token];

/// Hand/spin direction token → `left`/`right`, else null.
String? _leftRight(String? token) =>
    (token == 'left' || token == 'right') ? token : null;

/// ContraDB rendered set-direction words → our direction vocabulary. Only the
/// common `across`/`along` are mapped; `across` is usually the (empty) default.
const Map<String, String> _directionWords = <String, String>{
  'across': 'across',
  'along': 'along',
};

String? _direction(String? token) =>
    token == null ? null : _directionWords[token];
