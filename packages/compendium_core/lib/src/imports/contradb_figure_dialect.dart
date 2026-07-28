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
      _passTheOcean,
      _formAShortWave,
      _formLongWaves,
      _hey,
      _longLines,
      _balanceTheRing,
      _petronella,
      _roryOMore,
      _pullByDirection,
      _balance,
      _doSiDo,
      _allemandeOrbit,
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
      _giveAndTake,
      _rollAway,
      _turnAlone,
      _madRobin,
      _passBy,
      _passThrough,
      _pullByDancers,
      _gate,
      _contraCorners,
      _starPromenade,
      _zigZag,
      _boxCirculate,
      _slice,
      _revolvingDoor,
      _facingStar,
      _poussette,
      _crossTrails,
      _downTheHall,
      _upTheHall,
      _figure8,
      _squareThrough,
      _formALongWave,
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

/// allemandeOrbitWords. Renders as: "WHO allemande HAND INNER around while the
/// OTHER orbit clockwise|counter clockwise OUTER around". Ordered before the
/// plain allemande so an orbit isn't read as an allemande with a trailing note.
FigureMatch? _allemandeOrbit(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('allemande')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null;
  s.take();
  final inner = _rotation(s.peek());
  if (inner == null) return null;
  s.take();
  if (!s.eat('around')) return null;
  if (!s.eatPhrase('while the')) return null;
  if (_subject(s) == null) return null; // the orbiting pair
  if (!s.eat('orbit')) return null;
  if (!(s.eatPhrase('counter clockwise') || s.eat('clockwise'))) {
    // direction word is always rendered; if absent this isn't an orbit
    return null;
  }
  final params = <String, Object?>{'who': who, 'hand': hand, 'inner': inner};
  final outer = _rotation(s.peek());
  if (outer != null) {
    s.take();
    params['outer'] = outer;
  }
  s.eat('around');
  return FigureMatch('allemande_orbit', params: params, note: s.note());
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

/// pass_the_ocean (ContraDB `form an ocean wave` with pass_through=true).
/// Renders as: "pass through to an ocean wave [& balance] - CENTER by HAND in
/// the center, SIDES by HAND on the sides". The balance is kept INLINE here
/// (pass_the_ocean carries a balance param). Diagonal waves are deferred.
FigureMatch? _passTheOcean(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('pass through to')) return null;
  if (!(s.eat('a') || s.eat('an'))) return null;
  if (s.peek() == 'diagonal') return null;
  if (!s.eatPhrase('ocean wave')) return null;
  final balance = _eatAmpBalance(s);
  if (!s.eat('-')) return null;
  final center = _subject(s);
  if (center == null) return null;
  if (!s.eat('by')) return null;
  final centerHand = _leftRight(s.peek());
  if (centerHand == null) return null;
  s.take();
  if (!s.eatPhrase('in the center')) return null;
  final sides = _subject(s);
  if (sides == null) return null;
  if (!s.eat('by')) return null;
  final sideHand = _leftRight(s.peek());
  if (sideHand == null) return null;
  s.take();
  if (!s.eatPhrase('on the sides')) return null;
  return FigureMatch(
    'pass_the_ocean',
    params: {
      'dir': 'across',
      if (balance) 'balance': true,
      'center': center,
      'centerHand': centerHand,
      'sides': sides,
    },
    note: s.note(),
  );
}

/// form_a_short_wave (ContraDB `form an ocean wave` with pass_through=false).
/// Renders as: "form an ocean wave [& balance] - CENTER by HAND hands and SIDES
/// by HAND hands". The balance is NOT stored here — when present it is emitted
/// as a SEPARATE balance figure by the adapter (the form_long_waves precedent);
/// the adapter re-detects it from the row text, so this recognizer just consumes
/// the "& balance" token. Diagonal waves are deferred.
FigureMatch? _formAShortWave(String text) {
  final s = _Scan(text);
  if (!s.eat('form')) return null;
  if (!(s.eat('a') || s.eat('an'))) return null;
  if (s.peek() == 'diagonal') return null;
  if (!s.eatPhrase('ocean wave')) return null;
  _eatAmpBalance(s); // consumed; the adapter emits the separate balance figure
  if (!s.eat('-')) return null;
  final center = _subject(s);
  if (center == null) return null;
  if (!s.eat('by')) return null;
  final centerHand = _leftRight(s.peek());
  if (centerHand == null) return null;
  s.take();
  if (!s.eat('hands')) return null;
  if (!s.eat('and')) return null;
  final sides = _subject(s);
  if (sides == null) return null;
  if (!s.eat('by')) return null;
  final sideHand = _leftRight(s.peek());
  if (sideHand == null) return null;
  s.take();
  if (!s.eat('hands')) return null;
  return FigureMatch(
    'form_a_short_wave',
    params: {
      'dir': 'across',
      'center': center,
      'centerHand': centerHand,
      'sides': sides,
    },
    note: s.note(),
  );
}

/// Consumes an optional `& balance` token, returning whether it was present.
bool _eatAmpBalance(_Scan s) {
  final save = s.pos;
  if (s.eat('&') && s.eat('balance')) return true;
  s.reset(save);
  return false;
}

/// heyWords (common full/half form). Renders as: "PASS1 start a FULL|HALF hey -
/// SH1 PLACE, SH2 PLACE". Extracts pass1, length, and the first shoulder; the
/// shoulder/place clause is part of the render (consumed, not a note).
/// `until`-length heys and ricochets are deferred (their extra tail, if any,
/// survives verbatim as the note).
FigureMatch? _hey(String text) {
  final s = _Scan(text);
  final pass1 = _subject(s);
  if (pass1 == null) return null;
  if (!s.eat('start')) return null;
  if (!(s.eat('a') || s.eat('an'))) return null;
  String? length;
  if (s.eat('full')) {
    length = 'full';
  } else if (s.eat('half')) {
    length = 'half';
  }
  if (!s.eat('hey')) return null;
  final params = <String, Object?>{'pass1': pass1};
  if (length != null) params['length'] = length;
  final clauseSave = s.pos;
  if (s.eat('-')) {
    final sh1 = _shoulderTerse(s.peek());
    if (sh1 != null) {
      s.take();
      params['shoulder'] = sh1;
      _eatHeyPlace(s);
      final sh2 = _shoulderTerse(s.peek());
      if (sh2 != null) {
        s.take();
        _eatHeyPlace(s);
      }
    } else {
      s.reset(clauseSave); // not a shoulder clause — leave it as the note
    }
  }
  return FigureMatch('hey', params: params, note: s.note());
}

/// Terse hey shoulder word (`rights`/`lefts`) → `right`/`left`.
String? _shoulderTerse(String? token) => switch (token) {
  'rights' => 'right',
  'lefts' => 'left',
  _ => null,
};

/// Consumes a hey place phrase (`in center` / `on ends`) if present.
void _eatHeyPlace(_Scan s) {
  final save = s.pos;
  if (s.eat('in') && s.eat('center')) return;
  s.reset(save);
  if (s.eat('on') && s.eat('ends')) return;
  s.reset(save);
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

/// giveAndTakeWords (give form): `<who> give & take <whom>`. The rarer `take`
/// (give=false) form is left to the shared recognizer / custom fallback.
FigureMatch? _giveAndTake(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!(s.eat('give') && s.eat('&') && s.eat('take'))) return null;
  final params = <String, Object?>{'who': who, 'give': true};
  final whom = _subject(s);
  if (whom != null) params['whom'] = whom;
  return FigureMatch('give_and_take', params: params, note: s.note());
}

/// roll away (generic renderer): `<who> roll away <whom> [half sashay]`. Any
/// half-sashay detail is preserved verbatim as the note rather than guessed.
FigureMatch? _rollAway(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('roll away')) return null;
  final params = <String, Object?>{'who': who};
  final whom = _subject(s);
  if (whom != null) params['whom'] = whom;
  return FigureMatch('roll_away', params: params, note: s.note());
}

/// turnAloneWords: `[<who>] turn alone` (who omitted when everyone).
FigureMatch? _turnAlone(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (!s.eatPhrase('turn alone')) return null;
  return FigureMatch(
    'turn_alone',
    params: {'who': who ?? 'everyone'},
    note: s.note(),
  );
}

/// madRobinWords: `mad robin[ <rotation> around], <who> in front`.
FigureMatch? _madRobin(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('mad robin')) return null;
  final params = <String, Object?>{};
  final save = s.pos;
  final rot = _rotation(s.peek());
  if (rot != null) {
    s.take();
    if (s.eat('around')) {
      params['turn'] = rot;
    } else {
      s.reset(save);
    }
  }
  final who = _subject(s);
  if (who == null) return null;
  params['who'] = who;
  if (!s.eatPhrase('in front')) return null;
  return FigureMatch('mad_robin', params: params, note: s.note());
}

/// dolphinHeyWords is intentionally NOT handled yet: its `whom` is a
/// single-dancer identity (`onesRole1` …) and the render names that single
/// dancer, which needs single-dancer parsing not built here.

/// pass by (generic renderer): `<who> pass by [<side> shoulders]`.
FigureMatch? _passBy(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('pass by')) return null;
  final params = <String, Object?>{'who': who};
  final side = _shoulderPhrase(s);
  if (side != null) params['shoulder'] = side;
  return FigureMatch('pass_by', params: params, note: s.note());
}

/// passThroughWords: `pass through [<side> shoulders] <dir>`. ContraDB always
/// renders a direction; a bare "pass through" (or a TCB annotation like "(NR)")
/// is left to the canonical core / custom fallback.
FigureMatch? _passThrough(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('pass through')) return null;
  final params = <String, Object?>{};
  final side = _shoulderPhrase(s);
  if (side != null) params['shoulder'] = side;
  final dir = _direction(s.peek());
  if (dir == null) return null;
  s.take();
  params['dir'] = dir;
  return FigureMatch('pass_through', params: params, note: s.note());
}

/// pullByDancersWords: `<who> [balance] pull by <hand>`.
FigureMatch? _pullByDancers(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  final balance = s.eat('balance');
  if (!s.eatPhrase('pull by')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null;
  s.take();
  return FigureMatch(
    'pull_by_dancers',
    params: {'who': who, if (balance) 'balance': true, 'hand': hand},
    note: s.note(),
  );
}

/// pullByDirectionWords (non-diagonal): `[balance] pull by <hand> <dir>`.
FigureMatch? _pullByDirection(String text) {
  final s = _Scan(text);
  final balance = s.eat('balance');
  if (!s.eatPhrase('pull by')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null;
  s.take();
  final params = <String, Object?>{if (balance) 'balance': true, 'hand': hand};
  final dir = _direction(s.peek());
  if (dir != null) {
    s.take();
    params['dir'] = dir;
  }
  return FigureMatch('pull_by_direction', params: params, note: s.note());
}

/// gateWords: `<who> gate <whom> to face <direction>`.
FigureMatch? _gate(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('gate')) return null;
  final whom = _subject(s);
  if (whom == null) return null;
  if (!s.eatPhrase('to face')) return null;
  final face = _gateFace(s);
  final params = <String, Object?>{'who': who, 'whom': whom};
  if (face != null) params['face'] = face;
  return FigureMatch('gate', params: params, note: s.note());
}

/// contra corners (generic renderer): `<who> contra corners`. Any authored
/// detail (the custom_figure param) survives verbatim as the note.
FigureMatch? _contraCorners(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('contra corners')) return null;
  return FigureMatch('contra_corners', params: {'who': who}, note: s.note());
}

/// roryOMoreWords: `[balance] [<who>] Rory O'More <slide>`.
FigureMatch? _roryOMore(String text) {
  final s = _Scan(text);
  final balance = s.eat('balance');
  final who = _subject(s);
  if (!s.eatPhrase("rory o'more")) return null;
  final params = <String, Object?>{'balance': balance};
  if (who != null) params['who'] = who;
  final slide = _leftRight(s.peek());
  if (slide != null) {
    s.take();
    params['slide'] = slide;
  }
  return FigureMatch('rory_o_more', params: params, note: s.note());
}

/// starPromenadeWords: `[<who>] star promenade <hand> <rotation>` (who omitted
/// when it is the role1s default).
FigureMatch? _starPromenade(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (!s.eatPhrase('star promenade')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null;
  s.take();
  final params = <String, Object?>{'hand': hand};
  if (who != null) params['who'] = who;
  final rot = _rotation(s.peek());
  if (rot != null) {
    s.take();
    params['turn'] = rot;
  }
  return FigureMatch('star_promenade', params: params, note: s.note());
}

/// zigZagWords: `[<who>] zig <dir> zag <dir> [, <ender>]`. Captures the zig
/// (turn) direction; the ender, if any, survives verbatim as the note.
FigureMatch? _zigZag(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (!s.eat('zig')) return null;
  final turn = _leftRight(s.peek());
  if (turn == null) return null;
  s.take();
  if (!s.eat('zag')) return null;
  if (_leftRight(s.peek()) != null) s.take(); // the (derived) return direction
  final params = <String, Object?>{'turn': turn};
  if (who != null) params['who'] = who;
  return FigureMatch('zig_zag', params: params, note: s.note());
}

/// boxCirculateWords. Renders as: "[balance] box circulate - WHO cross while
/// OTHER loop HAND".
FigureMatch? _boxCirculate(String text) {
  final s = _Scan(text);
  final balance = s.eat('balance');
  if (!s.eatPhrase('box circulate')) return null;
  final params = <String, Object?>{if (balance) 'balance': true};
  final save = s.pos;
  if (s.eat('-')) {
    final who = _subject(s);
    if (who != null &&
        s.eatPhrase('cross while') &&
        _subject(s) != null &&
        s.eat('loop')) {
      params['who'] = who;
      final hand = _leftRight(s.peek());
      if (hand != null) {
        s.take();
        params['hand'] = hand;
      }
    } else {
      s.reset(save);
    }
  }
  return FigureMatch('box_circulate', params: params, note: s.note());
}

/// slice (generic renderer): `slice <left|right> …`. The increment/return detail
/// (by/return params) is left verbatim in the note.
FigureMatch? _slice(String text) {
  final s = _Scan(text);
  if (!s.eat('slice')) return null;
  final slide = _leftRight(s.peek());
  if (slide == null) return null;
  s.take();
  return FigureMatch('slice', params: {'slice': slide}, note: s.note());
}

/// revolvingDoorWords. Renders as: "revolving door - WHO take HAND hands and
/// drop off WHOM on other side".
FigureMatch? _revolvingDoor(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('revolving door')) return null;
  final params = <String, Object?>{};
  final save = s.pos;
  if (s.eat('-')) {
    final who = _subject(s);
    if (who != null && s.eat('take')) {
      params['who'] = who;
      final hand = _leftRight(s.peek());
      if (hand != null) {
        s.take();
        params['hand'] = hand;
      }
      if (s.eatPhrase('hands and drop off')) {
        final whom = _subject(s);
        if (whom != null) {
          params['whom'] = whom;
          s.eatPhrase('on other side');
        }
      }
    } else {
      s.reset(save);
    }
  }
  return FigureMatch('revolving_door', params: params, note: s.note());
}

/// facingStarWords. Renders as: "facing star SPIN N places with WHO putting
/// their HAND hands in and backing up".
FigureMatch? _facingStar(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('facing star')) return null;
  final params = <String, Object?>{};
  final turn = _spinDir(s);
  if (turn != null) params['turn'] = turn;
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
  if (s.eat('with')) {
    final who = _subject(s);
    if (who != null) params['who'] = who;
    if (s.eatPhrase('putting their')) {
      if (_leftRight(s.peek()) != null) s.take();
      s.eatPhrase('hands in and backing up');
    }
  }
  return FigureMatch('facing_star', params: params, note: s.note());
}

/// poussetteWords. Renders as: "[half|full] poussette - WHO pull WHOM back then
/// left|right".
FigureMatch? _poussette(String text) {
  final s = _Scan(text);
  String? half;
  if (s.eat('half')) {
    half = 'half';
  } else if (s.eat('full')) {
    half = 'full';
  }
  if (!s.eat('poussette')) return null;
  final params = <String, Object?>{if (half != null) 'half': half};
  if (s.eat('-')) {
    final who = _subject(s);
    if (who != null && s.eat('pull')) {
      params['who'] = who;
      final whom = _subject(s);
      if (whom != null) params['whom'] = whom;
      if (s.eatPhrase('back then')) {
        final d = _leftRight(s.peek());
        if (d != null) {
          s.take();
          params['turn'] = d == 'right' ? 'clockwise' : 'counterclockwise';
        }
      }
    }
  }
  return FigureMatch('poussette', params: params, note: s.note());
}

/// crossTrailsWords. Renders as: "cross trails - WHO DIR the set SHOULDER
/// shoulders, WHO2 DIR2 the set SHOULDER2 shoulders".
FigureMatch? _crossTrails(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('cross trails')) return null;
  final params = <String, Object?>{};
  if (s.eat('-')) {
    final who = _subject(s);
    if (who != null) {
      params['who'] = who;
      final dir = _direction(s.peek());
      if (dir != null) {
        s.take();
        s.eatPhrase('the set');
        params['dir'] = dir;
      }
      final sh = _shoulderPhrase(s);
      if (sh != null) params['shoulder'] = sh;
      final who2 = _subject(s);
      if (who2 != null) {
        params['who2'] = who2;
        if (_direction(s.peek()) != null) {
          s.take();
          s.eatPhrase('the set');
        }
        _shoulderPhrase(s);
      }
    }
  }
  return FigureMatch('cross_trails', params: params, note: s.note());
}

FigureMatch? _downTheHall(String text) => _hall(text, 'down', 'down_the_hall');
FigureMatch? _upTheHall(String text) => _hall(text, 'up', 'up_the_hall');

/// upOrDownTheHallWords. Renders as: "[WHO] down|up the hall|center|outsides
/// FACING [and ENDER]".
FigureMatch? _hall(String text, String dir, String moveId) {
  final s = _Scan(text);
  final who = _subject(s);
  if (!s.eat(dir)) return null;
  if (!s.eat('the')) return null;
  final String moving;
  if (s.eat('hall')) {
    moving = 'all';
  } else if (s.eat('center')) {
    moving = 'center';
  } else if (s.eat('outsides')) {
    moving = 'outsides';
  } else {
    return null;
  }
  final params = <String, Object?>{'moving': moving};
  if (who != null) params['who'] = who;
  final facing = _hallFacing(s);
  if (facing != null) params['facing'] = facing;
  return FigureMatch(moveId, params: params, note: s.note());
}

/// figure8Words. Renders as: "WHO [half|full] figure 8 [DIR] [, LEAD leading]".
FigureMatch? _figure8(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  String? half;
  if (s.eat('half')) {
    half = 'half';
  } else if (s.eat('full')) {
    half = 'full';
  }
  if (!s.eatPhrase('figure 8')) return null;
  final params = <String, Object?>{'who': who, if (half != null) 'half': half};
  final d = s.peek();
  if (d == 'above' || d == 'below' || d == 'across') {
    s.take();
    params['dir'] = d;
  }
  return FigureMatch('figure_8', params: params, note: s.note());
}

/// squareThroughWords. Renders as: "square through TWO|THREE|FOUR - WHO [balance]
/// pull by HAND, then WHO2 pull by HAND, …".
FigureMatch? _squareThrough(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('square through')) return null;
  const placeWords = {'two': 2, 'three': 3, 'four': 4};
  final params = <String, Object?>{};
  final pw = s.peek();
  if (placeWords.containsKey(pw)) {
    s.take();
    params['places'] = placeWords[pw];
  }
  if (s.eat('-')) {
    final who = _subject(s);
    if (who != null) {
      params['who'] = who;
      params['balance'] = s.eat('balance');
      if (s.eatPhrase('pull by')) {
        final hand = _leftRight(s.peek());
        if (hand != null) {
          s.take();
          params['hand'] = hand;
        }
      }
      if (s.eat('then')) {
        final who2 = _subject(s);
        if (who2 != null) params['who2'] = who2;
      }
    }
  }
  return FigureMatch('square_through', params: params, note: s.note());
}

/// formALongWaveWords (the common in=true/out=false form). Renders as: "WHO dance
/// in to a long wave in the center [- balance the wave]".
FigureMatch? _formALongWave(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eatPhrase('dance in to a long wave in the center')) return null;
  final params = <String, Object?>{'who': who, 'in': true, 'out': false};
  params['balance'] = s.eat('-') && s.eatPhrase('balance the wave');
  return FigureMatch('form_a_long_wave', params: params, note: s.note());
}

/// Consumes a spin-direction word, returning `clockwise`/`counterclockwise`.
String? _spinDir(_Scan s) {
  if (s.eat('clockwise')) return 'clockwise';
  if (s.eat('counter-clockwise')) return 'counterclockwise';
  final save = s.pos;
  if (s.eat('counter') && s.eat('clockwise')) return 'counterclockwise';
  s.reset(save);
  return null;
}

/// Consumes a down/up-the-hall facing phrase.
String? _hallFacing(_Scan s) {
  final save = s.pos;
  if (s.eat('forward')) {
    if (s.eat('and') && s.eat('back')) return 'forwardThenBackward';
    s.reset(save);
    s.eat('forward');
    return 'forward';
  }
  if (s.eat('backward') || s.eat('backing')) return 'backward';
  return null;
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

/// Consumes a `<side> shoulder[s]` phrase, returning `left`/`right`, or null
/// (leaving the cursor put) when the next tokens are not a shoulder phrase.
String? _shoulderPhrase(_Scan s) {
  final side = _leftRight(s.peek());
  if (side == null) return null;
  final save = s.pos;
  s.take();
  if (s.eat('shoulders') || s.eat('shoulder')) return side;
  s.reset(save);
  return null;
}

/// ContraDB rendered set-direction words → our direction vocabulary. Only the
/// common `across`/`along` are mapped; `across` is usually the (empty) default.
const Map<String, String> _directionWords = <String, String>{
  'across': 'across',
  'along': 'along',
};

String? _direction(String? token) =>
    token == null ? null : _directionWords[token];

/// Consumes a gate-face phrase, returning our `up`/`down`/`in`/`out`.
String? _gateFace(_Scan s) {
  if (s.eatPhrase('up the set')) return 'up';
  if (s.eatPhrase('down the set')) return 'down';
  if (s.eatPhrase('into the set')) return 'in';
  if (s.eatPhrase('out of the set')) return 'out';
  return null;
}
