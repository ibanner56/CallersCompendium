/// The English Country Dance line parser (ADR-006, workstream W6): reads one
/// typed or imported figure line of an ECD dance into figures of the ECD
/// taxonomy ([ecdTaxonomy]), and never into contra moves.
///
/// The contra grammar (`figure_parser.dart`) follows how contra source sites
/// write calls, and its moves are contra's. Read through it, an English line
/// in an ECD dance became a contra move (`star left` → contra `star`) or, worse,
/// a contra move with a value the line never stated (`balance and swing` →
/// contra `swing` with `who = partners`). An unprefixed move in an ECD dance
/// is meant to be a contra move stored before the ECD taxonomy existed
/// (ADR-006 §5.1), so new entry must not create one. This parser is the ECD
/// counterpart: same contract, ECD vocabulary.
///
/// ## Contract (as `parseFigureLine`'s)
/// - **Parse never fails.** A line it cannot read in full becomes a custom
///   figure with [CustomOrigin.importGap] carrying the scrubbed text. It never
///   throws.
/// - **Store what the words say** (ADR-006 §5.3, R2). A value the line does not
///   state is not stored, so it reads as the taxonomy's `unspecified` (`who`
///   included, §5.2). The one exception is the ADR's own: a forward and back
///   with no distance is a double (§9.1). Every word is accounted for:
///   a word the grammar does not know makes the line custom, and so does one
///   the movement has no place to hold (dancers named both before and after
///   a turn, a ring size with no fraction, a preposition the movement does not
///   show, such as `cast to 2s`), and a bracketed aside (`(on the side)`) is kept
///   as the figure's note.
/// - **Validated** against the ECD taxonomy on its own (no contra under it),
///   so a candidate with any error-severity issue degrades to custom.
///
/// ## Grammar, in brief
/// A line is one to four steps joined by `and`, `then` or a comma; two or
/// more steps are one `sequence` (ADR-006 §5.4). A line with one `as` or
/// `while` is a `meanwhile` of its two sides (§5.6). A step is an optional
/// subject (`1s`, `1st corners`, `partners`, `1s and 2s`, a role), words that
/// come before the movement (`right hand`, `half`, `single file`), the
/// movement, and words after it (`by the left`, `once and a half`, `back to
/// place`, `with neighbor`). A subject stated on the first step and not on a
/// later one is the later step's too, as the ADR's worked example reads "1st
/// corners set forward and turn single back to place" (§8.1), except for a
/// ring movement (circle, star, chain, heys…), which more dancers dance. `and back` after
/// a star is a second star back to place (§5.4, §8.1).
///
/// Role words arrive canonical: [scrubFigureText] turns gendered terms into
/// `role1`/`role2`, and free-text entry retries a line with the dialect's own
/// role words read the same way.
library;

import '../model/bar_timing.dart';
import '../model/figure.dart';
import '../model/formation.dart';
import '../taxonomy/ecd_taxonomy.dart';
import '../validation/validation.dart';
import 'ecd_bars.dart';
import 'figure_parser.dart' show combineFigureNotes;
import 'figure_text_scrub.dart';
import 'structured_draft.dart';

/// How many dancers a ring holds in a dance of [shape], or null when the
/// shape does not settle it. ADR-006 §7.3 derives a circle's or star's
/// "half" from the ring: two places in a duple minor (four dancers), three in
/// a triple minor (six). Contra shapes an ECD dance may still carry from before
/// the ECD shapes existed are read the same way.
int? ecdRingDancers(FormationShape? shape) => switch (shape) {
  FormationShape.dupleMinor ||
  FormationShape.twoCoupleSet ||
  FormationShape.sicilianCircle ||
  FormationShape.dupleProper ||
  FormationShape.dupleImproper ||
  FormationShape.dupleIndecent ||
  FormationShape.progressedImproper ||
  FormationShape.reverseProgressionImproper ||
  FormationShape.becketCw ||
  FormationShape.becketCcw => 4,
  FormationShape.tripleMinor || FormationShape.threeCoupleLongways => 6,
  _ => null,
};

/// Upper bound on the length of a line this parser reads. Lines longer than
/// this are kept as custom text without being read (OWASP bounded input), as
/// `maxFreeTextEntryLength` bounds free-text entry.
const int maxEcdLineLength = 2000;

/// Most steps one line may hold: a sequence's cap.
const int _maxSteps = kMaxSequenceFigures;

/// Parses [rawText], one figure line of an ECD dance, into an ECD figure,
/// or a custom figure when the line is not read in full. Returns null only
/// when the line is empty after scrubbing.
///
/// [beats] is the line's count (0 when it states none). On a single figure it
/// is that figure's `beats`; on a sequence or meanwhile it is the container's
/// span, and the steps carry no timing of their own (ADR-006 §5.5). A
/// container whose line states no count takes the sum of its steps' default
/// beats, so its span is never 0.
///
/// [ringDancers] is the number of dancers in a ring for the dance's formation
/// ([ecdRingDancers]); when it is null and the line does not say, a circle's
/// or star's fraction ("half way") is kept as the figure's note and its
/// `places` stay unstated.
///
/// [scrub] is the scrub to apply (default [scrubFigureText]).
///
/// A line that starts with a bar range (`1-4 partners set`, `(5-8) …`,
/// `A1 1-4 …`, [splitEcdBarRange]) is read without it, and takes its count
/// from it over [beats] and over any count the words give: its bars times the
/// beats in a bar of [meter] ([ecdBeatsPerBar], 2 when [meter] does not say).
/// A line whose rest also states a count in beats ([ecdRestStatesBeats]) is
/// kept as custom, so that count stays in its words, and so is one that goes
/// on to further ranges (`(5-8) X (9-12) Y`), counted across all of them. A
/// line kept as custom
/// keeps its whole text, range included, and the count. A range whose count
/// is over the beats range is not taken.
Figure? parseEcdFigureLine(
  String rawText, {
  int beats = 0,
  bool progression = false,
  int? ringDancers,
  String Function(String)? scrub,
  String? meter,
  BarTiming? timing,
  int startBeat = 0,
}) {
  var safeBeats = beats < 0 ? 0 : beats;
  var lineText = rawText;
  final bars = ecdBarCount(rawText, meter: meter);
  if (bars != null) {
    // The bars are the count (Hudson: "take them and use them"), over a
    // count the line was given or a custom line kept, so a re-check counts
    // again by the dance's meter.
    safeBeats = bars.beats;
    lineText = bars.rest;
  }
  Figure fallback(String text) => customFigure(
    text,
    beats: safeBeats,
    progression: progression,
    origin: CustomOrigin.importGap,
  );
  final String scrubbed;
  try {
    scrubbed = (scrub ?? scrubFigureText)(rawText);
  } catch (_) {
    final raw = rawText.trim();
    return raw.isEmpty ? null : fallback(raw);
  }
  if (scrubbed.isEmpty) return null;
  if (scrubbed.length > maxEcdLineLength) return fallback(scrubbed);
  // A count in beats as well, or a second range (`(5-8) X (9-12) Y`, two
  // figures), is kept in the words.
  if (bars != null && (bars.several || ecdRestStatesBeats(bars.rest))) {
    return fallback(scrubbed);
  }
  try {
    final read = recognizeEcdLine(
      identical(lineText, rawText)
          ? scrubbed
          : (scrub ?? scrubFigureText)(lineText),
      beats: safeBeats,
      ringDancers: ringDancers,
    );
    if (read == null) return fallback(scrubbed);
    final counted = bars == null || read.params['beats'] == bars.beats
        ? read
        : read.copyWith(params: {...read.params, 'beats': bars.beats});
    return progression ? counted.copyWith(progression: true) : counted;
  } catch (_) {
    return fallback(scrubbed);
  }
}

/// The ECD figure [scrubbed] reads as in full, or null when it does not.
/// [scrubbed] has been through [scrubFigureText] already. See
/// [parseEcdFigureLine] for [beats] and [ringDancers]. Never throws.
Figure? recognizeEcdLine(String scrubbed, {int beats = 0, int? ringDancers}) {
  try {
    if (scrubbed.length > maxEcdLineLength) return null;
    final lexed = _lex(scrubbed);
    if (lexed == null || lexed.tokens.isEmpty) return null;
    final figure = _Reader(
      lexed.tokens,
      ringDancers: ringDancers,
    ).readLine(beats < 0 ? 0 : beats);
    if (figure == null) return null;
    if (lexed.notes.isEmpty) return figure;
    var note = figure.note;
    for (final aside in lexed.notes) {
      note = combineFigureNotes(note, aside);
    }
    return figure.copyWith(note: note);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Lexing.

final RegExp _bracketGroup = RegExp(r'\(([^()\[\]]*)\)|\[([^()\[\]]*)\]');
final RegExp _innerHyphen = RegExp(r'(?<=\w)[-‐‑](?=\w)');
final RegExp _comma = RegExp(r',');
final RegExp _spaceRun = RegExp(r'\s+');
final RegExp _edgeStops = RegExp(r'^[.!]+|[.!]+$');

/// [text] as lowercase tokens, with each bracketed aside lifted out as a note,
/// or null when the text holds something the grammar never reads: an
/// unbalanced bracket, or punctuation other than a comma and a closing stop.
({List<String> tokens, List<String> notes})? _lex(String text) {
  final notes = <String>[];
  var body = text.replaceAllMapped(_bracketGroup, (m) {
    final inner = (m.group(1) ?? m.group(2) ?? '').trim();
    if (inner.isNotEmpty) notes.add(inner);
    return ' ';
  });
  if (RegExp(r'[()\[\]{}]').hasMatch(body)) return null;
  body = body
      .toLowerCase()
      .replaceAll('½', ' 1/2 ')
      .replaceAll('¼', ' 1/4 ')
      .replaceAll('¾', ' 3/4 ')
      .replaceAll('&', ' and ')
      .replaceAll('+', ' and ')
      .replaceAll('’', "'")
      .replaceAll(_innerHyphen, ' ')
      .replaceAll(_comma, ' , ');
  final tokens = <String>[];
  for (final raw in body.split(_spaceRun)) {
    if (raw.isEmpty) continue;
    final word = raw == ',' ? raw : raw.replaceAll(_edgeStops, '');
    if (word.isEmpty) continue;
    // A word with punctuation the grammar does not read (a dash between
    // words, a colon, a quote) keeps the line out.
    if (word != ',' && !RegExp(r"^[a-z0-9/.']+$").hasMatch(word)) return null;
    tokens.add(word);
  }
  // A comma at either end states nothing.
  while (tokens.isNotEmpty && tokens.first == ',') {
    tokens.removeAt(0);
  }
  while (tokens.isNotEmpty && tokens.last == ',') {
    tokens.removeLast();
  }
  return (tokens: tokens, notes: notes);
}

// ---------------------------------------------------------------------------
// Vocabulary.

/// Ordinals as callers write them, to the couple number.
const Map<String, int> _ordinals = {
  '1st': 1,
  'first': 1,
  '2nd': 2,
  'second': 2,
  '3rd': 3,
  'third': 3,
  '4th': 4,
  'fourth': 4,
  '5th': 5,
  'fifth': 5,
};

/// Small counts, as words or digits.
const Map<String, int> _counts = {
  '1': 1,
  'one': 1,
  '2': 2,
  'two': 2,
  '3': 3,
  'three': 3,
  '4': 4,
  'four': 4,
  '5': 5,
  'five': 5,
  '6': 6,
  'six': 6,
  '7': 7,
  'seven': 7,
  '8': 8,
  'eight': 8,
  '9': 9,
  'nine': 9,
  '10': 10,
  'ten': 10,
};

const List<String> _coupleTokens = ['ones', 'twos', 'threes', 'fours', 'fives'];

/// One- and two-word dancer phrases, to the ECD selector each names
/// (ADR-006 §6.2). Longer phrases are tried first. Couples by number,
/// singles (`1st role2`) and the neighbour series are read by
/// [_Reader.dancerAt] rather than listed.
final Map<String, String> _dancerPhrases = {
  'all': 'everyone',
  'everyone': 'everyone',
  'everybody': 'everyone',
  'all dancers': 'everyone',
  'partners': 'partners',
  'partner': 'partners',
  'your partner': 'partners',
  'ptnr': 'partners',
  'ptnrs': 'partners',
  'neighbors': 'neighbors',
  'neighbor': 'neighbors',
  'neighbours': 'neighbors',
  'neighbour': 'neighbors',
  'your neighbor': 'neighbors',
  'your neighbour': 'neighbors',
  'nbr': 'neighbors',
  'nbrs': 'neighbors',
  'corners': 'corners',
  'corner': 'corners',
  'your corner': 'corners',
  'long corners': 'longCorners',
  'first corners': 'firstCorners',
  'first corner': 'firstCorners',
  '1st corners': 'firstCorners',
  '1st corner': 'firstCorners',
  'second corners': 'secondCorners',
  'second corner': 'secondCorners',
  '2nd corners': 'secondCorners',
  '2nd corner': 'secondCorners',
  'first diagonals': 'firstDiagonals',
  '1st diagonals': 'firstDiagonals',
  'second diagonals': 'secondDiagonals',
  '2nd diagonals': 'secondDiagonals',
  'shadows': 'shadows',
  'shadow': 'shadows',
  'second shadows': 'secondShadows',
  'second shadow': 'secondShadows',
  'same roles': 'sameRoles',
  'role1s': 'role1s',
  'role1': 'role1s',
  'role2s': 'role2s',
  'role2': 'role2s',
  'top couple': 'top',
  'top': 'top',
  'bottom couple': 'bottom',
  'bottom': 'bottom',
  'ends': 'ends',
  'end couples': 'ends',
  'middles': 'middles',
  'middle couple': 'middles',
  'middle couples': 'middles',
  'centers': 'centers',
  'centres': 'centers',
  'actives': 'actives',
  'active couples': 'actives',
  'active couple': 'actives',
  'couples': 'couples',
  'side couples': 'sideCouples',
  'left file': 'leftFile',
  'right file': 'rightFile',
  'prev neighbors': 'prevNeighbors',
  'previous neighbors': 'prevNeighbors',
  'next neighbors': 'nextNeighbors',
  'next neighbor': 'nextNeighbors',
  'third neighbors': 'thirdNeighbors',
  'fourth neighbors': 'fourthNeighbors',
  'prev partners': 'prevPartners',
  'next partners': 'nextPartners',
};

/// Where a stated destination is written (ADR-006 §6.4). Longer phrases are
/// tried first.
final Map<String, String> _destinationPhrases = {
  'back to place': 'place',
  'back to places': 'place',
  'back to your place': 'place',
  'to place': 'place',
  'to places': 'place',
  'into place': 'place',
  'home': 'place',
  'back home': 'place',
  'to progressed place': 'progressedPlace',
  'to progressed places': 'progressedPlace',
  'to your progressed place': 'progressedPlace',
  'to progressed position': 'progressedPlace',
  'into progressed place': 'progressedPlace',
  'into progressed places': 'progressedPlace',
  'progressed': 'progressedPlace',
  'to original places': 'originalPlaces',
  'to original place': 'originalPlaces',
  'all home': 'originalPlaces',
  "to partner's place": 'partnersPlace',
  "into partner's place": 'partnersPlace',
  "to neighbor's place": 'neighborsPlace',
  "into neighbor's place": 'neighborsPlace',
  "to neighbour's place": 'neighborsPlace',
  "to diagonal's place": 'diagonalsPlace',
  'all improper': 'allImproper',
  'ending improper': 'allImproper',
  'to end improper': 'allImproper',
  'end improper': 'allImproper',
  'all proper': 'allProper',
  'ending proper': 'allProper',
  // The ends of the set, which only a cast takes (ADR-006 §9.4). "The top"
  // is never a dancer phrase, so no other movement's line reads differently;
  // a bare `to top`/`to bottom` reaches a cast as dancers instead.
  'to the top': 'top',
  'to the bottom': 'bottom',
  'to end proper': 'allProper',
  'end proper': 'allProper',
  for (final MapEntry(key: word, value: n) in _ordinals.entries)
    if (n <= 5) ...{
      'to $word place': _placeName(n),
      'into $word place': _placeName(n),
      'to $word position': _placeName(n),
    },
};

String _placeName(int n) => const [
  'firstPlace',
  'secondPlace',
  'thirdPlace',
  'fourthPlace',
  'fifthPlace',
  'sixthPlace',
][n - 1];

/// Amounts of a turn or a figure, as fractions of a whole one. Longer
/// phrases are tried first.
final Map<String, double> _amountPhrases = {
  'a quarter': 0.25,
  'quarter': 0.25,
  '1/4': 0.25,
  'quarter way': 0.25,
  '1/4 way': 0.25,
  'half': 0.5,
  'a half': 0.5,
  'halfway': 0.5,
  'half way': 0.5,
  '1/2': 0.5,
  '1/2 way': 0.5,
  'three quarters': 0.75,
  'three quarter': 0.75,
  '3/4': 0.75,
  '3/4 way': 0.75,
  'once': 1,
  'once round': 1,
  'once around': 1,
  'one full turn': 1,
  'all the way': 1,
  'all the way round': 1,
  'all the way around': 1,
  'full': 1,
  'whole': 1,
  '1x': 1,
  'one and a half': 1.5,
  'once and a half': 1.5,
  '1 and a half': 1.5,
  '1 1/2': 1.5,
  '1.5': 1.5,
  '1.5x': 1.5,
  '1 1/4': 1.25,
  'one and a quarter': 1.25,
  '1 3/4': 1.75,
  'one and three quarters': 1.75,
  'twice': 2,
  'twice round': 2,
  'twice around': 2,
  '2x': 2,
};

/// Side words: a bare `right` or `left`, whose parameter depends on the
/// movement ([_MoveRule.side]).
const Map<String, String> _sideWords = {
  'right': 'right',
  'r': 'right',
  'left': 'left',
  'l': 'left',
};

const Map<String, String> _spinPhrases = {
  'clockwise': 'clockwise',
  'cw': 'clockwise',
  'counterclockwise': 'counterclockwise',
  'counter clockwise': 'counterclockwise',
  'anticlockwise': 'counterclockwise',
  'anti clockwise': 'counterclockwise',
  'ccw': 'counterclockwise',
  'acw': 'counterclockwise',
};

const Map<String, String> _wherePhrases = {
  'up': 'up',
  'up the set': 'up',
  'up the hall': 'up',
  'down': 'down',
  'down the set': 'down',
  'down the hall': 'down',
  'forward': 'forward',
  'forwards': 'forward',
  'advancing': 'forward',
  'moving forward': 'forward',
  'across': 'across',
  'across the set': 'across',
  'along': 'along',
  'along the set': 'along',
  'along the line': 'along',
  'diagonally': 'diagonally',
  'on the diagonal': 'diagonally',
  'back': 'back',
  'out': 'out',
  'to the middle': 'toTheMiddle',
  'into the middle': 'toTheMiddle',
  'off': 'off',
  'around': 'around',
  'round': 'around',
};

const Map<String, String> _facingWords = {
  'up': 'up',
  'down': 'down',
  'in': 'in',
  'out': 'out',
};

const Map<String, String> _styleWords = {
  'straight': 'straight',
  'sharp': 'straight',
  'swirly': 'swirly',
  'playford': 'swirly',
  'push': 'push',
  'pushing': 'push',
  'draw': 'draw',
  'drawing': 'draw',
  'slipping': 'slipping',
  'skipping': 'skipping',
};

const Set<String> _boundaryWords = {',', 'and', 'then', 'as', 'while'};

/// The movements that read `and back` as their own return (`goBack`). After
/// any other movement, `and back` is a step of its own ([_Reader.readReturn]).
const Set<String> _goesBack = {'forward_and_back', 'galop'};

// ---------------------------------------------------------------------------
// Movements.

/// What one step states, slot by slot, before it is mapped onto a movement's
/// parameters. A slot is set once; a second statement of the same slot makes
/// the step unreadable. Every slot that is set must be read by the movement
/// ([_Bag.take]), or the step is unreadable: no word is dropped.
class _Bag {
  final Map<String, Object> _slots = {};
  final Set<String> _taken = {};

  bool has(String slot) => _slots.containsKey(slot);

  /// Sets [slot], or returns false when it is set already.
  bool put(String slot, Object value) {
    if (_slots.containsKey(slot)) return false;
    _slots[slot] = value;
    return true;
  }

  T? take<T>(String slot) {
    final value = _slots[slot];
    if (value == null) return null;
    _taken.add(slot);
    return value as T;
  }

  /// Marks [slot] read without using it.
  void drop(String slot) => _taken.add(slot);

  bool get allTaken => _slots.keys.every(_taken.contains);
}

/// The parameter map a movement builds from a step's [_Bag], or null when the
/// step states something the movement cannot hold.
typedef _Build = Map<String, Object?>? Function(_Bag bag, _Context context);

class _Context {
  const _Context({required this.ringDancers});
  final int? ringDancers;
}

class _MoveRule {
  const _MoveRule(this.id, this.build);
  final String id;
  final _Build build;
}

/// The phrases that name a movement, each with the slots the phrase itself
/// states (`up a double` states `where` and `distance`). Matched longest
/// first at the point a step's movement is expected.
typedef _VerbPhrase = ({
  List<String> words,
  String rule,
  Map<String, Object> preset,
});

_VerbPhrase _v(
  String words,
  String rule, [
  Map<String, Object> preset = const {},
]) => (words: words.split(' '), rule: rule, preset: preset);

final List<_VerbPhrase> _verbPhrases = [
  _v('set and link', 'set_and_link'),
  _v('set', 'set'),
  _v('honor', 'honor'),
  _v('honour', 'honor'),
  _v('step and honor', 'honor'),
  _v('step and honour', 'honor'),
  _v('bow', 'honor'),
  _v('clap', 'clap'),
  _v('turn single', 'turn_single'),
  _v('cloverleaf turn single', 'turn_single', {'cloverleaf': true}),
  _v('turn alone', 'turn_alone'),
  _v('hand turn', 'turn'),
  _v('turn', 'turn'),
  _v('two hand turn', 'turn', {'hand': 'two'}),
  _v('arm turn', 'arm_turn'),
  _v('arm', 'arm_turn'),
  _v('shoulder round', 'shoulder_round'),
  _v('gyre', 'shoulder_round'),
  _v('swing', 'swing'),
  _v('box the gnat', 'box_the_gnat'),
  _v('swat the flea', 'swat_the_flea'),
  _v('gate', 'gate'),
  _v('hand cast', 'hand_cast'),
  _v('orbit', 'orbit'),
  _v('mad robin', 'mad_robin'),
  _v('balance', 'balance'),
  _v('balance the ring', 'balance_ring'),
  _v('balance in a ring', 'balance_ring'),
  _v('petronella', 'petronella'),
  _v('petronella turn', 'petronella'),
  _v('circle', 'circle'),
  _v('ring', 'circle'),
  _v('chase', 'circle', {'singleFile': true}),
  _v('slip', 'circle', {'style': 'slipping'}),
  _v('star', 'star'),
  _v('hands across', 'star'),
  _v('hand across', 'star'),
  _v('form short waves', 'form_short_wave'),
  _v('form a short wave', 'form_short_wave'),
  _v('form long waves', 'form_long_wave'),
  _v('form long wave', 'form_long_wave'),
  _v('circular hey', 'circular_hey'),
  _v('square hey', 'circular_hey'),
  _v('rights and lefts', 'rights_and_lefts'),
  _v('right and left', 'rights_and_lefts'),
  _v('r and l', 'rights_and_lefts'),
  _v('chain', 'chain'),
  _v('figure eight', 'figure_eight'),
  _v('figure 8', 'figure_eight'),
  _v('figure of eight', 'figure_eight'),
  _v('figure of 8', 'figure_eight'),
  _v('fig 8', 'figure_eight'),
  _v('fig eight', 'figure_eight'),
  _v('dolphin hey', 'dolphin_hey'),
  _v('hey for three', 'hey_for_three'),
  _v('hey for 3', 'hey_for_three'),
  _v('hey of three', 'hey_for_three'),
  _v('reel of three', 'hey_for_three'),
  _v('reel of 3', 'hey_for_three'),
  _v('hey for four', 'hey_for_four'),
  _v('hey for 4', 'hey_for_four'),
  _v('hey of four', 'hey_for_four'),
  _v('reel of four', 'hey_for_four'),
  _v('reel of 4', 'hey_for_four'),
  _v('straight hey', 'hey_for_four'),
  _v('hey for six', 'hey_for_six'),
  _v('hey for 6', 'hey_for_six'),
  _v('reel of six', 'hey_for_six'),
  _v('tandem reel', 'tandem_reel'),
  _v('shetland reel', 'tandem_reel'),
  _v('mirror hey', 'mirror_hey'),
  _v('mirror heys', 'mirror_hey'),
  _v('grimstock hey', 'mirror_hey'),
  _v('grand chain', 'grand_chain'),
  _v('cross', 'cross'),
  _v('cross over', 'cross'),
  _v('right and left through', 'right_left_through'),
  _v('right left through', 'right_left_through'),
  _v('fall back', 'fall_back'),
  _v('forward and back', 'forward_and_back', {'goBack': true}),
  _v('forward', 'forward_and_back', {'where': 'forward'}),
  // `up` or `down` alone is a direction of travel (`robin up, lark down`),
  // so it names a forward and back only with its distance.
  for (final where in const ['up', 'down'])
    for (final distance in const ['double', 'single'])
      _v('$where a $distance', 'forward_and_back', {
        'where': where,
        'distance': distance,
      }),
  _v('back to back', 'back_to_back'),
  _v('siding', 'siding'),
  _v('side', 'siding'),
  _v('sharp siding', 'siding', {'style': 'straight'}),
  _v('playford siding', 'siding', {'style': 'swirly'}),
  _v('pass through', 'pass_through'),
  _v('promenade', 'promenade'),
  _v('poussette', 'poussette'),
  _v('draw poussette', 'poussette', {'style': 'draw'}),
  _v('arch', 'arch'),
  _v('make an arch', 'arch'),
  _v('roll away', 'rollaway'),
  _v('rollaway', 'rollaway'),
  _v('change places', 'change_places'),
  _v('change', 'change_places'),
  _v('trade places', 'change_places'),
  _v('pull by', 'pull_by'),
  _v('contra corners', 'contra_corners'),
  _v('turn contra corners', 'contra_corners'),
  _v('lead', 'lead'),
  _v('cast', 'cast'),
  _v('cast off', 'cast', {'where': 'off'}),
  _v('galop', 'galop'),
  _v('gallop', 'galop'),
  _v('chevron', 'chevron'),
  _v('pothooks', 'chevron'),
]..sort((a, b) => b.words.length.compareTo(a.words.length));

/// The parameter `who` holds for a step, from its subject (or, for a movement
/// with no `whom`, the dancers it names after the movement).
///
/// A step that names dancers both before and after such a movement (`1s turn
/// 2s`) has no place to hold both, so it is unreadable ([_fail]).
Object? _whoOf(_Bag bag, {bool objectIsWho = true}) {
  final subject = bag.take<List<String>>('who');
  if (objectIsWho) {
    final object = bag.take<List<String>>('object');
    if (subject != null && object != null) return _fail;
    return subject ?? object;
  }
  return subject;
}

/// A step's dancers as the movement's single `whom` set.
String? _single(List<String>? dancers) =>
    dancers == null || dancers.length != 1 ? null : dancers.single;

/// Whether [bag] stated something that [build] could not hold: `null` from a
/// builder means the step is unreadable.
const Object _fail = Object();

Map<String, Object?>? _params(Map<String, Object?> stated) {
  if (stated.values.contains(_fail)) return null;
  return {
    for (final entry in stated.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}

/// The value [slot] holds as one of [allowed], `null` when the slot is not
/// stated, or [_fail] when it holds another value.
Object? _oneOf(_Bag bag, String slot, Iterable<String> allowed) {
  final value = bag.take<Object>(slot);
  if (value == null) return null;
  return value is String && allowed.contains(value) ? value : _fail;
}

/// A turn amount as the ECD taxonomy's rotation (quarter steps, 0.25–2.5).
Object? _travel(_Bag bag) {
  final amount = bag.take<double>('amount');
  if (amount == null) return null;
  return amount >= 0.25 && amount <= 2.5 && (amount * 4) % 1 == 0
      ? amount
      : _fail;
}

/// An amount as the ECD `fraction` choice.
Object? _fraction(_Bag bag) {
  final amount = bag.take<double>('amount');
  if (amount == null) return null;
  return switch (amount) {
    0.25 => 'quarter',
    0.5 => 'half',
    0.75 => 'threeQuarter',
    1.0 => 'full',
    _ => _fail,
  };
}

/// The side a bare `right`/`left` names, when the movement reads it as
/// [param]: the param's value, merged with any explicit statement of the same
/// param in [explicit].
///
/// A side stated as `to the right` names a way to travel, never a hand or a
/// shoulder, so it is unreadable ([_fail]) unless [toTheAllowed].
Object? _sideAs(_Bag bag, String explicit, {bool toTheAllowed = true}) {
  final toThe = bag.take<bool>('sideToThe') == true;
  final side = bag.take<String>('side');
  if (toThe && !toTheAllowed && side != null) return _fail;
  final stated = bag.take<String>(explicit);
  if (side != null && stated != null) return _fail;
  return side ?? stated;
}

Object? _hand(
  _Bag bag, {
  bool sideIsHand = true,
  Set<String> allowed = const {'right', 'left'},
}) {
  final hand = sideIsHand
      ? _sideAs(bag, 'hand', toTheAllowed: false)
      : bag.take<String>('hand');
  if (hand == null || hand == _fail) return hand;
  return allowed.contains(hand) ? hand : _fail;
}

Object? _shoulder(
  _Bag bag, {
  bool sideIsShoulder = true,
  bool toTheAllowed = false,
}) {
  final value = sideIsShoulder
      ? _sideAs(bag, 'shoulder', toTheAllowed: toTheAllowed)
      : bag.take<String>('shoulder');
  if (value == null || value == _fail) return value;
  return value == 'right' || value == 'left' ? value : _fail;
}

Object? _where(_Bag bag, List<String> allowed) => _oneOf(bag, 'where', allowed);

/// A gate's params, for `gate` and its other name, `hand cast`. Dancers named
/// straight after the movement: no preposition reads as its `whom`.
Map<String, Object?>? _gateParams(_Bag b, _Context c) {
  final gated = _objectOrWhom(
    b.take<List<String>>('object'),
    _whomVia(b, const <String>{}),
  );
  return _params({
    'who': b.take<List<String>>('who'),
    'whom': gated,
    'direction': b.take<String>('spin'),
    'travel': _travel(b),
    'endFacing': b.take<String>('endFacing'),
    'destination': _dest(b),
  });
}

/// The dancers a step names after a preposition, when the movement reads
/// that preposition as its `whom` ([via]); [_fail] for any other preposition,
/// since each movement shows `whom` with its own word ("around", "through",
/// "with") and another would change what the line says.
Object? _whomVia(_Bag bag, Set<String> via) {
  final whom = bag.take<List<String>>('whom');
  final word = bag.take<String>('whomVia');
  if (whom == null) return null;
  if (word == null || !via.contains(word)) return _fail;
  return whom;
}

/// [_whomVia] as the movement's single `whom` set.
Object? _whom(_Bag bag, Set<String> via) {
  final whom = _whomVia(bag, via);
  if (whom is! List<String>) return whom;
  return _single(whom) ?? _fail;
}

/// [object] (dancers named straight after the movement) or [via] (after a
/// preposition), as one single `whom` set: [_fail] when both are stated.
Object? _objectOrWhom(List<String>? object, Object? via) {
  if (via == _fail || (object != null && via != null)) return _fail;
  final whom = object ?? via as List<String>?;
  return whom == null ? null : (_single(whom) ?? _fail);
}

Object? _flag(_Bag bag, String slot) =>
    bag.take<bool>(slot) == true ? true : null;

Object? _dest(_Bag bag) => bag.take<String>('destination');

/// `places` for a ring of [ring] dancers from a stated count of places or a
/// fraction of the ring (ADR-006 §7.3), or the fraction's words as a note
/// (the figure's note) when the ring is not known.
({Object? places, String? note}) _places(_Bag bag, int? ring) {
  final count = bag.take<int>('placeCount');
  final amount = bag.take<double>('amount');
  final words = bag.take<String>('amountWords');
  if (count != null && amount != null) return (places: _fail, note: null);
  if (count != null) return (places: count, note: null);
  if (amount == null) return (places: null, note: null);
  if (ring == null) return (places: null, note: words);
  final places = amount * ring;
  if (places % 1 != 0 || places < 1 || places > 10) {
    return (places: _fail, note: null);
  }
  return (places: places.toInt(), note: null);
}

/// The ring a circle or star is danced in: a ring size the line states, the
/// couples its subject names, or the dance's formation. [stated] is true for
/// a stated size, which the movement holds only through the places it turns
/// (ADR-006 §7.3), so a stated size with no fraction to work out is not read.
({int? ring, bool stated}) _ringOf(Object? who, _Bag bag, _Context context) {
  final stated = bag.take<int>('ringSize');
  if (stated != null) return (ring: stated, stated: true);
  if (who is List<String> &&
      who.isNotEmpty &&
      who.every(_coupleTokens.contains)) {
    return (ring: who.length * 2, stated: false);
  }
  return (ring: context.ringDancers, stated: false);
}

final Map<String, _MoveRule> _rules = {
  'set_and_link': _MoveRule('ecd_set_and_link', (b, c) {
    // Everyone sets and links (§7.1), so an "all" adds nothing to hold.
    final who = b.take<List<String>>('who');
    if (who != null && !(who.length == 1 && who.single == 'everyone')) {
      return null;
    }
    return const {};
  }),
  'set': _MoveRule(
    'ecd_set',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'to'}),
      'where': _where(b, const ['forward', 'along', 'across']),
      'direction': _sideAs(b, 'direction'),
    }),
  ),
  'honor': _MoveRule('ecd_honor', (b, c) {
    final subject = b.take<List<String>>('who');
    final object = b.take<List<String>>('object');
    return _params({
      'who': subject,
      'whom': _objectOrWhom(object, _whomVia(b, const {'to'})),
    });
  }),
  'clap': _MoveRule('ecd_clap', (b, c) => const {}),
  'turn_single': _MoveRule('ecd_turn_single', (b, c) {
    final cloverleaf = b.take<bool>('cloverleaf') == true;
    // A turn single's side is the side turned to: `to the right` names it.
    final shoulder = _shoulder(b, toTheAllowed: true);
    if (cloverleaf && shoulder != null) return null;
    return _params({
      'who': _whoOf(b, objectIsWho: false),
      'shoulder': cloverleaf ? 'cloverleaf' : shoulder,
      'destination': _dest(b),
    });
  }),
  'turn_alone': _MoveRule(
    'ecd_turn_alone',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'destination': _dest(b),
    }),
  ),
  'arm_turn': _MoveRule(
    'ecd_arm_turn',
    (b, c) => _params({
      'who': _whoOf(b),
      'hand': _hand(b),
      'travel': _travel(b),
      'endFacing': b.take<String>('endFacing'),
      'destination': _dest(b),
    }),
  ),
  'shoulder_round': _MoveRule(
    'ecd_shoulder_round',
    (b, c) => _params({
      'who': _whoOf(b),
      'shoulder': _shoulder(b),
      'travel': _travel(b),
      'destination': _dest(b),
    }),
  ),
  'swing': _MoveRule(
    'ecd_swing',
    (b, c) => _params({
      'who': _whoOf(b),
      'endFacing': b.take<String>('endFacing'),
      'destination': _dest(b),
    }),
  ),
  'box_the_gnat': _MoveRule(
    'ecd_box_the_gnat',
    (b, c) => _params({
      'who': _whoOf(b),
      'balance': _flag(b, 'balance'),
      'destination': _dest(b),
    }),
  ),
  'swat_the_flea': _MoveRule(
    'ecd_swat_the_flea',
    (b, c) => _params({
      'who': _whoOf(b),
      'balance': _flag(b, 'balance'),
      'destination': _dest(b),
    }),
  ),
  'gate': _MoveRule('ecd_gate', _gateParams),
  // A gate by its other name, stored under its own ID (ADR-006 §9.4).
  'hand_cast': _MoveRule('ecd_hand_cast', _gateParams),
  'orbit': _MoveRule(
    'ecd_orbit',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'around'}),
      'direction': b.take<String>('spin'),
      'travel': _travel(b),
      'destination': _dest(b),
    }),
  ),
  'mad_robin': _MoveRule(
    'ecd_mad_robin',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'around'}),
      'direction': b.take<String>('spin'),
      'travel': _travel(b),
      'destination': _dest(b),
    }),
  ),
  'balance': _MoveRule(
    'ecd_balance',
    (b, c) => _params({
      'who': _whoOf(b),
      'where': _where(b, const ['forward', 'along', 'across', 'diagonally']),
      'hand': _hand(b),
    }),
  ),
  'balance_ring': _MoveRule('ecd_balance_ring', (b, c) => const {}),
  'petronella': _MoveRule(
    'ecd_petronella',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'places': b.take<int>('placeCount'),
      'direction': _sideAs(b, 'direction'),
      'destination': _dest(b),
    }),
  ),
  'circle': _MoveRule('ecd_circle', (b, c) {
    final who = _whoOf(b, objectIsWho: false);
    final ring = _ringOf(who, b, c);
    final places = _places(b, ring.ring);
    // `circle six` with no fraction: the size has nowhere to go.
    if (ring.stated && places.places == null) return null;
    final spin = b.take<String>('spin');
    final side = _sideAs(b, 'direction');
    if (spin != null && side != null) return null;
    final singleFile = b.take<bool>('singleFile') == true;
    final params = _params({
      'who': who,
      'direction': spin ?? side,
      'places': places.places,
      'singleFile': singleFile ? true : null,
      'step': _oneOf(b, 'style', const ['slipping', 'skipping']),
      'destination': _dest(b),
    });
    if (params == null) return null;
    return {...params, if (places.note != null) _noteSlot: places.note};
  }),
  'star': _MoveRule('ecd_star', (b, c) {
    final who = _whoOf(b, objectIsWho: false);
    final ring = _ringOf(who, b, c);
    final places = _places(b, ring.ring);
    // `circle six` with no fraction: the size has nowhere to go.
    if (ring.stated && places.places == null) return null;
    final params = _params({
      'who': who,
      'hand': _hand(b),
      'places': places.places,
      'destination': _dest(b),
    });
    if (params == null) return null;
    return {...params, if (places.note != null) _noteSlot: places.note};
  }),
  'form_short_wave': _MoveRule(
    'ecd_form_short_wave',
    (b, c) => _params({
      'axis': _where(b, const ['along', 'across']),
      'balance': _flag(b, 'balance'),
    }),
  ),
  'form_long_wave': _MoveRule(
    'ecd_form_long_wave',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'with'}),
      'balance': _flag(b, 'balance'),
    }),
  ),
  'circular_hey': _MoveRule(
    'ecd_circular_hey',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const <String>{}),
      'slow': _flag(b, 'slow'),
      'changes': b.take<int>('changes'),
      'where': _where(b, const ['along', 'across', 'diagonally']),
      'shoulder': _shoulder(b, sideIsShoulder: false),
      'destination': _dest(b),
    }),
  ),
  'rights_and_lefts': _MoveRule(
    'ecd_rights_and_lefts',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'starting with'}),
      'slow': _flag(b, 'slow'),
      'changes': b.take<int>('changes'),
      'where': _where(b, const ['along', 'across', 'diagonally']),
      'hand': _hand(b, sideIsHand: false),
      'destination': _dest(b),
    }),
  ),
  'chain': _MoveRule(
    'ecd_chain',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'hand': _hand(b),
      'where': _where(b, const ['along', 'across', 'diagonally']),
      'open': _flag(b, 'open'),
      'destination': _dest(b),
    }),
  ),
  'figure_eight': _MoveRule(
    'ecd_figure_eight',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'through'}),
      'where': _where(b, const ['up', 'down', 'across']),
      'fraction': _fraction(b),
      'double': _flag(b, 'double'),
      'destination': _dest(b),
    }),
  ),
  for (final hey in const [
    'dolphin_hey',
    'hey_for_three',
    'hey_for_four',
    'hey_for_six',
  ])
    hey: _MoveRule(
      'ecd_$hey',
      (b, c) => _params({
        'who': _whoOf(b, objectIsWho: false),
        'whom': _whom(b, const <String>{}),
        'shoulder': _shoulder(b, sideIsShoulder: false),
        'where': _where(b, const ['along', 'across', 'diagonally']),
        'fraction': _fraction(b),
        'destination': _dest(b),
      }),
    ),
  'tandem_reel': _MoveRule(
    'ecd_tandem_reel',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'with'}),
      'shoulder': _shoulder(b, sideIsShoulder: false),
      'where': _where(b, const ['along', 'across', 'diagonally']),
      'destination': _dest(b),
    }),
  ),
  'mirror_hey': _MoveRule(
    'ecd_mirror_hey',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const <String>{}),
      'fraction': _fraction(b),
      'destination': _dest(b),
    }),
  ),
  'grand_chain': _MoveRule(
    'ecd_grand_chain',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'starting with'}),
      'changes': b.take<int>('changes'),
      'hand': _hand(b, sideIsHand: false),
      'destination': _dest(b),
    }),
  ),
  'cross': _MoveRule(
    'ecd_cross',
    (b, c) => _params({
      'who': _whoOf(b),
      'shoulder': _shoulder(b, sideIsShoulder: false),
      'where': _where(b, const ['diagonally', 'along', 'across', 'up', 'down']),
      'endFacing': b.take<String>('endFacing'),
      'destination': _dest(b),
    }),
  ),
  'right_left_through': _MoveRule(
    'ecd_right_left_through',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'where': _where(b, const ['along', 'across', 'diagonally']),
      'destination': _dest(b),
    }),
  ),
  'fall_back': _MoveRule(
    'ecd_fall_back',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'with'}),
      'where': _where(b, const ['across', 'along', 'diagonally', 'up', 'down']),
      'distance': b.take<String>('distance'),
      'destination': _dest(b),
    }),
  ),
  'forward_and_back': _MoveRule(
    'ecd_forward_and_back',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'where': _where(b, const ['up', 'down', 'forward']),
      // A bare `lines` is the movement's own (§7.5): it states no formation.
      'formation': (b..drop('lines')).take<String>('formation'),
      // A double when the line gives no distance: the one exception to R2
      // (ADR-006 §9.1 point 3), stored so it never reads as unstated.
      'distance': b.take<String>('distance') ?? 'double',
      'goBack': _flag(b, 'goBack'),
    }),
  ),
  'back_to_back': _MoveRule(
    'ecd_back_to_back',
    (b, c) => _params({
      'who': _whoOf(b),
      'shoulder': _shoulder(b),
      'travel': _travel(b),
      'where': _where(b, const ['across', 'along']),
      'destination': _dest(b),
    }),
  ),
  'siding': _MoveRule(
    'ecd_siding',
    (b, c) => _params({
      'who': _whoOf(b),
      'shoulder': _shoulder(b),
      'where': _where(b, const ['across', 'along']),
      'style': _oneOf(b, 'style', const ['straight', 'swirly']),
      'destination': _dest(b),
    }),
  ),
  'pass_through': _MoveRule(
    'ecd_pass_through',
    (b, c) => _params({
      'who': _whoOf(b),
      'where': _where(b, const ['along', 'across', 'diagonally', 'up', 'down']),
      'shoulder': _shoulder(b, sideIsShoulder: false),
      'destination': _dest(b),
    }),
  ),
  'promenade': _MoveRule('ecd_promenade', (b, c) {
    final singleFile = b.take<bool>('singleFile') == true;
    return _params({
      'who': _whoOf(b),
      'where': _where(b, const ['along', 'across', 'up', 'down']),
      'direction': b.take<String>('spin'),
      'fraction': _fraction(b),
      'places': b.take<int>('placeCount'),
      'singleFile': singleFile ? true : null,
      'destination': _dest(b),
    });
  }),
  'poussette': _MoveRule('ecd_poussette', (b, c) {
    // `who` names the dancers who push or draw (§7.5), so only the dancers
    // named with "push"/"draw" after the movement are held there. A subject
    // before it names who dances, not who pushes: "all" adds nothing, as for
    // set and link, and any other subject is not read (R2).
    final subject = b.take<List<String>>('who');
    if (subject != null &&
        !(subject.length == 1 && subject.single == 'everyone')) {
      return null;
    }
    return _params({
      'who': b.take<List<String>>('styleWho'),
      'whom': _whom(b, const {'with'}),
      'fraction': _fraction(b),
      'direction': b.take<String>('spin'),
      'style': _oneOf(b, 'style', const ['push', 'draw']),
      'destination': _dest(b),
    });
  }),
  'arch': _MoveRule(
    'ecd_arch',
    (b, c) => _params({'who': _whoOf(b, objectIsWho: false)}),
  ),
  'rollaway': _MoveRule('ecd_rollaway', (b, c) {
    // Dancers named straight after the movement: no preposition reads as its
    // `whom`.
    final rolled = _objectOrWhom(
      b.take<List<String>>('object'),
      _whomVia(b, const <String>{}),
    );
    return _params({
      'who': b.take<List<String>>('who'),
      'whom': rolled,
      'where': _where(b, const ['along', 'across', 'up', 'down']),
      'halfSashay': _flag(b, 'halfSashay'),
      'destination': _dest(b),
    });
  }),
  'change_places': _MoveRule(
    'ecd_change_places',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'whom': _whom(b, const {'with'}),
      'hand': _hand(
        b,
        // `change R`: the side is the hand, as for a turn.
        allowed: const {'right', 'left', 'none'},
      ),
      'where': _where(b, const ['along', 'across', 'diagonally', 'up', 'down']),
      'destination': _dest(b),
    }),
  ),
  'pull_by': _MoveRule('ecd_pull_by', (b, c) {
    // Dancers named straight after the movement: no preposition reads as its
    // `whom`.
    final passed = _objectOrWhom(
      b.take<List<String>>('object'),
      _whomVia(b, const <String>{}),
    );
    return _params({
      'who': b.take<List<String>>('who'),
      'whom': passed,
      'hand': _hand(b),
      'where': _where(b, const ['along', 'across', 'diagonally']),
      'destination': _dest(b),
    });
  }),
  'contra_corners': _MoveRule(
    'ecd_contra_corners',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'destination': _dest(b),
    }),
  ),
  'lead': _MoveRule(
    'ecd_lead',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'where': _where(b, const ['up', 'down', 'out', 'toTheMiddle', 'back']),
      'whom': _whom(b, const {'through'}),
      'destination': _dest(b),
    }),
  ),
  // A cast's `direction` is up, down, or the shoulder turned over (ADR-006
  // §9.4): a bare `left`/`right`, never `to the left`, which is a way to
  // travel. `back` is how a cast with no `up` or `down` reads ("cast back
  // left"), so it states nothing. "Cast off" is down one place unless the
  // line states a count or where the cast ends.
  'cast': _MoveRule('ecd_cast', (b, c) {
    final who = _whoOf(b, objectIsWho: false);
    final where = _where(b, const ['off', 'up', 'down', 'back']);
    // `clockwise` is over the right shoulder, `counterclockwise` the left
    // (the maintainer's mapping). A role never implies one (§9.4).
    final side = _sideAs(b, 'direction', toTheAllowed: false);
    final spin = switch (b.take<String>('spin')) {
      null => null,
      'clockwise' => 'right',
      'counterclockwise' => 'left',
      _ => _fail,
    };
    final shoulder = side != null && spin != null ? _fail : side ?? spin;
    final count = b.take<int>('placeCount');
    final direction = where == null || where == 'back'
        ? shoulder
        : shoulder != null
        ? _fail
        : where == 'off'
        ? 'down'
        : where;
    // A bare `to top`/`to bottom` reaches the step as dancers after `to`;
    // only a cast reads it as where it ends, so other movements keep reading
    // `set to top` as setting to the top couple.
    var end = _dest(b);
    Object? whom;
    final named = b.take<List<String>>('whom');
    final via = b.take<String>('whomVia');
    if (named != null) {
      final single = _single(named);
      if (via == 'to' && (single == 'top' || single == 'bottom')) {
        end = end == null ? single : _fail;
      } else {
        whom = via == 'around' ? single ?? _fail : _fail;
      }
    }
    return _params({
      'who': who,
      'direction': direction,
      'places': count ?? (where == 'off' && end == null ? 1 : null),
      'whom': whom,
      'destination': end,
    });
  }),
  'galop': _MoveRule(
    'ecd_galop',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'where': _where(b, const ['up', 'down', 'along', 'across']),
      'goBack': _flag(b, 'goBack'),
      'destination': _dest(b),
    }),
  ),
  'chevron': _MoveRule(
    'ecd_chevron',
    (b, c) => _params({
      'who': _whoOf(b, objectIsWho: false),
      'shoulder': _shoulder(b, sideIsShoulder: false),
      'whom': _whom(b, const <String>{}),
      'destination': _dest(b),
    }),
  ),
};

/// A turn: by one hand ([ecd_hand_turn]) or two ([ecd_two_hand_turn]),
/// chosen by the hand the line states. A turn that states neither is not read:
/// which turn it is would be a guess.
Map<String, Object?>? _turnParams(
  _Bag bag,
  _Context context,
  void Function(String) setMove,
) {
  final hand = _sideAs(bag, 'hand', toTheAllowed: false);
  if (hand == 'two') {
    setMove('ecd_two_hand_turn');
    return _params({
      'who': _whoOf(bag),
      'travel': _travel(bag),
      'direction': bag.take<String>('spin'),
      'endFacing': bag.take<String>('endFacing'),
      'destination': _dest(bag),
    });
  }
  if (hand != 'right' && hand != 'left') return null;
  setMove('ecd_hand_turn');
  return _params({
    'who': _whoOf(bag),
    'hand': hand,
    'travel': _travel(bag),
    'endFacing': bag.take<String>('endFacing'),
    'destination': _dest(bag),
  });
}

/// The key a builder uses to hand a note back with its params.
const String _noteSlot = '\u0000note';

// ---------------------------------------------------------------------------
// Reading.

class _Step {
  _Step(this.move, this.params, {this.note, this.statedWho = false});
  final String move;
  final Map<String, Object?> params;
  final String? note;
  final bool statedWho;
}

class _Reader {
  _Reader(this.tokens, {required int? ringDancers})
    : context = _Context(ringDancers: ringDancers);

  final List<String> tokens;
  final _Context context;
  int pos = 0;

  bool get atEnd => pos >= tokens.length;
  String? at(int i) => i < tokens.length ? tokens[i] : null;

  /// Whether the words from [i] are [words].
  bool wordsAt(int i, List<String> words) {
    if (i + words.length > tokens.length) return false;
    for (var k = 0; k < words.length; k++) {
      if (tokens[i + k] != words[k]) return false;
    }
    return true;
  }

  /// The longest key of [phrases] at [i]: its value and length.
  (T, int)? phraseAt<T>(int i, Map<String, T> phrases) {
    (T, int)? best;
    for (final entry in phrases.entries) {
      final words = entry.key.split(' ');
      if ((best == null || words.length > best.$2) && wordsAt(i, words)) {
        best = (entry.value, words.length);
      }
    }
    return best;
  }

  Figure? readLine(int beats) {
    // Split at the one `as`/`while` a meanwhile may have.
    final sides = <List<_Step>>[[]];
    String? lastConnector;
    while (!atEnd) {
      if (sides.last.isNotEmpty) {
        final connector = takeConnector();
        if (connector == null) return null;
        if (connector == 'as' || connector == 'while') {
          if (sides.length == 2) return null;
          sides.add([]);
        }
        lastConnector = connector;
      }
      final current = sides.last;
      // `and back` after a star: a second star back to place (§5.4).
      final back = readReturn(current);
      if (back != null) {
        current.add(back);
      } else {
        final step = readStep();
        if (step == null) return null;
        // `, bending the line` makes the step before it a modifier.
        current.add(step);
      }
      if (current.length > _maxSteps) return null;
    }
    if (lastConnector != null && sides.last.isEmpty) return null;
    final built = [for (final side in sides) _inheritWho(side)];
    if (built.any((side) => side.isEmpty)) return null;
    if (sides.length == 1) return _assemble(built.single, beats);
    final figures = [for (final side in built) _assemble(side, 0)];
    if (figures.any((f) => f == null)) return null;
    final span = beats > 0
        ? beats
        : figures
              .map((f) => _beatsOf(f!))
              .fold<int>(0, (a, b) => a > b ? a : b);
    // As for one side (see [_assemble]): a count outside the beats range is
    // not read.
    if (!_beatsInRange(span)) return null;
    return Figure.meanwhile(
      figures: [for (final f in figures) f!],
      beats: span,
    );
  }

  /// A connector between steps, or null when there is none at [pos].
  String? takeConnector() {
    if (wordsAt(pos, const [',', 'and', 'then'])) {
      pos += 3;
      return 'then';
    }
    if (wordsAt(pos, const ['and', 'then'])) {
      pos += 2;
      return 'then';
    }
    if (wordsAt(pos, const [',', 'then'])) {
      pos += 2;
      return 'then';
    }
    if (wordsAt(pos, const [',', 'and'])) {
      pos += 2;
      return 'and';
    }
    if (wordsAt(pos, const [',', 'as'])) {
      pos += 2;
      return 'as';
    }
    if (wordsAt(pos, const [',', 'while'])) {
      pos += 2;
      return 'while';
    }
    final word = at(pos);
    if (word == null || !_boundaryWords.contains(word)) return null;
    pos++;
    return word;
  }

  /// `back [by the left] [to place]` as a return of the star before it, or
  /// null when [pos] is not one.
  _Step? readReturn(List<_Step> side) {
    if (side.isEmpty || at(pos) != 'back') return null;
    final previous = side.last;
    if (previous.move != 'ecd_star') return null;
    // `back to place`/`back home` are destinations of the star's own reading.
    final start = pos;
    pos++;
    final bag = _Bag();
    while (!atEnd && !_boundaryWords.contains(at(pos))) {
      if (!takeHand(bag) && !takeSide(bag) && !takeDestination(bag)) {
        pos = start;
        return null;
      }
    }
    final hand = _sideAs(bag, 'hand', toTheAllowed: false);
    final destination = bag.take<String>('destination');
    if (hand == _fail ||
        !bag.allTaken ||
        (destination != null && destination != 'place')) {
      pos = start;
      return null;
    }
    return _Step('ecd_star', {'hand': ?hand, 'destination': 'place'});
  }

  _Step? readStep() {
    final start = pos;
    final bag = _Bag();
    final who = takeDancers(subject: true);
    if (who != null) {
      bag.put('who', who);
      // `Partner, 2 hand turn`: a comma may set the subject off.
      if (at(pos) == ',' && verbAt(pos + 1) != null) pos++;
    }
    // Words before the movement.
    _VerbPhrase? verb;
    while (!atEnd) {
      // `balance and box the gnat` is the gnat's `balance` flag (§5.4), not
      // a balance step.
      if (takeFixed(bag)) continue;
      verb = verbAt(pos);
      if (verb != null) break;
      if (!takePreModifier(bag)) {
        pos = start;
        return null;
      }
    }
    if (verb == null) {
      pos = start;
      return null;
    }
    pos += verb.words.length;
    for (final MapEntry(:key, :value) in verb.preset.entries) {
      if (!bag.put(key, value)) {
        pos = start;
        return null;
      }
    }
    // Words after it, up to the next connector.
    var bend = false;
    while (!atEnd) {
      final word = at(pos)!;
      if (word == ',' || word == 'and') {
        // Some phrases after a movement begin with a comma or `and`.
        if (takeContinuation(bag, verb.rule)) continue;
        if (wordsAt(pos, const [',', 'bending', 'the', 'line'])) {
          pos += 4;
          bend = true;
          continue;
        }
        break;
      }
      if (_boundaryWords.contains(word)) break;
      if (!takePostModifier(bag)) {
        pos = start;
        return null;
      }
    }
    final rule = _rules[verb.rule];
    String move = rule?.id ?? '';
    final raw = verb.rule == 'turn'
        ? _turnParams(bag, context, (id) => move = id)
        : rule!.build(bag, context);
    if (raw == null || !bag.allTaken) {
      pos = start;
      return null;
    }
    final note = raw[_noteSlot] as String?;
    final params = {...raw}..remove(_noteSlot);
    if (bend) {
      return _Step(modifierMove, {
        'figures': [
          _Step(move, params, note: note, statedWho: who != null),
          _Step('ecd_bend_line', const {}),
        ],
      }, statedWho: who != null);
    }
    return _Step(move, params, note: note, statedWho: who != null);
  }

  _VerbPhrase? verbAt(int i) {
    for (final verb in _verbPhrases) {
      if (wordsAt(i, verb.words)) return verb;
    }
    return null;
  }

  // ---- Dancers.

  /// One or more dancer phrases joined by `and` or a comma (`1s and 2s`,
  /// `1s, 2s and 3s`), or null when [pos] does not start one.
  List<String>? takeDancers({bool subject = false}) {
    final first = dancerAt(pos);
    if (first == null) return null;
    final out = [first.$1];
    pos += first.$2;
    while (true) {
      final joiner = at(pos);
      if (joiner != 'and' && !(subject && joiner == ',')) break;
      final next = dancerAt(pos + 1);
      if (next == null) break;
      // `partners and neighbors` is two sets; but `1s and turn` is a step.
      out.add(next.$1);
      pos += 1 + next.$2;
    }
    return out;
  }

  /// The dancer phrase at [i]: its selector and length.
  (String, int)? dancerAt(int i) {
    final word = at(i);
    if (word == null) return null;
    // Single dancers: `1st role2`, `role2 1`, `first role1`.
    final ordinal = _ordinals[word];
    if (ordinal != null && ordinal <= 4) {
      final role = _roleOf(at(i + 1));
      if (role != null) return ('${_coupleTokens[ordinal - 1]}$role', 2);
    }
    final role = _roleOf(word);
    if (role != null) {
      final n = int.tryParse(at(i + 1) ?? '');
      if (n != null && n >= 1 && n <= 4) {
        return ('${_coupleTokens[n - 1]}$role', 2);
      }
    }
    // Couples by number: `1s`, `ones`, `1st couple(s)`, `couple 1`.
    final couple = _coupleAt(i);
    if (couple != null) return couple;
    final phrase = phraseAt(i, _dancerPhrases);
    if (phrase == null) return null;
    // `top`/`bottom` alone are places, not dancers, unless a movement follows
    // (`top couple` is read above).
    return phrase;
  }

  (String, int)? _coupleAt(int i) {
    final word = at(i)!;
    const plural = {
      '1s': 1,
      "1's": 1,
      'ones': 1,
      '2s': 2,
      "2's": 2,
      'twos': 2,
      '3s': 3,
      "3's": 3,
      'threes': 3,
      '4s': 4,
      "4's": 4,
      'fours': 4,
      '5s': 5,
      "5's": 5,
      'fives': 5,
    };
    final n = plural[word];
    if (n != null) {
      final couples = at(i + 1) == 'couples' || at(i + 1) == 'couple';
      return (_coupleTokens[n - 1], couples ? 2 : 1);
    }
    final ordinal = _ordinals[word];
    if (ordinal != null) {
      final noun = at(i + 1);
      if (noun == 'couple' ||
          noun == 'couples' ||
          noun == 'cpl' ||
          noun == 'cpls') {
        return (_coupleTokens[ordinal - 1], 2);
      }
    }
    if (word == 'couple') {
      final number = int.tryParse(at(i + 1) ?? '');
      if (number != null && number >= 1 && number <= 5) {
        return (_coupleTokens[number - 1], 2);
      }
    }
    return null;
  }

  static String? _roleOf(String? word) => switch (word) {
    'role1' || 'role1s' => 'Role1',
    'role2' || 'role2s' => 'Role2',
    _ => null,
  };

  // ---- Modifiers.

  /// A word or phrase that may come before the movement.
  bool takePreModifier(_Bag bag) =>
      takeChanges(bag) ||
      takeFixed(bag) ||
      takeAmount(bag) ||
      takeHand(bag) ||
      takeShoulder(bag) ||
      takeSide(bag) ||
      takeFormation(bag) ||
      takeStyle(bag) ||
      takeWithWhom(bag);

  /// A word or phrase that may come after the movement.
  bool takePostModifier(_Bag bag) =>
      takeDestination(bag) ||
      takePlaceCount(bag) ||
      takeAmount(bag) ||
      takeHand(bag) ||
      takeShoulder(bag) ||
      takeSpin(bag) ||
      takeSide(bag) ||
      takeDistance(bag) ||
      takeWhom(bag) ||
      takeStyleWho(bag) ||
      takeStyle(bag) ||
      takeRingSize(bag) ||
      takeFixed(bag) ||
      takeWhere(bag) ||
      takeObject(bag);

  /// A phrase after a movement that starts with a comma or `and`: `and back`,
  /// `and face up`, `and balance`, `, to progressed place`, `, robins push`.
  bool takeContinuation(_Bag bag, String rule) {
    final start = pos;
    if (_goesBack.contains(rule) && wordsAt(pos, const ['and', 'back'])) {
      final next = at(pos + 2);
      if (next == null || _boundaryWords.contains(next)) {
        if (bag.has('goBack')) return false;
        pos += 2;
        bag.put('goBack', true);
        return true;
      }
    }
    if (wordsAt(pos, const ['and', 'balance'])) {
      pos += 2;
      return bag.put('balance', true) || _undo(start);
    }
    if (at(pos) == 'and' || at(pos) == ',') {
      pos++;
      if (takeFacing(bag)) return true;
      if (at(start) == ',' && (takeDestination(bag) || takeStyleWho(bag))) {
        final next = at(pos);
        if (next == null || _boundaryWords.contains(next)) return true;
      }
      pos = start;
    }
    return false;
  }

  bool _undo(int start) {
    pos = start;
    return false;
  }

  bool takeDestination(_Bag bag) {
    final hit = phraseAt(pos, _destinationPhrases);
    if (hit == null) return false;
    if (!bag.put('destination', hit.$1)) return false;
    pos += hit.$2;
    return true;
  }

  bool takeAmount(_Bag bag) {
    final hit = phraseAt(pos, _amountPhrases);
    if (hit == null) return false;
    var length = hit.$2;
    // `half way round`, `3/4 around`: the ring word adds nothing.
    final after = at(pos + length);
    if (after == 'round' || after == 'around') length++;
    if (!bag.put('amount', hit.$1)) return false;
    bag.put('amountWords', tokens.sublist(pos, pos + length).join(' '));
    // The words travel with the amount; only a ring reads them.
    bag.drop('amountWords');
    pos += length;
    return true;
  }

  bool takePlaceCount(_Bag bag) {
    final n = _counts[at(pos) ?? ''];
    final noun = at(pos + 1);
    if (n == null || (noun != 'places' && noun != 'place')) return false;
    if (!bag.put('placeCount', n)) return false;
    pos += 2;
    return true;
  }

  bool takeChanges(_Bag bag) {
    final start = pos;
    final n = _counts[at(pos) ?? ''];
    if (n == null) return false;
    var i = pos + 1;
    var slow = false;
    if (at(i) == 'slow') {
      slow = true;
      i++;
    }
    if (at(i) != 'changes' && at(i) != 'change') return false;
    i++;
    if (at(i) == 'of') i++;
    if (at(i) == 'a') i++;
    if (!bag.put('changes', n)) return _undo(start);
    if (slow && !bag.put('slow', true)) return _undo(start);
    pos = i;
    return true;
  }

  bool takeHand(_Bag bag) {
    final start = pos;
    if (at(pos) == 'by' || at(pos) == 'with' || at(pos) == 'giving') {
      pos++;
      if (at(pos) == 'the') pos++;
    }
    String? hand;
    final word = at(pos);
    if (word == 'rh') {
      hand = 'right';
      pos++;
    } else if (word == 'lh') {
      hand = 'left';
      pos++;
    } else if (word == 'two' || word == '2' || word == 'both') {
      if (at(pos + 1) == 'hand' || at(pos + 1) == 'hands') {
        hand = 'two';
        pos += 2;
      }
    } else if (word == '2h') {
      hand = 'two';
      pos++;
    } else if (word == 'no' || word == 'without') {
      if (at(pos + 1) == 'hands') {
        hand = 'none';
        pos += 2;
      }
    } else if (_sideWords.containsKey(word)) {
      final noun = at(pos + 1);
      if ((noun == 'hand' || noun == 'hands') && at(pos + 2) == 'across') {
        // `right hands across`: the star's own name keeps its `hands`.
        hand = _sideWords[word];
        pos++;
      } else if (noun == 'hand' || noun == 'hands') {
        hand = _sideWords[word];
        pos += 2;
      } else if (start != pos) {
        // `by the right`: the side after `by` is a hand.
        hand = _sideWords[word];
        pos++;
      }
    }
    if (hand == null || !bag.put('hand', hand)) return _undo(start);
    return true;
  }

  bool takeShoulder(_Bag bag) {
    final start = pos;
    if (const {'by', 'passing', 'over', 'pass'}.contains(at(pos))) {
      pos++;
      if (at(pos) == 'the') pos++;
    }
    final side = _sideWords[at(pos) ?? ''];
    final noun = at(pos + 1);
    if (side == null || (noun != 'shoulder' && noun != 'shoulders')) {
      return _undo(start);
    }
    // `right shoulder round` is the movement's own name.
    if (at(pos + 2) == 'round') return _undo(start);
    if (!bag.put('shoulder', side)) return _undo(start);
    pos += 2;
    return true;
  }

  bool takeSide(_Bag bag) {
    final start = pos;
    final toThe = at(pos) == 'to' && at(pos + 1) == 'the';
    if (toThe) pos += 2;
    final side = _sideWords[at(pos) ?? ''];
    if (side == null || !bag.put('side', side)) return _undo(start);
    if (toThe) bag.put('sideToThe', true);
    pos++;
    return true;
  }

  bool takeSpin(_Bag bag) {
    final hit = phraseAt(pos, _spinPhrases);
    if (hit == null || !bag.put('spin', hit.$1)) return false;
    pos += hit.$2;
    return true;
  }

  bool takeWhere(_Bag bag) {
    final hit = phraseAt(pos, _wherePhrases);
    if (hit == null || !bag.put('where', hit.$1)) return false;
    pos += hit.$2;
    return true;
  }

  bool takeFacing(_Bag bag) {
    final start = pos;
    if (at(pos) == 'face' || at(pos) == 'facing') {
      pos++;
    } else if (at(pos) == 'to' && at(pos + 1) == 'face') {
      pos += 2;
    } else {
      return false;
    }
    final facing = _facingWords[at(pos) ?? ''];
    if (facing == null || !bag.put('endFacing', facing)) return _undo(start);
    pos++;
    return true;
  }

  bool takeDistance(_Bag bag) {
    final start = pos;
    if (at(pos) == 'a') pos++;
    final word = at(pos);
    if (word != 'double' && word != 'single') return _undo(start);
    // `single file` is a flag, not a distance.
    if (word == 'single' && at(pos + 1) == 'file') return _undo(start);
    if (!bag.put('distance', word!)) return _undo(start);
    pos++;
    return true;
  }

  bool takeStyle(_Bag bag) {
    final style = _styleWords[at(pos) ?? ''];
    if (style == null || !bag.put('style', style)) return false;
    pos++;
    return true;
  }

  /// `role2s push`, `1s draw`: who pushes or draws a poussette (§7.5).
  bool takeStyleWho(_Bag bag) {
    final start = pos;
    final dancers = takeDancers();
    if (dancers == null) return false;
    final style = _styleWords[at(pos) ?? ''];
    if (style == null || (style != 'push' && style != 'draw')) {
      return _undo(start);
    }
    if (!bag.put('styleWho', dancers) || !bag.put('style', style)) {
      return _undo(start);
    }
    pos++;
    return true;
  }

  bool takeRingSize(_Bag bag) {
    // `circle four`, `circle of six`, `hands six`.
    final start = pos;
    if (at(pos) == 'of') pos++;
    final n = _counts[at(pos) ?? ''];
    if (n == null || n < 4 || n.isOdd) return _undo(start);
    // A count before `places`/`changes` is not a ring.
    final after = at(pos + 1);
    if (after == 'places' || after == 'place' || after == 'changes') {
      return _undo(start);
    }
    if (!bag.put('ringSize', n)) return _undo(start);
    pos++;
    return true;
  }

  bool takeFormation(_Bag bag) {
    final start = pos;
    if (wordsAt(pos, const ['in', 'a', 'ring'])) {
      pos += 3;
      return bag.put('formation', 'inARing') || _undo(start);
    }
    if (at(pos) != 'lines' && at(pos) != 'line') return false;
    if (at(pos) == 'lines' && at(pos + 1) != 'of') {
      // `lines forward and back` names the movement's own lines (§7.5).
      pos++;
      return bag.put('lines', true) || _undo(start);
    }
    if (at(pos + 1) == 'of') {
      final n = _counts[at(pos + 2) ?? ''];
      final value = switch (n) {
        3 => 'linesOfThree',
        4 => 'linesOfFour',
        5 => 'linesOfFive',
        6 => 'linesOfSix',
        _ => null,
      };
      if (value == null) return false;
      pos += 3;
      return bag.put('formation', value) || _undo(start);
    }
    return false;
  }

  /// Fixed words with one meaning wherever they appear.
  bool takeFixed(_Bag bag) {
    final start = pos;
    bool flag(String slot, int length) {
      if (!bag.put(slot, true)) return _undo(start);
      pos += length;
      return true;
    }

    if (wordsAt(pos, const ['single', 'file'])) return flag('singleFile', 2);
    if (at(pos) == 'double' && verbAt(pos + 1)?.rule == 'figure_eight') {
      return flag('double', 1);
    }
    if (at(pos) == 'slow') return flag('slow', 1);
    if (at(pos) == 'open') return flag('open', 1);
    if (at(pos) == 'cloverleaf') return flag('cloverleaf', 1);
    if (wordsAt(pos, const ['balance', 'and']) &&
        const {'box', 'swat'}.contains(at(pos + 2))) {
      return flag('balance', 2);
    }
    if (wordsAt(pos, const ['with', 'a', 'half', 'sashay'])) {
      return flag('halfSashay', 4);
    }
    return false;
  }

  /// `with X`, `to X`, `around X`, `through X`, `starting with X`: the
  /// dancers acted with.
  bool takeWhom(_Bag bag) {
    final start = pos;
    final String via;
    if (wordsAt(pos, const ['starting', 'with'])) {
      via = 'starting with';
      pos += 2;
    } else if (const {
      'to',
      'with',
      'around',
      'round',
      'through',
      'past',
    }.contains(at(pos))) {
      via = at(pos) == 'round' ? 'around' : at(pos)!;
      pos++;
    } else {
      return false;
    }
    final dancers = takeDancers();
    if (dancers == null || !bag.put('whom', dancers)) return _undo(start);
    bag.put('whomVia', via);
    return true;
  }

  /// `with X` before the movement (`with neighbor, half poussette`).
  bool takeWithWhom(_Bag bag) {
    final start = pos;
    if (at(pos) != 'with') return false;
    pos++;
    final dancers = takeDancers();
    if (dancers == null || !bag.put('whom', dancers)) return _undo(start);
    bag.put('whomVia', 'with');
    if (at(pos) == ',') pos++;
    return true;
  }

  /// Dancers named after the movement with no preposition (`turn partner`).
  bool takeObject(_Bag bag) {
    final start = pos;
    final dancers = takeDancers();
    if (dancers == null || !bag.put('object', dancers)) return _undo(start);
    return true;
  }
}

/// [side] with the first step's stated subject given to each later step that
/// states none, as "1st corners set and turn single" is read (§8.1).
List<_Step> _inheritWho(List<_Step> side) {
  if (side.isEmpty) return side;
  final first = side.first;
  final who = first.statedWho ? _whoParam(first) : null;
  if (who == null) return side;
  // A later step that names other dancers (`1s cast and 2s cross up, double
  // figure 8`) leaves it unclear whose the steps after it are, so no step
  // takes a subject it does not state.
  if (side.skip(1).any((step) => step.statedWho)) return side;
  return [
    first,
    for (final step in side.skip(1))
      step.statedWho || !_takesWho(step.move) ? step : _withWho(step, who),
  ];
}

Object? _whoParam(_Step step) => step.move == modifierMove
    ? ((step.params['figures'] as List).first as _Step).params['who']
    : step.params['who'];

bool _takesWho(String move) =>
    move == modifierMove ||
    (!_ringMoves.contains(move) &&
        (ecdTaxonomy.resolve(move)?.params.containsKey('who') ?? false));

/// Movements danced by a ring or by more dancers than one step's subject
/// usually names: "1s set and circle left" does not say the 1s circle alone,
/// so such a step never takes an earlier step's subject (R2).
const Set<String> _ringMoves = {
  'ecd_circle',
  'ecd_star',
  'ecd_chain',
  'ecd_rights_and_lefts',
  'ecd_grand_chain',
  'ecd_right_left_through',
  'ecd_circular_hey',
  'ecd_dolphin_hey',
  'ecd_hey_for_three',
  'ecd_hey_for_four',
  'ecd_hey_for_six',
  'ecd_mirror_hey',
  'ecd_tandem_reel',
  'ecd_form_long_wave',
  'ecd_poussette',
  'ecd_contra_corners',
  'ecd_chevron',
};

_Step _withWho(_Step step, Object who) {
  if (step.move == modifierMove) {
    final children = step.params['figures'] as List;
    final core = children.first as _Step;
    return _Step(modifierMove, {
      'figures': [_withWho(core, who), ...children.skip(1)],
    });
  }
  if (step.params.containsKey('who') || !_takesWho(step.move)) return step;
  return _Step(step.move, {'who': who, ...step.params}, note: step.note);
}

/// The figure for one side of a line: one step, or a sequence of them.
Figure? _assemble(List<_Step> steps, int beats) {
  final figures = <Figure>[];
  for (final step in steps) {
    final figure = _figureOf(step);
    if (figure == null) return null;
    figures.add(figure);
  }
  // A count outside the beats range is left to the range check, as contra's
  // parser leaves it: the line is not read, so it stays custom.
  if (!_beatsInRange(beats)) return null;
  if (figures.length == 1) {
    final only = figures.single;
    if (beats <= 0) return only;
    if (only.isContainer) return _withSpan(only, beats);
    return only.copyWith(params: {...only.params, 'beats': beats});
  }
  final span = beats > 0 ? beats : figures.map(_beatsOf).fold(0, _sum);
  if (!_beatsInRange(span)) return null;
  return Figure.sequence(figures: figures, beats: span);
}

int _sum(int a, int b) => a + b;

/// The counts a figure's `beats` may hold ([ParamKind.beats]: 0 to 64).
bool _beatsInRange(int beats) => beats >= 0 && beats <= 64;

/// One step as a figure, validated against the ECD taxonomy alone.
Figure? _figureOf(_Step step) {
  if (step.move == modifierMove) {
    final children = [
      for (final child in step.params['figures'] as List)
        _figureOf(child as _Step),
    ];
    if (children.any((c) => c == null)) return null;
    final core = children.first!;
    return Figure.modifier(
      figures: [for (final c in children) c!],
      beats: _beatsOf(core),
    );
  }
  final figure = Figure(move: step.move, params: step.params, note: step.note);
  final invalid = ecdTaxonomy
      .validateFigure(figure)
      .any((i) => i.severity == ValidationSeverity.error);
  return invalid ? null : figure;
}

/// The beats [figure] lasts: its own, or its movement's default.
int _beatsOf(Figure figure) {
  if (figure.isContainer) return figure.beats;
  final beats = ecdTaxonomy.effectiveParams(figure)['beats'];
  return beats is int ? beats : 0;
}

Figure _withSpan(Figure container, int beats) =>
    container.copyWith(params: {...container.params, 'beats': beats});
