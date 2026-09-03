import '../model/figure.dart';
import '../taxonomy/param_types.dart';
import '../taxonomy/taxonomy.dart';
import 'figure_parser.dart';
import 'figure_text_scrub.dart';

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
  declineToCustom: _declineStarPromenade,
);

/// Vetoes ContraDB `star promenade` lines so they reach the custom fallback
/// rather than being structured (taxonomy v26, #843).
///
/// **Deleting the recognizer is not enough, and that is the whole reason this
/// hook exists.** The shared recognizers in `figure_parser.dart` are
/// source-neutral, and one of them recognises `star promenade` for every
/// front-end. So removing ContraDB's own recognizer merely handed the line to
/// the shared one, which reads the prose subject as `who` — and ContraDB's
/// subject is the role with a hand in the CENTER, while our `who` now names the
/// dancer you PICK UP on the side (owner ruling, 2026-08-06). The line would
/// have kept structuring, with the wrong dancers, and no test that only checked
/// the dialect file would have noticed.
///
/// Anchored on the two-word phrase so a plain `promenade` — a different move,
/// with an unaffected reading — is untouched.
///
/// **Case-insensitivity comes from the regex flag, NOT from the input.**
/// Matching runs on the SCRUBBED text, which is role-canonicalized but is
/// **not** lowercased — `scrubFigureText` never lowercases, and `_normalize`
/// (which does) runs AFTER this veto. So `Gentlespoons Star Promenade Right 1`
/// scrubs to `role1s Star Promenade Right 1`, with the casing intact, and is
/// caught only because [_starPromenadeVeto] is declared `caseSensitive: false`.
/// Verified: the same pattern without that flag does not match that string.
///
/// This is spelled out because the earlier wording credited the input, which
/// was wrong in a way that would not surface here — the veto works either way —
/// but would bite the next person to add one: drop the flag, trust the comment,
/// and you ship a matcher that silently misses every capitalised line.
bool _declineStarPromenade(String scrubbed) =>
    _starPromenadeVeto.hasMatch(scrubbed);

/// `caseSensitive: false` is LOAD-BEARING — see [_declineStarPromenade]. The
/// scrubbed text this runs against retains its source casing.
final RegExp _starPromenadeVeto = RegExp(
  r'\bstar\s+promenades?\b',
  caseSensitive: false,
);

/// A "while"/"whiles" simultaneity connective, matched as a whole word
/// (case-insensitive) rather than a literal substring — `while` is itself a
/// substring of `whiles` (see ContraDB dance #1603, "Eye Of The Tiger": "…
/// whiles ladles slide left …"), so a literal match would cut `whiles`
/// mid-word.
final RegExp _whileConnective = RegExp(r'\bwhiles?\b', caseSensitive: false);

/// Parses one ContraDB free-text figure line, fanning a general `A while B` /
/// `A whiles B` simultaneity connective out into a [Figure.meanwhile]
/// container (#591, part of the #572 "meanwhile" epic) when — and only
/// when — ordinary recognition does not already resolve the WHOLE line to a
/// structured (non-custom) figure.
///
/// ## Precedence (locked #591 requirement)
/// The named combined moves `boxCirculateWords` ([_boxCirculate], "box
/// circulate - WHO cross while OTHER loop …") and the bare ContraDB form
/// ([_boxCirculateBare], "WHO cross while OTHER loop …") — and every OTHER
/// recognizer in [contraDbHtmlFigureFrontEnd] (plus the canonical shared
/// recognizers) get
/// their full, unmodified first attempt at the WHOLE line via the ordinary
/// [parseFigureLine] call below. Only when that degrades to custom does this
/// function look for a general top-level `while`/`whiles` connective, so a
/// dedicated combined move ALWAYS wins and is never rerouted into a generic
/// `meanwhile` fan-out.
///
/// The `allemandeOrbitWords` combined line (e.g. ContraDB #1717 "…ladles
/// allemande left 1½ around while the gentlespoons orbit clockwise ½ around")
/// is the ONE exception: the fused `allemande_orbit` move was retired (issue
/// #295), so it is now resolved by [_allemandeOrbitMeanwhile] into a
/// `meanwhile[allemande, orbit]` container. That check runs right after the
/// generic parse (and is preferred over it) so the combined template keeps the
/// same first-crack precedence it always had, while emitting a container
/// instead of a fused figure.
///
/// ## Why the container can't be a [FigureMatch] pre-recognizer
/// `meanwhileMove` is a *structural* id (like `customMove`) and is
/// deliberately NOT registered in the ContraDB [Taxonomy], so
/// [Taxonomy.validateFigure] would reject it as an `unknown_move` if it ever
/// reached that check. [Figure.meanwhile] is therefore built DIRECTLY here
/// (both for the general `while` fan-out and for [_allemandeOrbitMeanwhile]),
/// bypassing [parseFigureLine]'s validate step entirely — exactly how
/// `customFigure` already bypasses it.
///
/// ## Fidelity rules (mirrors the CallersBox `||` fan-out in
/// `callersbox_figure_dialect.dart`)
/// - **Prefer-custom.** Each side is parsed via the SAME [parseFigureLine] +
///   [contraDbHtmlFigureFrontEnd] used for the whole line, so a side that
///   fails to structure becomes its own custom sub-figure (already
///   scrubbed/sanitised — #444/#611 parity is automatic, since
///   [parseFigureLine] always scrubs first) rather than collapsing the whole
///   line back to one whole-line custom figure.
/// - **Shared container beats.** The source states ONE combined total for
///   the whole line, so it rides on the container's `beats`
///   ([Figure.meanwhile]'s `beats` parameter); both sides are beats-absent —
///   this keeps [deriveSections]' cumulative beat total byte-identical to the
///   pre-#591 whole-custom line.
/// - **Security bound.** [splitTopLevelOnWord] only ever splits on the FIRST
///   top-level connective, so this always yields exactly 2 sides — always
///   within [kMaxMeanwhileSides]. Sides are ordinary (non-meanwhile) figures,
///   so [Figure.meanwhile]'s flat-only precondition can never fail here — no
///   `try`/`catch` is needed around the factory call.
Figure? parseContraDbFigureLine(
  String rawText, {
  int beats = 0,
  bool progression = false,
  Taxonomy? taxonomy,
  String Function(String)? scrub,
}) {
  final whole = parseFigureLine(
    rawText,
    beats: beats,
    progression: progression,
    taxonomy: taxonomy,
    scrub: scrub,
    frontEnd: contraDbHtmlFigureFrontEnd,
  );
  if (whole == null) return null;
  // Issue #295: the combined `allemandeOrbitWords` line becomes
  // `meanwhile[allemande, orbit]` (the fused `allemande_orbit` move was
  // retired at taxonomy v19). Handled here — after the generic parse, but
  // preferred over it when it resolves — so the named combined template keeps
  // the SAME "first crack at the whole line" precedence the fused
  // `_allemandeOrbit` recognizer previously held, while now emitting a
  // container instead of one fused figure. It reads the scrubbed text (the
  // same normalization the recognizers see) and builds the container directly,
  // bypassing validate exactly like the `while` fan-out below.
  final combinedOrbit = _allemandeOrbitMeanwhile(
    (scrub ?? scrubFigureText)(rawText),
    beats: beats,
    progression: progression,
  );
  if (combinedOrbit != null) return combinedOrbit;
  // A structured prefix-match recognizer (e.g. `_balance`) can capture
  // everything after its own template as a verbatim NOTE — including a
  // `while`/`whiles` connective it has no business absorbing. Trust a
  // non-custom whole-line parse UNLESS its note swallowed that connective;
  // this mirrors `_noteSwallowedCompound` in `figure_front_end_fan_out.dart`
  // (the same guard for `||`/`;`) — a dedicated recognizer like
  // `_allemandeOrbit`/`_boxCirculate` fully consumes its template (empty
  // note), so this never rejects a genuine named-combined-move precedence
  // win; it only rejects an unrelated recognizer greedily swallowing the
  // rest of the line.
  final noteSwallowedConnective =
      whole.note != null &&
      splitTopLevelOnWord(whole.note!, _whileConnective) != null;
  // Nothing to fan out — return unchanged. This is the precedence guarantee
  // above: every named recognizer keeps first crack at the whole line,
  // completely unmodified.
  if (!whole.isCustom && !noteSwallowedConnective) return whole;

  final sides = splitTopLevelOnWord(rawText, _whileConnective);
  // No top-level connective, or a degenerate split (`while B` / `A while`,
  // i.e. one side empty) → decline the fan-out and keep the original
  // whole-line result (today's unchanged behaviour).
  if (sides == null || sides.any((s) => s.isEmpty)) return whole;

  final safeBeats = beats < 0 ? 0 : beats;
  final figures = <Figure>[];
  for (final side in sides) {
    final f = parseFigureLine(
      side,
      taxonomy: taxonomy,
      scrub: scrub,
      frontEnd: contraDbHtmlFigureFrontEnd,
    );
    // `f` is only `null` when `side` is empty after scrubbing (defensive —
    // decline the fan-out rather than drop a side; `whole` still preserves
    // the full source text).
    if (f == null) return whole;
    figures.add(f);
  }
  return Figure.meanwhile(
    figures: figures,
    beats: safeBeats,
    progression: progression,
  );
}

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
      _tradeBy,
      _passThrough,
      _pullByDancers,
      _gate,
      _contraCorners,
      _zigZag,
      _boxCirculateBare,
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
      _dolphinHey,
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
  if (s.eat('meltdown')) {
    params['prefix'] = 'meltdown';
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
  // A trailing "&" always marks a `balance & <move>` compound (swing, rory,
  // petronella, pull by, box circulate, …) emitted by the `bal` param's
  // "balance & " render — never a plain balance — so decline regardless of
  // subject and let the specific recognizer claim it (#578). "balance the ..."
  // likewise belongs to another move; guard it only in the subject-less case
  // (a stated subject already disambiguates a plain balance).
  if (s.peek() == '&') return null;
  if (who == null && s.peek() == 'the') return null;
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

/// Issue #295: the ContraDB `allemandeOrbitWords` combined line — e.g. #1717
/// "…ladles allemande left 1½ around while the gentlespoons orbit clockwise ½
/// around" — is modeled as `meanwhile[allemande, orbit]` (the fused
/// `allemande_orbit` move was RETIRED at taxonomy v19). The source states BOTH
/// the orbit direction AND the orbiting pair, so the container is built with
/// full fidelity (no derivation): `allemande{who, hand, turn: inner}` +
/// `orbit{who: who2, turn: direction, amount: outer}`, both sides beats-absent
/// so the shared line total rides on the container's `beats` (keeping
/// [deriveSections]' cumulative total byte-identical to the pre-split fused
/// line). Returns null — declining to a plain allemande / custom — unless the
/// whole "WHO allemande HAND INNER around while the WHO2 orbit DIR [OUTER]
/// [around]" template resolves. Any trailing prose that still carries a
/// top-level `while`/`whiles` is left for the general fan-out rather than
/// swallowed into the container note.
///
/// `meanwhileMove` is a structural id (like `customMove`) that the ContraDB
/// [Taxonomy] deliberately does not register, so the container is built
/// DIRECTLY here — exactly like [parseContraDbFigureLine]'s `while` fan-out —
/// bypassing [parseFigureLine]'s validate step. Sides are ordinary
/// (non-meanwhile) figures, so [Figure.meanwhile]'s flat-only precondition
/// cannot fail here.
Figure? _allemandeOrbitMeanwhile(
  String text, {
  required int beats,
  required bool progression,
}) {
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
  final who2 = _subject(s); // the orbiting pair
  if (who2 == null) return null;
  if (!s.eat('orbit')) return null;
  final String direction;
  if (s.eatPhrase('counter clockwise')) {
    direction = 'counterclockwise';
  } else if (s.eat('clockwise')) {
    direction = 'clockwise';
  } else {
    // The direction word is always rendered; if absent this isn't an orbit.
    return null;
  }
  final orbitParams = <String, Object?>{'who': who2, 'turn': direction};
  final outer = _rotation(s.peek());
  if (outer != null) {
    s.take();
    orbitParams['amount'] = outer;
  }
  s.eat('around');
  // Leftover after the template is trailing prose. If it still carries a
  // top-level while/whiles connective, decline so the general fan-out can
  // represent that further simultaneity rather than dropping it into a note.
  final note = s.note();
  if (note != null && splitTopLevelOnWord(note, _whileConnective) != null) {
    return null;
  }
  return Figure.meanwhile(
    figures: [
      Figure(
        move: 'allemande',
        params: {'who': who, 'hand': hand, 'turn': inner},
      ),
      Figure(move: 'orbit', params: orbitParams),
    ],
    beats: beats < 0 ? 0 : beats,
    progression: progression,
    note: note,
  );
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

/// circle (generic renderer): `circle {left|right} {n} places`.
///
/// Issue #634: ContraDB free text occasionally phrases a single-file
/// circulation around the ring as `promenade single file around the
/// circle|ring {n} places` (real render: Travels with Rick and Kim #455) —
/// a single-file CIRCLE, not the `promenade` move (this taxonomy has no
/// separate `circle_left` id; `turn` already spans left/right). The owner
/// flagged this as the more fragile of the two #634 mappings, so it is
/// recognized ONLY as this exact, fully-anchored phrase — no partial match,
/// no fallback — and always defaults `turn` to `left` (the phrasing never
/// states a direction).
FigureMatch? _circle(String text) {
  final s = _Scan(text);
  final singleFileSave = s.pos;
  if (s.eatPhrase('promenade single file around the')) {
    final ringNoun = s.peek();
    if (ringNoun == 'circle' || ringNoun == 'ring') {
      s.take();
      final params = <String, Object?>{'turn': 'left', 'singleFile': true};
      _eatPlaces(s, params);
      return FigureMatch('circle', params: params, note: s.note());
    }
  }
  s.reset(singleFileSave);

  if (!s.eat('circle')) return null;
  final turn = _leftRight(s.peek());
  if (turn == null) return null;
  s.take();
  final params = <String, Object?>{'turn': turn};
  _eatPlaces(s, params);
  return FigureMatch('circle', params: params, note: s.note());
}

/// Consumes an optional trailing `<n> places`/`<n> place` into `places` on
/// [params], leaving the cursor put when the count/unit isn't a complete
/// pair. Shared by both `_circle` branches above.
void _eatPlaces(_Scan s, Map<String, Object?> params) {
  final n = int.tryParse(s.peek() ?? '');
  if (n == null) return;
  final save = s.pos;
  s.take();
  if (s.eat('places') || s.eat('place')) {
    params['places'] = n;
  } else {
    s.reset(save);
  }
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

/// chainWords: `[<left|right> diagonal]`, `<role1s|role2s>`,
/// `[<left|right>-hand]`, `chain`. The leading diagonal qualifier renders only
/// for non-default values (real render: The Judge — `left diagonal ladles
/// chain to shadow`) and maps to the `dir` param; the ubiquitous form is a
/// bare `ladles chain`. The hand slot (v28, #976) sits between the subject
/// and `chain`, matching ContraDB's `chainWords` order (`words(sdiag, swho,
/// thand, smove)`, `figure.js:266-278`) — hyphenated (`left-hand`) because
/// that is [_leftRight]'s inverse: ContraDB's renderer emits
/// `shand + "-hand"` (`figure.js:275`), never a bare side, for this move. A
/// bare `<role> chain` (no hand token) sets the role-implied side via
/// [chainHandForWho] — the role word IS the source stating the hand (#976
/// §6.1.2) — which [_subject]'s role1s/role2s requirement above guarantees
/// is always present here, so the role-word-scoping rule (#976 §6.1.3) is
/// satisfied by construction and needs no extra guard in THIS parser.
/// ContraDB's wildcard hand (`*-hand`, `figure.js:271-272`) declines the
/// whole line to `custom` — consistent with `_leftRight` already declining
/// bare `*` for every other move here. A trailing positional qualifier
/// (e.g. `to shadow`) survives verbatim as the note (Q2: shadow kept as a
/// note, never fabricated into a dancer target).
FigureMatch? _chain(String text) {
  final s = _Scan(text);
  String? dir;
  final diagSave = s.pos;
  final diagSide = _leftRight(s.peek());
  if (diagSide != null) {
    s.take();
    if (s.eat('diagonal')) {
      dir = diagSide == 'left' ? 'leftDiagonal' : 'rightDiagonal';
    } else {
      s.reset(diagSave);
    }
  }
  final who = _subject(s);
  if (who == null || (who != 'role1s' && who != 'role2s')) return null;
  final handToken = s.peek();
  if (handToken == '*-hand') return null;
  String? statedHand;
  if (handToken == 'left-hand') {
    statedHand = 'left';
    s.take();
  } else if (handToken == 'right-hand') {
    statedHand = 'right';
    s.take();
  }
  if (!s.eat('chain')) return null;
  final params = <String, Object?>{
    'who': who,
    'hand': statedHand ?? chainHandForWho(who),
  };
  if (dir != null) params['dir'] = dir;
  return FigureMatch('chain', params: params, note: s.note());
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

/// form_short_waves (ContraDB `form an ocean wave` with pass_through=false).
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
    'form_short_waves',
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

/// Consumes a leading `balance` prefix plus the `&` ContraDB renders after it,
/// returning whether a balance was present. The `bal` param's forward renderer
/// (`libfigure` `stringParamBalance`) always emits `balance & ` before the move
/// (e.g. `balance & Rory O'More`, `balance & petronella`), so the `&` is a
/// template token, not a leftover note — leaving it unconsumed made the
/// recognizer decline and demote an otherwise-matchable figure to custom (#578).
/// `balance` itself is always consumed (that is the prefix); the `&` is optional
/// so lenient input rendered without it (e.g. hand-authored `balance petronella`)
/// still recognises. A trailing `&` is only eaten when it immediately follows
/// `balance`, never mid-figure.
bool _eatBalanceAmp(_Scan s) {
  if (!s.eat('balance')) return false;
  s.eat('&');
  return true;
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
  final balance = _eatBalanceAmp(s);
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

/// starWords: `star <hand> [- <grip> -] <n> places`. ContraDB renders the grip
/// clause between the hand and the count for the modeled non-`none` grips
/// (`- wrist grip -`, `- hands across -`; real renders: Al's Safeway Produce,
/// Strange New Worlds, Sweet Vicki, Fun Dance for Marjorie). The grip is
/// consumed into the `grip` param (the taxonomy models `{none, wristGrip,
/// handsAcross}`); any text trailing the count survives verbatim as the note.
FigureMatch? _star(String text) {
  final s = _Scan(text);
  if (!s.eat('star')) return null;
  final hand = _leftRight(s.peek());
  if (hand == null) return null;
  s.take();
  final params = <String, Object?>{'hand': hand};
  // Optional grip clause "- <grip> -"; only consumed as a complete unit so a
  // stray leading dash never derails the count read.
  final gripSave = s.pos;
  if (s.eat('-')) {
    final grip = _starGrip(s);
    if (grip != null && s.eat('-')) {
      params['grip'] = grip;
    } else {
      s.reset(gripSave);
    }
  }
  final n = int.tryParse(s.peek() ?? '');
  if (n == null) return null; // no places → defer to shared _star
  final placesSave = s.pos;
  s.take();
  if (!(s.eat('places') || s.eat('place'))) {
    s.reset(placesSave);
    return null;
  }
  params['places'] = n;
  return FigureMatch('star', params: params, note: s.note());
}

/// Consumes a ContraDB star grip phrase (`wrist grip` / `hands across`) →
/// `wristGrip`/`handsAcross`, leaving the cursor put when neither matches.
String? _starGrip(_Scan s) {
  final save = s.pos;
  if (s.eatPhrase('wrist grip')) return 'wristGrip';
  s.reset(save);
  if (s.eatPhrase('hands across')) return 'handsAcross';
  s.reset(save);
  return null;
}

/// promenadeWords: `<who> promenade [<dir>] [<spin>]`.
///
/// Issue #634: a leading `single file` (no dancer subject follows — a true
/// single-file promenade travels the WHOLE major set, not a per-couple
/// relationship) sets `singleFile` and defaults `who` to `everyone`; real
/// render: Strange New Worlds #3107 — `single file promenade along major set
/// to new neightbors`.
///
/// Issue #749: a bare `along`/`across` direction token immediately after
/// `promenade` IS consumed in the single-file branch, so `dir` is captured
/// from the source text; the rest of the tail was left as the note.
///
/// Issue #921 (taxonomy v29): the destination tail is now structured. After
/// consuming `[dir]`, the recognizer consumes an optional "major set"
/// descriptor and then a "to [new|the same] {subject}" clause, storing the
/// result as `destination`. "new neighbors" (ContraDB source phrasing for the
/// next couple) maps to `nextNeighbors`. An unrecognised tail is still stored
/// verbatim as the note. The ordinary (non-single-file) form is unchanged.
FigureMatch? _promenade(String text) {
  final s = _Scan(text);
  var singleFile = false;
  final sfSave = s.pos;
  if (s.eatPhrase('single file')) {
    singleFile = true;
  } else {
    s.reset(sfSave);
  }
  final who = _subject(s);
  if (who == null && !singleFile) return null;
  if (!s.eat('promenade')) return null;
  final params = <String, Object?>{'who': who ?? 'everyone'};
  if (singleFile) {
    params['singleFile'] = true;
    // Consume a bare direction token (`along` or `across`) immediately after
    // `promenade` so `dir` is captured from the source text.
    final dir = _direction(s.peek());
    if (dir != null) {
      s.take();
      params['dir'] = dir;
    }
    // Consume the destination tail (issue #921):
    //   optional "major set" descriptor (e.g. "along major set to …")
    //   then "to [new|the same] {subject}"
    final preDest = s.pos;
    s.eatPhrase('major set');
    final dest = _promenadeDestination(s);
    if (dest != null) {
      params['destination'] = dest;
    } else {
      s.reset(preDest); // restore if we couldn't parse a destination
    }
  } else {
    final dir = _direction(s.peek());
    if (dir != null) {
      s.take();
      params['dir'] = dir;
    }
    final turn = _promenadeTurn(s);
    if (turn != null) params['turn'] = turn;
  }
  return FigureMatch('promenade', params: params, note: s.note());
}

/// ContraDB renders promenade's optional rotation qualifier after its optional
/// set direction as `on the left` / `on the right`. The canonical taxonomy
/// mapping is a maintainer decision: left means clockwise, right means
/// counterclockwise.
String? _promenadeTurn(_Scan s) {
  if (s.eatPhrase('on the left')) return 'clockwise';
  if (s.eatPhrase('on the right')) return 'counterclockwise';
  return null;
}

/// Consumes a "to [new|the same] {subject}" destination clause for the
/// single-file promenade tail (issue #921, taxonomy v29) and returns the
/// corresponding dancer-set token, or null if no clause is present.
///
/// ContraDB source-text conventions handled:
/// - `to new neighbors` / `to new neightbors` → `nextNeighbors`
/// - `to new neighbors at home` → `nextNeighbors` (consumes "at home" too)
/// - `to the same {subject}` → the matched subject token
/// - `to {subject}` → the matched subject token
///
/// On null: the scanner position is unchanged so the caller's save/reset can
/// leave the tail in the note without double-advancing.
String? _promenadeDestination(_Scan s) {
  final save = s.pos;
  if (!s.eat('to')) return null;

  // "to new …" — ContraDB says "new neighbors" for the next couple.
  // "new" always means `nextNeighbors` regardless of the exact noun form
  // (including typo "neightbors"). Consume the noun if it parses; if not,
  // consume one raw token so it does not land in the note.
  if (s.eat('new')) {
    if (_subject(s) == null) s.take(); // discard noun (even typos)
    s.eatPhrase('at home'); // consume optional "at home" suffix
    return 'nextNeighbors';
  }

  // "to the same {subject}" — maps to the subject directly.
  final theSave = s.pos;
  if (s.eat('the')) {
    if (s.eat('same')) {
      final who = _subject(s);
      if (who != null) return who;
    }
    // "the" consumed but "same" or subject didn't follow — restore.
    s.reset(theSave);
  }

  // "to {subject}" — general case.
  final who = _subject(s);
  if (who != null) return who;

  s.reset(save);
  return null;
}

/// boxTheGnatWords: `<who> [<hand> hand balance &] box the gnat`. ContraDB
/// renders a leading balance as `<hand> hand balance & ` before the move (real
/// renders: 50/50, The Hobbit — `neighbors right hand balance & box the gnat`);
/// the prefix sets `hand` + `balance` and is consumed as a unit so a plain
/// `<who> box the gnat` still matches.
FigureMatch? _boxTheGnat(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  final params = <String, Object?>{'who': who};
  final save = s.pos;
  final hand = _leftRight(s.peek());
  if (hand != null) {
    s.take();
    if (s.eat('hand') && _eatBalanceAmp(s)) {
      params['hand'] = hand;
      params['balance'] = true;
    } else {
      s.reset(save);
    }
  }
  if (!s.eatPhrase('box the gnat')) return null;
  return FigureMatch('box_the_gnat', params: params, note: s.note());
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

/// giveAndTakeWords: `<who> give & take <whom>` (give=true), or the take-only
/// form `<who> take <whom>` (give=false; issue #634 — real renders: The Erik
/// Effect #570 `ladles take neighbors`, Green Lake Twirl #548 `gentlespoons
/// take neighbors`). The take-only branch requires `whom` to resolve to a
/// known dancer-set subject — unlike the looser give=true branch — so a
/// bare `<who> take <anything-else>` line is never force-matched; it falls
/// through to the shared recognizer / custom fallback instead.
FigureMatch? _giveAndTake(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  final giveSave = s.pos;
  if (s.eat('give') && s.eat('&') && s.eat('take')) {
    final params = <String, Object?>{'who': who, 'give': true};
    final whom = _subject(s);
    if (whom != null) params['whom'] = whom;
    return FigureMatch('give_and_take', params: params, note: s.note());
  }
  s.reset(giveSave);
  if (s.eat('take')) {
    final whom = _subject(s);
    if (whom != null) {
      return FigureMatch(
        'give_and_take',
        params: {'who': who, 'give': false, 'whom': whom},
        note: s.note(),
      );
    }
  }
  return null;
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

/// dolphinHeyWords. Renders as: "dolphin hey - start with WHO passing WHOM by
/// SHOULDER", where WHOM is a single dancer ("[the] first|second
/// gentlespoon|ladle", scrubbed to "first|second role1|role2").
FigureMatch? _dolphinHey(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('dolphin hey')) return null;
  if (!s.eat('-')) return null;
  if (!s.eatPhrase('start with')) return null;
  final who = _subject(s);
  if (who == null) return null;
  if (!s.eat('passing')) return null;
  final whom = _singleDancer(s);
  if (whom == null) return null;
  if (!s.eat('by')) return null;
  final params = <String, Object?>{'who': who, 'whom': whom};
  final side = _shoulderPhrase(s);
  if (side != null) params['shoulder'] = side;
  return FigureMatch('dolphin_hey', params: params, note: s.note());
}

/// Consumes a single-dancer identity `[the] first|second role1|role2` →
/// `onesRole1`/`onesRole2`/`twosRole1`/`twosRole2`.
String? _singleDancer(_Scan s) {
  s.eat('the');
  final String couple;
  if (s.eat('first')) {
    couple = 'ones';
  } else if (s.eat('second')) {
    couple = 'twos';
  } else {
    return null;
  }
  final role = s.peek();
  if (role == 'role1' || role == 'role1s') {
    s.take();
    return couple == 'ones' ? 'onesRole1' : 'twosRole1';
  }
  if (role == 'role2' || role == 'role2s') {
    s.take();
    return couple == 'ones' ? 'onesRole2' : 'twosRole2';
  }
  return null;
}

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

/// trade by (issue #945, defect C): `[who] trade by [the] [side
/// shoulder(s)]`, preserving any trailing text as a verbatim note. This
/// mirrors [_passBy] rather than the shared `_tradePassBy` in
/// figure_parser.dart (which also structures `trade by` as of this issue)
/// because a ContraDB dance can carry a trailing tail after the shoulder
/// phrase — Kettle Drum's real line is `ladles trade by the left shoulder,
/// catch left hands` — and the shared parser declines whole-line unless it
/// fully consumes. Scoping the note-preserving leniency to the ContraDB
/// dialect keeps the shared parser's strict full-consumption behaviour
/// unchanged for every other TCB line. ContraDB defines no `trade` move at
/// all (verified against the deployed bundle); this is deliberate leniency
/// on human-typed custom prose, not a template-mirroring recognizer like the
/// other entries in this file.
FigureMatch? _tradeBy(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (!s.eatPhrase('trade by')) return null;
  s.eat('the');
  final params = <String, Object?>{'who': ?who};
  final side = _leftRight(s.peek());
  if (side != null) {
    s.take();
    if (!s.eat('shoulder')) s.eat('shoulders');
    params['shoulder'] = side;
  }
  return FigureMatch('pass_by', params: params, note: s.note());
}

/// passThroughWords: `pass through [<side> shoulders] [<dir>]`. ContraDB usually
/// renders a set direction (`across`/`along`), but real programs also render a
/// bare `pass through` (Sweet Vicki, The Hobbit) and forms whose qualifier is
/// positional rather than a direction (`by the left`, `past partners`,
/// `to next neighbors`, `to form an ocean wave with shadows`; real renders:
/// Barack Me Obamadeus, In Cahoots, Ad Vielle, The Young Adult Rose). The
/// recognised template is just `pass through` plus an optional shoulder/dir; any
/// remaining qualifier survives verbatim as the note (`dir` then defaults to the
/// taxonomy `along`).
FigureMatch? _passThrough(String text) {
  final s = _Scan(text);
  if (!s.eatPhrase('pass through')) return null;
  final params = <String, Object?>{};
  final side = _shoulderPhrase(s);
  if (side != null) params['shoulder'] = side;
  final dir = _direction(s.peek());
  if (dir != null) {
    s.take();
    params['dir'] = dir;
  }
  return FigureMatch('pass_through', params: params, note: s.note());
}

/// pullByDancersWords: `<who> [balance] pull by <hand>`.
FigureMatch? _pullByDancers(String text) {
  final s = _Scan(text);
  final who = _subject(s);
  if (who == null) return null;
  final balance = _eatBalanceAmp(s);
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
  final balance = _eatBalanceAmp(s);
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
///
/// `who` is the side that extends a hand and BACKS UP; `whom` walks forward
/// (libfigure `figure.js:844`). The trailing direction is the gate's ENDING
/// FACING (`figure.js:841` emits the literal words "to face"), stored on the
/// merged move's `face` param as of taxonomy v22 — the rotation sense and turn
/// amount ContraDB does not model stay `unspecified`.
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
  final balance = _eatBalanceAmp(s);
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

/// ContraDB's `starPromenadeWords` — the `[who] star promenade HAND ROTATION`
/// grammar — has **no recognizer here, deliberately** (taxonomy v26, #843).
///
/// ContraDB's `who`+`hand` name, as a pair, the dancers with a hand in the
/// CENTER; our `who` now names the dancer you PICK UP on the side (owner
/// ruling, 2026-08-06). The pick-up relationship is not recoverable from the
/// center role, and approximating it would assert the wrong dancers — so these
/// lines fall to the custom fallback, which keeps ContraDB's own wording
/// verbatim. This is a deliberate, owner-accepted structure regression, not an
/// oversight.
///
/// The recognizer was DELETED rather than left unregistered: it emitted a
/// `hand` param that `star_promenade` no longer declares, so re-registering it
/// would write a param the taxonomy would silently ignore. The corresponding
/// `contradb_adapter.dart` `_MoveMap` entry is likewise absent, with a comment
/// pointing here.

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

/// Parses `<subject> cross while <subject> loop [left|right]` at the current
/// [_Scan] position: consumes the matched tokens and returns
/// `{'who': …, 'hand'?: …}`, or returns `null` leaving [s] **unchanged** on
/// any mismatch.
///
/// Both dancer-set subjects must resolve via [_subject] (unknown role →
/// decline). [who] is the crossing subject; [hand] from a trailing
/// `left`/`right` when present.
///
/// **Why a shared helper.** [_boxCirculateBare] and [_boxCirculate] both parse
/// this clause. Extracting it into one site prevents silent grammar drift: two
/// parsers for one grammar will diverge — a change to one path, a doc comment
/// asserting both mirror each other, and a silent mismatch that no test catches
/// until behaviour differs. Keep the clause in one place.
///
/// **Security.** The params map is allocated only after a full match. Input is
/// already sanitised upstream; [_Scan] tokenizes on `\S+` (bounded by input
/// length) and this function reads at most ~5 tokens, returning early on the
/// first mismatch. `_subject` and `eatPhrase` do allocate internally (string
/// comparisons, `split`), but those are O(1) per token against a fixed
/// vocabulary and bounded by the input length already enforced upstream.
///
/// **Measured consequence of the guards:**
/// - Dropping the [_subject] null-check on the looping dancer would admit
///   lines whose second role is unrecognized — e.g.
///   `role1s cross while unknown loop` — turning an unknown into a structured
///   `box_circulate` with the wrong `who`.
/// - Dropping `s.eat('loop')` would match any `<subject> cross while <subject>`
///   prefix, absorbing unrelated content into the note — e.g.
///   `role1s cross while role2s - all balance` would silently become
///   `box_circulate` with note `"- all balance"`.
Map<String, Object?>? _crossWhileLoopParams(_Scan s) {
  final save = s.pos;
  final who = _subject(s);
  if (who == null) {
    s.reset(save);
    return null;
  }
  if (!s.eatPhrase('cross while')) {
    s.reset(save);
    return null;
  }
  if (_subject(s) == null) {
    s.reset(save);
    return null;
  }
  if (!s.eat('loop')) {
    s.reset(save);
    return null;
  }
  final params = <String, Object?>{'who': who};
  final hand = _leftRight(s.peek());
  if (hand != null) {
    s.take();
    params['hand'] = hand;
  }
  return params;
}

/// Bare ContraDB box-circulate form:
/// `[balance &] <subject> cross while <subject> loop [left|right]`.
///
/// ContraDB renders the component cross/loop path directly, without the
/// `box circulate` head phrase. Calls [_crossWhileLoopParams] (the shared
/// clause parser) for the cross/loop clause; mirrors [_boxCirculate]'s
/// optional `balance &` prefix so the two forms handle balance identically.
FigureMatch? _boxCirculateBare(String text) {
  final s = _Scan(text);
  final balance = _eatBalanceAmp(s);
  final clause = _crossWhileLoopParams(s);
  if (clause == null) return null;
  final params = <String, Object?>{...clause, if (balance) 'balance': true};
  return FigureMatch('box_circulate', params: params, note: s.note());
}

/// boxCirculateWords. Renders as: "[balance] box circulate - WHO cross while
/// OTHER loop HAND". Calls [_crossWhileLoopParams] (the shared clause parser)
/// for the optional `- …` clause.
FigureMatch? _boxCirculate(String text) {
  final s = _Scan(text);
  final balance = _eatBalanceAmp(s);
  if (!s.eatPhrase('box circulate')) return null;
  final params = <String, Object?>{if (balance) 'balance': true};
  final save = s.pos;
  if (s.eat('-')) {
    final clause = _crossWhileLoopParams(s);
    if (clause != null) {
      params.addAll(clause);
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
  final params = <String, Object?>{'half': ?half};
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
  final params = <String, Object?>{'who': who, 'half': ?half};
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
      params['balance'] = _eatBalanceAmp(s);
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

/// ContraDB's deployed `invertPairHash`, used only to guard the two `out`
/// branches of [_formALongWave] below (issue #945, defect B). Declining any
/// dancer set not in this table is the safe default — it is not a general
/// dancer-set inverter.
const Map<String, String> _invertPairHash = <String, String>{
  'role1s': 'role2s',
  'role2s': 'role1s',
  'ones': 'twos',
  'twos': 'ones',
  'firstCorners': 'secondCorners',
  'secondCorners': 'firstCorners',
  '*': '*',
};

/// formALongWaveWords. libfigure's deployed `figure.js` renders one of four
/// templates depending on the `in`/`out` flags:
///
///   out && in:  "`invertPair(who)` dance out while `who` dance in to a long
///                wave in the center [- balance the wave]"
///   out && !in: "`invertPair(who)` dance out [& balance]"
///   !out && in: "`who` dance in to a long wave in the center
///                [- balance the wave]" (the only branch previously
///                implemented here)
///   !out && !in: a different figure entirely ("`who` `smove` in the
///                center"), out of scope for this recognizer.
///
/// In both `out` branches, `who` (the `who` param) is the role dancing IN
/// (or, for `out && !in`, the role that *would* be "in"); the named subject
/// in the rendered text is its `invertPair` partner. Getting this backwards
/// silently swaps the roles and produces a wrong dance that still looks
/// structured, so both branches verify the named subject against
/// [_invertPairHash] and decline — falling through to the `meanwhile`
/// fan-out — rather than over-claiming arbitrary "X dance out ..." prose.
FigureMatch? _formALongWave(String text) {
  final s = _Scan(text);

  // out && in: "<named> dance out while <who> dance in to a long wave in
  // the center [- balance the wave]".
  {
    final start = s.pos;
    final named = _subject(s);
    if (named != null && s.eatPhrase('dance out while')) {
      final who = _subject(s);
      if (who != null &&
          _invertPairHash[who] == named &&
          s.eatPhrase('dance in to a long wave in the center')) {
        final params = <String, Object?>{'who': who, 'in': true, 'out': true};
        params['balance'] = s.eat('-') && s.eatPhrase('balance the wave');
        return FigureMatch('form_a_long_wave', params: params, note: s.note());
      }
    }
    s.reset(start);
  }

  // out && !in: "<named> dance out [& balance]", where <named> is the OUT
  // role and `who` is its invertPair partner (the role dancing IN).
  {
    final start = s.pos;
    final named = _subject(s);
    if (named != null && s.eatPhrase('dance out')) {
      final who = _invertPairHash[named];
      if (who != null) {
        final balance = s.eat('&') && s.eat('balance');
        if (s.peek() == null) {
          final params = <String, Object?>{
            'who': who,
            'in': false,
            'out': true,
            'balance': balance,
          };
          return FigureMatch(
            'form_a_long_wave',
            params: params,
            note: s.note(),
          );
        }
      }
    }
    s.reset(start);
  }

  // !out && in: "WHO dance in to a long wave in the center
  // [- balance the wave]" (the pre-existing, most common form).
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
///
/// ContraDB's deployed `dialectForFigures` performs a content-conditional,
/// whole-dance remap: if any figure in the dance uses the `3rd neighbors`
/// parameter, `neighbors` renders as `1st neighbors` and `next neighbors`
/// renders as `2nd neighbors` for every figure in that dance — not just the
/// one using the ordinal. Independently, if any figure uses `2nd shadows`,
/// `shadows` renders as `1st shadows` for the whole dance. The ordinal
/// entries below map those rendered forms back to their base taxonomy
/// tokens (`1st neighbors` → `neighbors`, `1st shadows` → `shadows`) so the
/// remap is transparent to every recognizer that calls `_subject`. The
/// higher ordinals (`3rd`/`4th neighbors`, `2nd shadows`) are rendered
/// unconditionally and map to their own distinct tokens, which already
/// exist in `ParamVocab.pairDancerSets` (`param_types.dart`) — no taxonomy
/// change needed. The new entries begin with distinct numeral prefixes, so
/// ordering relative to each other is not load-bearing, but they are kept
/// above the bare entries to preserve the "longest phrase first" invariant.
const List<MapEntry<String, String>> _subjectPhrases =
    <MapEntry<String, String>>[
      MapEntry('next neighbors', 'nextNeighbors'),
      MapEntry('previous neighbors', 'prevNeighbors'),
      // ContraDB renders the previous-neighbors set as `prev neighbors`
      // (libfigure abbreviation; real render: The Hobbit — `prev neighbors
      // allemande left once`). Kept ahead of the bare `neighbors` entry.
      MapEntry('prev neighbors', 'prevNeighbors'),
      MapEntry('1st neighbors', 'neighbors'),
      MapEntry('2nd neighbors', 'nextNeighbors'),
      MapEntry('3rd neighbors', 'thirdNeighbors'),
      MapEntry('4th neighbors', 'fourthNeighbors'),
      MapEntry('neighbors', 'neighbors'),
      MapEntry('partners', 'partners'),
      MapEntry('role1s', 'role1s'),
      MapEntry('role2s', 'role2s'),
      MapEntry('ones', 'ones'),
      MapEntry('twos', 'twos'),
      MapEntry('everyone', 'everyone'),
      MapEntry('1st shadows', 'shadows'),
      MapEntry('2nd shadows', 'secondShadows'),
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
