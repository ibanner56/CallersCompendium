import 'dart:convert';

import 'package:compendium_core/compendium_core.dart' show contraTaxonomy;
import 'package:meta/meta.dart';

import '../domain/formation_type.dart';
import '../engine/compiler.dart';
import '../engine/invocation.dart';
import '../engine/result.dart';
import '../engine/success_criterion.dart';
import '../ops/diagnostics.dart';
import '../ops/operation.dart';
import '../ops/params.dart';

/// A dance record could not be turned into a [Dance].
///
/// Deliberately **not** an [OpError]: those describe a dance whose figures
/// refuse to run, which is a fact about the choreography. This describes a
/// record the compiler cannot even read, which is a fact about the input. The
/// two are reported through different channels so a caller never has to guess
/// which kind of problem it is looking at.
@immutable
class DanceParseError {
  const DanceParseError(this.message, {this.path = '', this.deferred = false});

  /// What went wrong.
  final String message;

  /// Where in the record, in dotted JSON-path form (`figures[2].params.who`).
  final String path;

  /// Whether the record is fine and **this compiler** is the thing missing.
  ///
  /// Set only where the reason is "not modelled yet" — an unimplemented move,
  /// or a vocabulary value with no reading here. A malformed record is not
  /// deferred, and neither is an unmodelled *progression* tier, which is a
  /// property of the dance rather than of any figure in it. The distinction is
  /// what lets a corpus report separate the backlog from the defects
  /// (`CorpusReport.inScope`).
  final bool deferred;

  @override
  bool operator ==(Object other) =>
      other is DanceParseError &&
      other.message == message &&
      other.path == path &&
      other.deferred == deferred;

  @override
  int get hashCode => Object.hash(message, path, deferred);

  @override
  String toString() => path.isEmpty ? message : '$path: $message';
}

/// Thrown internally to unwind out of a nested read; never escapes [parseDance].
class _ParseFailure implements Exception {
  _ParseFailure(this.error);
  final DanceParseError error;
}

/// Typed, forgiving access to one figure's `params` object.
///
/// **Unknown keys are ignored by design.** The dance schema is owned upstream
/// and gains fields over time; a record that carries a parameter we have not
/// modelled yet is still a record we can compile, so reading is by lookup
/// rather than by exhaustive destructuring. Missing keys fall back to the
/// taxonomy's documented defaults — real records omit anything they leave at
/// its default (no `where` on a swing, no `dir` on a plain chain).
///
/// What is *not* forgiven is a key present with the wrong type or an
/// unrecognized value: that is a malformed record, and guessing at it would
/// silently compile a different dance than the one written down.
class _Params {
  _Params(this._raw, this._path);

  final Map<String, Object?> _raw;
  final String _path;

  Never _fail(String key, String message, {bool deferred = false}) =>
      throw _ParseFailure(
        DanceParseError(message, path: '$_path.$key', deferred: deferred),
      );

  /// The upstream sentinel meaning "the source states nothing here".
  ///
  /// Treated as **absent**, which is exactly what it means: the parameter falls
  /// back to its documented default. Handling it here rather than per-figure
  /// means every parameter gets the behaviour for free, including the ones that
  /// opt into the sentinel later — upstream is explicit that the set of params
  /// admitting it is a moving target, so enumerating them here would drift.
  static const String _unspecified = 'unspecified';

  /// The value under the first authored key, so canonical spellings win even
  /// when they explicitly state `unspecified`.
  Object? _first(List<String> keys) {
    final value = _raw[_blameKey(keys)];
    return value == _unspecified ? null : value;
  }

  /// Which of [keys] the author actually wrote, falling back to the first.
  ///
  /// A refusal has to point at the spelling on the page. Reporting the first
  /// accepted alias regardless sends the reader to a key their file does not
  /// contain — the one case where a parse error makes the problem harder to
  /// find than no error would have. When nothing is stated the first alias is
  /// the only honest answer: there is no written key to name, and that is the
  /// one the taxonomy documents.
  String _blameKey(List<String> keys) {
    for (final key in keys) {
      if (_raw.containsKey(key)) return key;
    }
    return keys.first;
  }

  String? optionalString(List<String> keys) {
    final value = _first(keys);
    if (value == null) return null;
    if (value is! String) {
      _fail(_blameKey(keys), 'expected a string, got $value');
    }
    return value;
  }

  int intOr(List<String> keys, int fallback) {
    final value = _first(keys);
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    _fail(_blameKey(keys), 'expected a whole number, got $value');
  }

  double numberOr(List<String> keys, double fallback) {
    final value = _first(keys);
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    _fail(_blameKey(keys), 'expected a number, got $value');
  }

  bool boolOr(List<String> keys, bool fallback) {
    final value = _first(keys);
    if (value == null) return fallback;
    if (value is! bool) {
      _fail(_blameKey(keys), 'expected true or false, got $value');
    }
    return value;
  }

  /// Resolves an enum-like parameter through [lookup], falling back to
  /// [fallback] when absent.
  T enumOr<T>(List<String> keys, T? Function(String) lookup, T fallback) {
    final raw = optionalString(keys);
    if (raw == null) return fallback;
    final value = lookup(raw);
    if (value == null) {
      _fail(_blameKey(keys), 'unrecognized value "$raw"', deferred: true);
    }
    return value;
  }

  /// Resolves an enum-like parameter that has **no** default.
  ///
  /// A handful of parameters default to the `unspecified` sentinel upstream —
  /// `gate`'s whole signature, `balance.hand`, `courtesy_turn.whom`. For those,
  /// "absent" is a distinct state from any value in the vocabulary, and
  /// collapsing it into one would assert something the source never said.
  T? optionalEnum<T>(List<String> keys, T? Function(String) lookup) {
    final raw = optionalString(keys);
    if (raw == null) return null;
    final value = lookup(raw);
    if (value == null) {
      _fail(_blameKey(keys), 'unrecognized value "$raw"', deferred: true);
    }
    return value;
  }

  /// A number with no default, for the same reason as [optionalEnum].
  double? optionalNumber(List<String> keys) {
    final value = _first(keys);
    if (value == null) return null;
    if (value is num) return value.toDouble();
    _fail(_blameKey(keys), 'expected a number, got $value');
  }
}

/// Builds one figure from its `params` object.
typedef _FigureBuilder = Operation Function(_Params params);

/// The name → constructor registry (`docs/architecture.md` §9).
///
/// The single boundary between the external record's `move` string and the
/// typed, sealed [Operation] hierarchy. Everything past this map is typed; the
/// pure core never sees a raw map.
///
/// A move that is not in this table is a figure the compiler has not built yet.
/// That is reported rather than skipped: silently dropping a figure would
/// change the dance and then cheerfully compare it against the oracle.
const Map<String, _FigureBuilder> _registry = {
  'allemande': _buildAllemande,
  'balance': _buildBalance,
  'balance_the_ring': _buildBalanceTheRing,
  'box_circulate': _buildBoxCirculate,
  'box_the_gnat': _buildBoxTheGnat,
  'california_twirl': _buildCaliforniaTwirl,
  'chain': _buildChain,
  'circle': _buildCircle,
  'courtesy_turn': _buildCourtesyTurn,
  'cross_trails': _buildCrossTrails,
  'do_si_do': _buildDoSiDo,
  'down_the_hall': _buildDownTheHall,
  'facing_star': _buildFacingStar,
  'figure_8': _buildFigureEight,
  'form_a_long_wave': _buildFormALongWave,
  'form_long_waves': _buildFormLongWaves,
  'form_short_waves': _buildFormShortWaves,
  'gate': _buildGate,
  'give_and_take': _buildGiveAndTake,
  'hey': _buildHey,
  'long_lines': _buildLongLines,
  'mad_robin': _buildMadRobin,
  'orbit': _buildOrbit,
  'pass_by': _buildPassBy,
  'pass_the_ocean': _buildPassTheOcean,
  'pass_through': _buildPassThrough,
  'petronella': _buildPetronella,
  'poussette': _buildPoussette,
  'pull_by': _buildPullBy,
  'right_left_through': _buildRightLeftThrough,
  'roll_away': _buildRollAway,
  'rory_o_more': _buildRoryOMore,
  'shoulder_round': _buildShoulderRound,
  'slide_along_set': _buildSlideAlongSet,
  'square_through': _buildSquareThrough,
  'stand_still': _buildStandStill,
  'star': _buildStar,
  'star_promenade': _buildStarPromenade,
  'star_through': _buildStarThrough,
  'swing': _buildSwing,
  'turn_alone': _buildTurnAlone,
  'turn_as_couples': _buildTurnAsCouples,
  'two_hand_turn': _buildTwoHandTurn,
  'up_the_hall': _buildUpTheHall,
  'zig_zag': _buildZigZag,
};

/// The figures this compiler can build, for diagnostics.
/// Every move this compiler can parse, including the aliases it resolves.
///
/// Aliases are `compendium_core`'s vocabulary, not ours: they are listed here
/// because a record may name one, and refusing it would reject a dance we can
/// in fact compile.
List<String> get supportedMoves => <String>{
  ..._registry.keys,
  for (final entry in contraTaxonomy.aliases.entries)
    if (_registry.containsKey(entry.value.targetMove)) entry.key,
}.toList()..sort();

Operation _buildCircle(_Params p) => Circle(
  // `turn` here is a **direction** — one of its three taxonomy meanings.
  turn: p.enumOr(
    ['direction', 'turn'],
    CircleDirection.fromKey,
    CircleDirection.left,
  ),
  places: p.intOr(['places'], 4),
  singleFile: p.boolOr(['singleFile'], false),
);

Operation _buildStar(_Params p) => Star(
  hand: p.enumOr(['hand'], Hand.fromKey, Hand.right),
  places: p.intOr(['places'], 4),
  // Upstream spells "no stated grip" as the choice `none`; we carry it as an
  // absent value, since grip has no end-state effect either way.
  grip: switch (p.optionalString(['grip'])) {
    null || 'none' => null,
    final String grip => grip,
  },
);

Operation _buildPetronella(_Params p) =>
    Petronella(balance: p.boolOr(['balance'], true));

Operation _buildSwing(_Params p) => Swing(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  // `where` is ours, not upstream's — no record carries it, so it always takes
  // this default. Kept readable so a hand-written fixture can still set it.
  where: p.enumOr(['where'], SwingWhere.fromKey, SwingWhere.sides),
  // Upstream spells the finishing facing `endFacing`, deliberately distinct
  // from `gate`'s `face`; our own taxonomy calls it `face`. Both are read,
  // canonical spelling first.
  face: p.enumOr(
    ['endFacing', 'face'],
    FaceDirection.fromKey,
    FaceDirection.towardSet,
  ),
  prefix: p.optionalString(['prefix']) ?? 'none',
);

Operation _buildDoSiDo(_Params p) => DoSiDo(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.neighbors),
  // `travel` is the v35 spelling; both earlier spellings remain readable.
  circling: p.numberOr(['travel', 'turn', 'circling'], 1),
  shoulder: p.enumOr(['shoulder'], Hand.fromKey, Hand.right),
);

Operation _buildRightLeftThrough(_Params p) =>
    RightLeftThrough(dir: p.optionalString(['where', 'dir']) ?? 'across');

Operation _buildChain(_Params p) => Chain(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role2s),
  // Upstream defaults this to the `unspecified` sentinel rather than the
  // role-implied side, so it very often arrives unstated. Harmless here: the
  // pull-by hand is recorded for fidelity and has no end-state effect.
  hand: p.enumOr(['hand'], Hand.fromKey, Hand.right),
  dir: p.enumOr(
    ['where', 'dir'],
    ChainDirection.fromKey,
    ChainDirection.across,
  ),
);

Operation _buildStandStill(_Params p) =>
    StandStill(beats: p.intOr(['beats'], 8));

Operation _buildHey(_Params p) => HeyForFour(
  pass1: p.enumOr(['pass1'], WhoSet.fromKey, WhoSet.role2s),
  length: p.enumOr(['length'], HeyLength.fromKey, HeyLength.half),
  // Both of these arrive as the `unspecified` sentinel far more often than not,
  // which `_Params` already reads as absent. `pass2` is an anchor and
  // `meetTarget` only speaks to the deferred partial lengths, so neither
  // selects anybody.
  pass2: p.optionalEnum(['pass2'], WhoSet.fromKey),
  meetTarget: p.optionalEnum(['meetTarget'], WhoSet.fromKey),
  shoulder: p.enumOr(['shoulder'], Hand.fromKey, Hand.right),
  dir: p.enumOr(['where', 'dir'], Direction.fromKey, Direction.across),
  rico1: p.boolOr(['rico1'], false),
  rico2: p.boolOr(['rico2'], false),
  rico3: p.boolOr(['rico3'], false),
  rico4: p.boolOr(['rico4'], false),
);

// --- Turns -----------------------------------------------------------------

Operation _buildAllemande(_Params p) => Allemande(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.neighbors),
  hand: p.enumOr(['hand'], Hand.fromKey, Hand.right),
  turn: p.numberOr(['travel', 'turn'], 1),
);

Operation _buildTwoHandTurn(_Params p) => TwoHandTurn(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  turn: p.numberOr(['travel', 'turn'], 1),
);

Operation _buildShoulderRound(_Params p) => ShoulderRound(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.neighbors),
  shoulder: p.enumOr(['shoulder'], Hand.fromKey, Hand.right),
  turn: p.numberOr(['travel', 'turn'], 1),
);

Operation _buildMadRobin(_Params p) => MadRobin(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role2s),
  turn: p.numberOr(['travel', 'turn'], 1),
  direction: p.optionalEnum(['direction'], SpinDirection.fromKey),
  whom: p.optionalEnum(['whom'], WhoSet.fromKey),
);

Operation _buildOrbit(_Params p) => Orbit(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.ones),
  turn: p.enumOr(
    ['direction', 'turn'],
    SpinDirection.fromKey,
    SpinDirection.clockwise,
  ),
  amount: p.numberOr(['travel', 'amount'], 0.5),
);

Operation _buildStarPromenade(_Params p) => StarPromenade(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role1s),
  turn: p.numberOr(['travel', 'turn'], 0.5),
);

// --- Rings -----------------------------------------------------------------

Operation _buildBoxCirculate(_Params p) => BoxCirculate(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role2s),
  hand: p.enumOr(['hand'], Hand.fromKey, Hand.right),
  balance: p.boolOr(['balance'], false),
);

Operation _buildFacingStar(_Params p) => FacingStar(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.ones),
  turn: p.enumOr(
    ['direction', 'turn'],
    SpinDirection.fromKey,
    SpinDirection.clockwise,
  ),
  places: p.intOr(['places'], 3),
);

// --- Couple wheels ---------------------------------------------------------

Operation _buildCaliforniaTwirl(_Params p) =>
    CaliforniaTwirl(who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners));

Operation _buildStarThrough(_Params p) =>
    StarThrough(who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners));

Operation _buildRoryOMore(_Params p) => RoryOMore(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.everyone),
  balance: p.boolOr(['balance'], true),
  // `slide` names the dancer's own side, so it reads as a hand.
  slide: p.enumOr(['slide'], Hand.fromKey, Hand.right),
);

Operation _buildTurnAsCouples(_Params p) =>
    TurnAsCouples(who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners));

Operation _buildCourtesyTurn(_Params p) => CourtesyTurn(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  whom: p.optionalEnum(['whom'], WhoSet.fromKey),
  direction: p.enumOr(
    ['direction'],
    SpinDirection.fromKey,
    SpinDirection.clockwise,
  ),
  // A dancer relationship despite the name it shares with `swing.endFacing`.
  endFacing: p.optionalEnum(['endFacing'], WhoSet.fromKey),
);

// --- Pair swaps ------------------------------------------------------------

Operation _buildRollAway(_Params p) => RollAway(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.neighbors),
  whom: p.enumOr(['whom'], WhoSet.fromKey, WhoSet.partners),
  halfSashay: p.boolOr(['halfSashay'], false),
);

Operation _buildPullBy(_Params p) {
  final who = p.optionalEnum(['who'], WhoSet.fromKey);
  final where = p.optionalEnum(['where', 'dir'], Direction.fromKey);
  final balance = p.boolOr(['balance'], false);
  final hand = p.enumOr(['hand'], Hand.fromKey, Hand.right);

  // v35 unified the two wire moves. A named dancer set is the more specific
  // reading when both axes are present; otherwise the move is spatial.
  if (who != null) {
    return PullByDancers(who: who, balance: balance, hand: hand);
  }
  if (where == null) {
    p._fail(
      p._blameKey(['who', 'where', 'dir']),
      'pull_by requires a stated who or where',
      deferred: true,
    );
  }
  return PullByDirection(balance: balance, dir: where, hand: hand);
}

Operation _buildPassBy(_Params p) => PassBy(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.neighbors),
  shoulder: p.enumOr(['shoulder'], Hand.fromKey, Hand.right),
);

Operation _buildBoxTheGnat(_Params p) => BoxTheGnat(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  hand: p.enumOr(['hand'], Hand.fromKey, Hand.right),
  balance: p.boolOr(['balance'], false),
);

// --- Axis swaps ------------------------------------------------------------

Operation _buildPassThrough(_Params p) => PassThrough(
  dir: p.enumOr(['where', 'dir'], Direction.fromKey, Direction.along),
  shoulder: p.enumOr(['shoulder'], Hand.fromKey, Hand.right),
);

Operation _buildZigZag(_Params p) => ZigZag(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  turn: p.enumOr(['slide', 'turn'], Hand.fromKey, Hand.left),
  ender: p.enumOr(['ender'], ZigZagEnder.fromKey, ZigZagEnder.none),
);

Operation _buildPoussette(_Params p) => Poussette(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.ones),
  whom: p.enumOr(['whom'], WhoSet.fromKey, WhoSet.neighbors),
  half: p.enumOr(['fraction', 'half'], TurnFraction.fromKey, TurnFraction.half),
  turn: p.enumOr(
    ['direction', 'turn'],
    SpinDirection.fromKey,
    SpinDirection.clockwise,
  ),
);

Operation _buildCrossTrails(_Params p) => CrossTrails(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  dir: p.enumOr(['where', 'dir'], Direction.fromKey, Direction.across),
  shoulder: p.enumOr(['shoulder'], Hand.fromKey, Hand.right),
  who2: p.enumOr(['who2'], WhoSet.fromKey, WhoSet.neighbors),
);

Operation _buildSquareThrough(_Params p) => SquareThrough(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.partners),
  who2: p.enumOr(['who2'], WhoSet.fromKey, WhoSet.neighbors),
  balance: p.boolOr(['balance'], true),
  hand: p.enumOr(['hand'], Hand.fromKey, Hand.right),
  places: p.intOr(['places'], 4),
);

// --- Stationary ------------------------------------------------------------

Operation _buildBalance(_Params p) => Balance(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.neighbors),
  // Most balances state no hand, and defaulting to a side would assert
  // something the source never said.
  hand: p.optionalEnum(['hand'], Hand.fromKey),
);

Operation _buildBalanceTheRing(_Params p) => const BalanceTheRing();

Operation _buildLongLines(_Params p) =>
    LongLines(goBack: p.boolOr(['goBack'], true));

Operation _buildTurnAlone(_Params p) => TurnAlone(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.everyone),
  custom: p.optionalString(['custom']) ?? '',
);

// --- Waves -----------------------------------------------------------------

Operation _buildFormShortWaves(_Params p) => FormShortWaves(
  dir: p.enumOr(['axis', 'dir'], Direction.fromKey, Direction.across),
  balance: p.boolOr(['balance'], false),
  center: p.enumOr(['center'], WhoSet.fromKey, WhoSet.role2s),
  // Core's stated default, which is now the canonical duple-improper wave.
  // Honoured rather than derived because upstream owns what an omitted
  // parameter means; the figure keeps its `center`-derives-hand path for
  // direct construction. See [FormShortWaves.centerHand].
  centerHand: p.enumOr(['centerHand'], Hand.fromKey, Hand.left),
  sides: p.enumOr(['sides'], WhoSet.fromKey, WhoSet.neighbors),
);

/// Shares `form_short_waves`' whole wave signature, because the wave it lands
/// in is that figure — the pass across the hall is what this one adds.
Operation _buildPassTheOcean(_Params p) => PassTheOcean(
  dir: p.enumOr(['where', 'dir'], Direction.fromKey, Direction.across),
  balance: p.boolOr(['balance'], false),
  center: p.enumOr(['center'], WhoSet.fromKey, WhoSet.role2s),
  centerHand: p.enumOr(['centerHand'], Hand.fromKey, Hand.left),
  sides: p.enumOr(['sides'], WhoSet.fromKey, WhoSet.neighbors),
);

Operation _buildFormLongWaves(_Params p) => FormLongWaves(
  // Core's stated default. The figure keeps `null` as a distinct state for
  // records that fix the geometry by naming the hold instead, but a record
  // parsed from core's schema never reaches it.
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role1s),
  whom: p.optionalEnum(['whom'], WhoSet.fromKey),
  hand: p.optionalEnum(['whomHand', 'hand'], Hand.fromKey),
  balance: p.boolOr(['balance'], false),
);

Operation _buildFormALongWave(_Params p) => FormALongWave(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role2s),
  // `in` and `out` are the wire spellings; Dart reserves the first.
  stepsIn: p.boolOr(['in'], true),
  stepsOut: p.boolOr(['out'], false),
  balance: p.boolOr(['balance'], true),
);

// --- Bespoke ---------------------------------------------------------------

Operation _buildGiveAndTake(_Params p) => GiveAndTake(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.role1s),
  whom: p.enumOr(['whom'], WhoSet.fromKey, WhoSet.partners),
  give: p.boolOr(['give'], true),
);

Operation _buildFigureEight(_Params p) => FigureEight(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.ones),
  dir: p.enumOr(['where', 'dir'], FigureEightDir.fromKey, FigureEightDir.none),
  // `lead` names a single dancer (`onesRole2`), which is outside our `who`
  // vocabulary, so it is carried verbatim rather than resolved. It is
  // descriptive only -- no net effect on the landing -- but the taxonomy gives
  // it a stated default, so an unstated lead takes that rather than nothing.
  lead: p.optionalString(['lead']) ?? 'onesRole2',
  half: p.enumOr(['fraction', 'half'], TurnFraction.fromKey, TurnFraction.half),
);

Operation _buildGate(_Params p) => Gate(
  who: p.optionalEnum(['who'], WhoSet.fromKey),
  whom: p.optionalEnum(['whom'], WhoSet.fromKey),
  // `pair` is the axis that actually selects the gating pairs.
  pair: p.optionalEnum(['pair'], WhoSet.fromKey),
  direction: p.optionalEnum(['direction'], GateDirection.fromKey),
  turn: p.optionalNumber(['travel', 'turn']),
  face: p.optionalEnum(['endFacing', 'face'], GateFace.fromKey),
);

Operation _buildSlideAlongSet(_Params p) => SlideAlongSet(
  slide: p.enumOr(['slide'], SlideDirection.fromKey, SlideDirection.left),
);

// --- Hall ------------------------------------------------------------------

Operation _buildDownTheHall(_Params p) => DownTheHall(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.everyone),
  moving: p.enumOr(['moving'], HallMoving.fromKey, HallMoving.all),
  facing: p.enumOr(['facing'], HallFacing.fromKey, HallFacing.forward),
  ender: p.enumOr(['ender'], HallEnder.fromKey, HallEnder.turnCouple),
);

Operation _buildUpTheHall(_Params p) => UpTheHall(
  who: p.enumOr(['who'], WhoSet.fromKey, WhoSet.everyone),
  moving: p.enumOr(['moving'], HallMoving.fromKey, HallMoving.all),
  facing: p.enumOr(['facing'], HallFacing.fromKey, HallFacing.forward),
  // Upstream's one asymmetry with `down_the_hall`.
  ender: p.enumOr(['ender'], HallEnder.fromKey, HallEnder.circle),
);

/// How a record's top-level `progression` maps to a success criterion.
const Map<String, int> _progressionCounts = {
  'single': 1,
  'double': 2,
  'triple': 3,
  'quadruple': 4,
};

/// Parses a dance record (`docs/architecture.md` §9).
///
/// Accepts the upstream dance-record shape, of which the compiler reads four
/// things — `title`, `formation.shape`, `progression`, and `figures` — and
/// **ignores everything else**. That is deliberate: the schema is owned
/// elsewhere and grows over time, so the parser is written to tolerate fields
/// it has never heard of rather than to enumerate the ones it has.
///
/// Returns a [DanceParseError] rather than throwing, so a caller folding over a
/// library of dances can collect failures instead of unwinding.
Result<Dance, DanceParseError> parseDance(Map<String, Object?> record) {
  try {
    return Ok(_parseDance(record));
  } on _ParseFailure catch (failure) {
    return Err(failure.error);
  }
}

/// Parses a dance record from its JSON text.
Result<Dance, DanceParseError> parseDanceJson(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    return Err(DanceParseError('not valid JSON: ${error.message}'));
  }
  if (decoded is! Map<String, Object?>) {
    return Err(const DanceParseError('expected a JSON object at the root'));
  }
  return parseDance(decoded);
}

Dance _parseDance(Map<String, Object?> record) {
  final form = record['form'];
  if (form is String && form.toLowerCase() != 'contra') {
    // Refused rather than attempted: a square or circle dance has a different
    // geometry, and running it through contra hands four would produce a
    // confident, meaningless answer (`docs/taxonomy.md` §2).
    throw _ParseFailure(
      DanceParseError(
        'unsupported form "$form"; this compiler is contra-only',
        path: 'form',
      ),
    );
  }

  final warnings = <Warning>[];
  return Dance(
    name: record['title'] is String ? record['title']! as String : '',
    formation: _parseFormation(record['formation'], warnings),
    success: _parseSuccess(record['progression']),
    figures: _parseFigures(record['figures']),
    warnings: warnings,
  );
}

/// The shape assumed when a record names one this compiler does not model.
///
/// Duple Improper is the base formation the others are described against
/// (`docs/fundamentals.md` §9), so it is the reading least likely to smuggle in
/// an assumption of its own — a Becket fallback would silently impose a
/// rotational offset nobody asked for. *(User-ruled.)*
const _fallbackFormation = FormationType.dupleImproper;

FormationType _parseFormation(Object? raw, List<Warning> warnings) {
  // The record nests the shape under a `formation` object alongside a
  // free-text `detail` that is documentation, not data.
  final shape = switch (raw) {
    {'shape': final Object? shape} => shape,
    _ => raw,
  };
  if (shape is! String) {
    throw _ParseFailure(
      const DanceParseError('missing formation shape', path: 'formation.shape'),
    );
  }
  final type = FormationType.fromKey(shape);
  if (type != null) return type;

  // Warned and read as the base formation rather than refused. The shape
  // vocabulary is owned upstream and grows — `other` is already in the corpus —
  // and a dance whose own figures establish the arrangement it dances in does
  // not need the declaration to be one this compiler has a name for. The
  // declared type is not what the figures are checked against in any case: it
  // fixes the starting matrix and nothing more, and never tracks where the
  // dancers actually stand (§3.2). *(User-ruled.)*
  warnings.add(
    Warning(
      WarningKind.unrecognizedFormation,
      detail:
          'the record declares formation "$shape", which this compiler does '
          'not model; it is read as ${_fallbackFormation.label} and the dance '
          'starts from that matrix',
    ),
  );
  return _fallbackFormation;
}

SuccessCriterion _parseSuccess(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    throw _ParseFailure(
      const DanceParseError(
        'missing progression; the compiler needs to know what the dance '
        'claims to achieve',
        path: 'progression',
      ),
    );
  }
  final count = _progressionCounts[raw.trim().toLowerCase()];
  if (count == null) {
    throw _ParseFailure(
      DanceParseError('unrecognized progression "$raw"', path: 'progression'),
    );
  }
  return ProgressionCriterion(count: count);
}

List<OperationInvocation> _parseFigures(Object? raw) {
  if (raw is! List) {
    throw _ParseFailure(
      const DanceParseError('missing figure list', path: 'figures'),
    );
  }
  return [
    for (var index = 0; index < raw.length; index++)
      _parseFigure(raw[index], index),
  ];
}

OperationInvocation _parseFigure(Object? raw, int index) {
  final path = 'figures[$index]';
  if (raw is! Map<String, Object?>) {
    throw _ParseFailure(
      DanceParseError('expected a figure object', path: path),
    );
  }

  final move = raw['move'];
  if (move is! String) {
    throw _ParseFailure(
      DanceParseError('missing move name', path: '$path.move'),
    );
  }

  // An alias is `compendium_core`'s name for a target move with some params
  // fixed -- `see_saw` is a `do_si_do` by the left shoulder. Resolving through
  // `contraTaxonomy.aliases` rather than a table of our own keeps the one
  // definition upstream, which is the point of depending on core at all.
  final alias = contraTaxonomy.aliases[move];
  final moveId = alias?.targetMove ?? move;

  final build = _registry[moveId];
  if (build == null) {
    throw _ParseFailure(
      DanceParseError(
        'unsupported move "$move"; this compiler knows '
        '${supportedMoves.join(', ')}',
        path: '$path.move',
        deferred: true,
      ),
    );
  }

  final params = raw['params'];
  if (params != null && params is! Map<String, Object?>) {
    throw _ParseFailure(
      DanceParseError('expected a params object', path: '$path.params'),
    );
  }

  final progression = raw['progression'];
  if (progression != null && progression is! bool) {
    throw _ParseFailure(
      DanceParseError('expected true or false', path: '$path.progression'),
    );
  }

  final figureParams = <String, Object?>{
    ...(params as Map<String, Object?>?) ?? const {},
  };
  if (alias != null) {
    if (move == 'pull_by_dancers' || move == 'pull_by_direction') {
      // Migration pins fill only values the v34 record did not state. `dir`
      // is the legacy spelling of `where`, so either key suppresses the
      // direction alias's default while preserving source-key diagnostics.
      for (final pin in alias.pinnedParams.entries) {
        if (move == 'pull_by_direction' &&
            pin.key == 'where' &&
            (figureParams.containsKey('where') ||
                figureParams.containsKey('dir'))) {
          continue;
        }
        figureParams.putIfAbsent(pin.key, () => pin.value);
      }
    } else {
      // For semantic aliases the pins *are* the alias: a `see_saw` whose
      // record also said `shoulder:right` is still a see saw.
      figureParams.addAll(alias.pinnedParams);
    }
  }

  return OperationInvocation(
    build(_Params(figureParams, '$path.params')),
    progression: (progression as bool?) ?? false,
  );
}
