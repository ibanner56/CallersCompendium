import '../model/enums.dart';
import '../model/figure.dart' show customMoveId;
import 'gate_facing.dart';
import 'move_def.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Version of the seeded contra taxonomy. Bumped when moves/params change.
///
/// A documentary marker: nothing reads this at runtime. It records that the
/// seeded move/param vocabulary changed, which users notice because dances are
/// categorised, rendered or matched differently. Distinct from
/// `CompendiumDatabase.schemaVersion` — a bump here implies no DB migration
/// unless the entry for that version says so.
///
/// **The per-version log lives in `docs/design/figure-taxonomy.md` under
/// "Taxonomy version history", and every bump appends an entry there in the
/// same PR** — `tools/ci/check_version_history.py` fails the build otherwise.
/// It is kept there because it is a ledger of decisions already shipped: it
/// constrains nothing on this line, and it grows on every bump, so readers of
/// this file were paying for the whole history to reach one constant.
const int contraTaxonomyVersion = 29;

// Shared parameter specs.
const _beats4 = ParamSpec(ParamKind.beats, defaultValue: 4);

// ContraDB chooser_down_the_hall_ender values (shared by down/up the hall).
const _downTheHallEnders = [
  'none',
  'turnCouple',
  'turnAlone',
  'circle',
  'cozy',
  'cloverleaf',
  'threadNeedle',
  'rightHandHigh',
  'slidingDoors',
  // v10: TCB writes the bend-the-line as a separate following line; the
  // CallersBox cross-line merge folds it into a preceding hall as this ender.
  'bendTheLine',
];

// hey's second pass may be any pair OR left unspecified (ContraDB
// chooser_pairz_or_unspecified). Built from the pair-level dancer sets so a
// single-dancer identity can't be selected as a "pair".
const _heyPass2Choices = [...ParamVocab.pairDancerSets, ParamVocab.unspecified];

// hey's `meetTarget` (issue #576): which pair you run a partial hey until you
// meet. ContraDB's `dancer%%N` meeting target is drawn from `chooser_pairz`
// (pairs only — never single dancers, and NOT `everyone`/`centers`, which are
// nonsensical as a hey meeting target), plus an `unspecified` sentinel default.
// chooser_pairz = pairDancerSets minus {everyone, centers}, so we spell it out
// rather than derive it, keeping the domain explicit and stable.
//
// EXTENDED beyond ContraDB at v24 (issue #732, orchestrating-session decision):
// the five mixer partner-series tokens (`prevPartners`/`nextPartners`/
// `thirdPartners`/`fourthPartners`/`fifthPartners`) are included even though
// they do not exist in ContraDB. Without them a mixer's partial hey cannot name
// the partner it runs until you meet (e.g. a hey that runs until P2). The param
// defaults to `unspecified`, so existing data is unaffected.
const _heyMeetTargetChoices = [
  'role1s',
  'role2s',
  'ones',
  'twos',
  'partners',
  'neighbors',
  'sameRoles',
  'firstCorners',
  'secondCorners',
  'shadows',
  'secondShadows',
  'prevNeighbors',
  'nextNeighbors',
  'thirdNeighbors',
  'fourthNeighbors',
  'prevPartners',
  'nextPartners',
  'thirdPartners',
  'fourthPartners',
  'fifthPartners',
  ParamVocab.unspecified,
];

// The four single-dancer identities (ContraDB chooser_dancer: 1st/2nd couple x
// role), for moves that name an individual dancer.
const _singleDancers = ParamVocab.singleDancers;

// v20 (issue #295): the pair relationship named by a TCB line, or the
// `unspecified` sentinel when the source states none. Exactly the
// `_heyMeetTargetChoices` domain (ContraDB `chooser_pairz` + the sentinel) —
// pairs only, never a single dancer, and never `everyone`/`centers`, neither of
// which can be a mad-robin target or a butterfly-whirling pair.
const _pairOrUnspecified = _heyMeetTargetChoices;

// v20 (issue #295): the rotation direction TCB states for `mad_robin` and
// `butterfly_whirl` — exactly [ParamVocab.spins] plus the `unspecified`
// sentinel, so this introduces no new vocabulary. The sentinel is the default
// because ContraDB models no direction for either move and a ContraDB import
// must keep asserting none.
//
// Both params carry the honest [ParamKind.spinDirection]. From v20 until issue
// #739 they were declared [ParamKind.choice] ONLY so they could admit the
// sentinel: the five typed dropdown kinds then rendered and validated from a
// HARDCODED vocabulary that ignored `spec.choices`, so a sentinel declared on
// one was offered nowhere and rejected by the validator. That gap is closed —
// all three consumers of the kind + `choices` contract now read
// `spec.choices ?? <fixed vocabulary>`: the figure param editor
// (`figure_param_editors.dart`) and [ParamSpec.validate] (issue #726), and the
// Advanced-search facet (`facet_labels.dart`'s `figureParamChoices`, PR #746).
// A sentinel on a typed kind is offered, stored and validated correctly, so do
// NOT reintroduce the `choice` workaround for new params.
const _spinOrUnspecified = [...ParamVocab.spins, ParamVocab.unspecified];

// v21 (issue #295): the hand a wave is held by, or the `unspecified` sentinel
// when the source states none — exactly [ParamVocab.sides] plus the sentinel,
// so this introduces no new vocabulary. Carries the honest
// [ParamKind.handedness]; see `_spinOrUnspecified` above for why it spent v21
// through #739 declared as a `choice`, and why that workaround is obsolete.
const _handOrUnspecified = [...ParamVocab.sides, ParamVocab.unspecified];

// v21 (issue #295): the pair tokens that have a nameable INVERSE — exactly
// `ParamVocab.pairInverse`'s keys, which is ContraDB's `chooser_pair` domain.
// Used by params whose rendering names the OTHER pair (`form_long_waves.who` →
// "{who} facing in, {other} facing out"), so the "other" can never resolve to
// an empty set. Spelled out because `ParamSpec.choices` must be `const`;
// `wave_balance_test.dart` asserts it stays in lockstep with `pairInverse`.
const _invertiblePairs = [
  'role1s',
  'role2s',
  'ones',
  'twos',
  'firstCorners',
  'secondCorners',
];
// v22 (gate merge): the full dancer domain plus the `unspecified` sentinel.
// The pre-merge `gate.who`/`gate.whom` carried NO `choices`, i.e. the whole
// [ParamVocab.dancerSets] domain; listing the sentinel is the only way a spec
// may admit it, so the domain is spelled as "everything it already accepted,
// plus the sentinel" rather than narrowed here. (ContraDB's own choosers are
// narrower — `chooser_pair` for the subject, `chooser_pairs_or_ones_or_twos`
// for the object — but enforcing a source's UI restrictions on stored data is
// not something this taxonomy does elsewhere, and TCB names dancers ContraDB's
// subject chooser would reject.)
const _dancerOrUnspecified = [...ParamVocab.dancerSets, ParamVocab.unspecified];

// v22 (gate merge): the TCB rotation qualifier plus the sentinel.
//
// ⚠️ This IS a `choice`, and must stay one — for a reason that has nothing to
// do with the sentinel. Its domain is `gateDirections`, which includes
// `mirror`: the two-couple gate, which has no ContraDB equivalent and which
// [ParamKind.spinDirection] (`clockwise`/`counterclockwise` only) cannot
// express. This is therefore NOT an instance of the obsolete sentinel
// workaround issue #739 unwound from `_spinOrUnspecified` /
// `_handOrUnspecified`; "finishing the job" here would silently drop `mirror`
// from the domain of every gate.
const _gateDirectionOrUnspecified = [...gateDirections, ParamVocab.unspecified];

// v22 (gate merge): ContraDB `gate_face` (the ENDING facing) plus the sentinel.
// Same four set-relative tokens `swing.endFacing` uses.
const _gateFacingOrUnspecified = [...gateFacings, ParamVocab.unspecified];

/// The seed contra move taxonomy.
///
/// This is an initial, deliberately conservative slice of the full ContraDB
/// move set (see docs/design/figure-taxonomy.md and the session extract).
/// It covers every [ParamKind], the alias mechanism, and the custom figure,
/// so the engine is exercised end-to-end. Moves whose faithful modeling needs
/// param-vocabulary extensions or open design decisions (circle/star "places",
/// hey's ten params, the ocean/long-wave family, etc.) are intentionally
/// deferred pending review — adding them is purely additive.
///
/// Divergences from ContraDB, per our design decisions:
/// - canonical roles are `role1`/`role2` (ContraDB gentlespoons/ladles);
/// - `shoulder_round` replaces gyre/gypsy (legacy names kept as keywords);
/// - rotation is expressed in full turns (0.25–2.5), not degrees (90–900).
final Taxonomy contraTaxonomy = Taxonomy(
  version: contraTaxonomyVersion,
  form: DanceForm.contra,
  moves: [
    const MoveDef(
      id: 'swing',
      displayName: 'swing',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'prefix': ParamSpec(
          ParamKind.choice,
          defaultValue: 'none',
          choices: ['none', 'balance', 'meltdown'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
        // issue #543: the body facing a swing ends in. First-class promotion of
        // what previously went in a figure note. Reuses the four set-relative
        // facing tokens (the ContraDB `gate` `face` domain / `gateFacings`);
        // defaults to `in` (across), where most swings end. Named `endFacing`
        // (not `face`) only to keep the two moves' params separately
        // addressable; since v22 the gate's `face` is known to be the same kind
        // of value (an ending facing), it just defaults to `unspecified` there.
        // Carries NO beat cost (absent from `paramBeats`) and is silenced in the
        // display renderer when `in` (see renderer.dart `_displayBaseRenderers`),
        // so the canonical `renderTemplate` below stays byte-stable.
        'endFacing': ParamSpec(
          ParamKind.choice,
          defaultValue: 'in',
          choices: ['in', 'out', 'up', 'down'],
        ),
      },
      renderTemplate: '{who} {prefix} {move}',
      goodBeats: [8, 16],
      // ContraDB swingChange: a prefixed swing (balance OR meltdown) with
      // beats <= 8 snaps to 16; swingGoodBeats narrows a prefixed swing to
      // 14..16. A plain (none) swing stays 8. Collapsed to the discrete
      // per-value defaults; beats stays user-overridable and warning-only.
      paramBeats: ParamBeats(
        param: 'prefix',
        byValue: {'none': 8, 'balance': 16, 'meltdown': 16},
      ),
    ),
    const MoveDef(
      id: 'balance',
      displayName: 'balance',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        // v25 (#870): TCB writes `(RH)` / `(LH)` on ~1,066 balance lines; the
        // hand was silently dropped because balance had no slot. Defaults to
        // `unspecified` — not `right` — because most balances state no hand, and
        // defaulting to a side would assert something the source never said.
        // Precedent: `form_long_waves.hand` (v21).
        'hand': ParamSpec(
          ParamKind.handedness,
          defaultValue: ParamVocab.unspecified,
          choices: _handOrUnspecified,
        ),
        'beats': _beats4,
      },
      renderTemplate: '{who} {move}',
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'balance_the_ring',
      displayName: 'balance the ring',
      params: {'beats': _beats4},
      renderTemplate: '{move}',
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'allemande',
      displayName: 'allemande',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 1.0),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {hand} {turn}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'do_si_do',
      displayName: 'do si do',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 1.0),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {turn}',
      searchKeywords: ['dosido', 'do-si-do'],
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'box_the_gnat',
      displayName: 'box the gnat',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        // v10: a preceding balance line folds in here via the CallersBox
        // cross-line merge (swat_the_flea inherits this through its target).
        // No paramBeats: box_the_gnat's beats stay on the deferral list.
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move}',
      goodBeats: [4],
    ),
    // ContraDB `box circulate` (figure.js): params who / balance / hand (right
    // hand spin) / beats, boxCirculateGoodBeats `beats === (bal ? 8 : 4)`.
    // Modeled 1:1 on box_the_gnat: the `balance` flag defaults FALSE (neutral —
    // a standalone line states no balance; a preceding CallersBox "balance" line
    // folds in as true, and the balanced 8-beat count comes only from that merge
    // sum, so — like box_the_gnat — no `paramBeats`). ContraDB lists box
    // circulate under moveCaresAboutPlaces for angle DISPLAY only; it carries no
    // places param here.
    const MoveDef(
      id: 'box_circulate',
      displayName: 'box circulate',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move}',
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'shoulder_round',
      displayName: 'shoulder round',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 1.0),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      // %S lets a dialect inject the shoulder side ("right shoulder round").
      renderTemplate: '{who} {move} {turn}',
      searchKeywords: ['gypsy', 'gyre'],
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'petronella',
      displayName: 'petronella',
      params: {
        'balance': ParamSpec(ParamKind.flag, defaultValue: true),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{move}',
      goodBeats: [4, 8],
      // ContraDB petronellaGoodBeats: `beats === (balance ? 8 : 4)`.
      paramBeats: ParamBeats(param: 'balance', byValue: {true: 8, false: 4}),
    ),
    const MoveDef(
      id: 'long_lines',
      displayName: 'long lines',
      params: {
        'goBack': ParamSpec(ParamKind.flag, defaultValue: true),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{move}',
      goodBeats: [4, 8],
      // ContraDB longLinesChange/GoodBeats: `beats = goBack ? 8 : 4`.
      paramBeats: ParamBeats(param: 'goBack', byValue: {true: 8, false: 4}),
    ),
    const MoveDef(
      id: 'pass_through',
      displayName: 'pass through',
      params: {
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'along'),
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 2),
      },
      renderTemplate: '{move} {dir}',
      goodBeats: [2],
    ),
    const MoveDef(
      id: 'right_left_through',
      displayName: 'right left through',
      params: {
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{move} {dir}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'chain',
      displayName: 'chain',
      params: {
        'who': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'role2s',
          choices: ['role1s', 'role2s'],
        ),
        // v28 (#976): ContraDB's `by_right_hand` (`figure.js:281-291`) is a
        // fourth param we never modelled, so a stated hand — including one
        // that CONTRADICTS the implicit role reading (`women do a left-hand
        // ladies chain`) — fell all the way to `custom`. Defaults to
        // `unspecified`, not the role-implied side: a role-conditional
        // taxonomy default would be a stored value that goes stale the moment
        // `who` is edited afterward (no equivalent of ContraDB's
        // `chainChange`, `figure.js:256-263`, exists at the taxonomy layer).
        // The role-implied side is instead written explicitly, by
        // [chainHandForWho], at every write site that actually reads a role
        // word: both parsers, the editor's `_selectMove` (×2) and its `who`
        // reaction in `_applyNonBeatsParamChange`, and the one-time backfill
        // sweep — never here. `unspecified` remains the taxonomy default only
        // so pre-release figures (and any bare, role-less chain — #976
        // §6.1.3) keep a defined effective value.
        'hand': ParamSpec(
          ParamKind.handedness,
          defaultValue: ParamVocab.unspecified,
          choices: _handOrUnspecified,
        ),
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      // Hand precedes move, matching ContraDB's `chainWords`
      // (`words(sdiag, swho, thand, smove)`, `figure.js:266-278`) and the live
      // render ("ladles left-hand chain") — NOT `{who} {move} {hand} {dir}`,
      // which would read "ladies chain left across". `dir`'s position is
      // unchanged; ContraDB puts the diagonal first, but matching that would
      // reword all displayed diagonal chains for an unrelated reason.
      renderTemplate: '{who} {hand} {move} {dir}',
      goodBeats: [8],
    ),
    // v23: The Caller's Box's standalone courtesy turn. ContraDB models this
    // figure NOWHERE (0 hits repo-wide for "courtesy" at contradb/contra @
    // master) — it treats the courtesy turn as an unparameterized sub-component
    // of `chain` and `right left through`, neither of which carries a slot for
    // it. TCB instead writes it as its own figure line 115 times across the
    // 24,107-dance corpus, which is what this move exists to hold.
    //
    // NOT a chain, and never emitted by one. 30 corpus lines write both
    // together (`[W1+W2] Ladies chain, with half courtesy turn in center`,
    // `Ladies chain to partner with double courtesy turn`, `Right and left
    // through with partner with double courtesy turn`, `Neighbor promenade
    // across with double courtesy turn`). Those stay whole-`custom`: a chain
    // line that also emitted a standalone `courtesy_turn` would double-count
    // both the figure and its beats, and — since neither our `chain` nor
    // ContraDB's has a courtesy-turn parameter — there is no slot in either
    // model for the qualifier to ride in. The recognizer's whole-line contract
    // enforces this by construction (the leftover `chain`/`with`/`double`
    // tokens decline the line); no exclusion logic is needed and none is
    // written.
    const MoveDef(
      id: 'courtesy_turn',
      displayName: 'courtesy turn',
      params: {
        // The pairing the turn is danced with — TCB states it on every line
        // (partner x53, neighbor x39, N2 neighbor x13, shadow/N3 neighbor/twos
        // x1 each). `partners` is the mode, used as the authoring default; a
        // recognizer that falls back to it marks the figure `assumedSubject`.
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        // The dancer being turned, when a source names a turner AND a turnee.
        // NO SOURCE DOES: searching the corpus for `<X> courtesy turn <Y>`
        // finds nothing, so `who` always names the pairing and this slot is
        // never filled on import. It exists for manual authoring, per the
        // maintainer's ruling that `whom` be "left out by default unless it
        // actually shows up in parsing data". Full dancer domain plus the
        // sentinel, exactly like `gate.who`/`gate.whom` (v22).
        'whom': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _dancerOrUnspecified,
        ),
        // The rotation sense. A courtesy turn wheels clockwise by construction,
        // and all 10 corpus lines that state a direction say `clockwise` —
        // `counterclockwise` is unattested — so `clockwise` is a REAL default
        // rather than a fabricated one, and the display renderer says nothing
        // when it holds.
        //
        // ⚠️ DELIBERATELY NO `unspecified` SENTINEL — but only because this
        // move has no semantic need for one, NOT because a sentinel would be
        // unsafe on a typed kind. It once was: `ParamKind.spinDirection` used
        // to render from a hardcoded `ParamVocab.spins` that ignored
        // `spec.choices`, and `_dropdown`'s reconciliation pushes a substitute
        // value back into the draft via `addPostFrameCallback`, so merely
        // OPENING the editor on a sentinel-bearing spinDirection would have
        // silently rewritten "the source stated nothing" into "clockwise" —
        // the exact class of bug #724 fixed at the UI layer. That gap is
        // CLOSED. All three consumers of the kind + `choices` contract now read
        // `spec.choices ?? <fixed vocabulary>`: the figure param editor
        // (`figure_param_editors.dart`) and [ParamSpec.validate] (issue #726),
        // and the Advanced-search facet (`facet_labels.dart`'s
        // `figureParamChoices`, PR #746). A sentinel on a typed kind is
        // therefore offered, stored and validated correctly.
        //
        // ⚠️ The corollary: declaring a param `ParamKind.choice` PURELY so it
        // can admit the sentinel is an OBSOLETE workaround — do not copy it
        // into new params. Issue #739 unwound the three declarations that used
        // it: `form_long_waves.hand` (via `_handOrUnspecified`) now carries
        // `ParamKind.handedness`, and `mad_robin.direction` /
        // `butterfly_whirl.direction` (via `_spinOrUnspecified`) now carry
        // `ParamKind.spinDirection` — each still listing the sentinel in
        // `choices`. The one sentinel-bearing `choice` that REMAINS,
        // `gate.direction`, is not an instance of the workaround: its domain
        // includes `mirror`, which no typed kind can express (see
        // `_gateDirectionOrUnspecified`). THIS param keeps the honest
        // `ParamKind.spinDirection` and no sentinel because a courtesy turn
        // wheels clockwise by construction, so `clockwise` is a real default
        // rather than a fabricated one.
        'direction': ParamSpec(
          ParamKind.spinDirection,
          defaultValue: 'clockwise',
        ),
        // ⚠️ THIS IS A DANCER, NOT A FACING — do not read it as `swing.endFacing`.
        // The names match; the domains do not. `swing.endFacing` (issue #543)
        // and `gate.face` (v22) hold the four set-relative cardinals
        // (`in`/`out`/`up`/`down`, i.e. `gateFacings`). THIS param holds a
        // dancer relationship, because that is what the source states: all 13
        // corpus lines with an in-line ending facing write `, face N2` (x8),
        // `, face N3` (x4) or `, face N0` (x1), which `tcbPassPeople` maps to
        // `nextNeighbors` / `thirdNeighbors` / `prevNeighbors`.
        //
        // The corpus DOES also contain cardinal facings — `Ones courtesy turn;
        // face down`, `Partner courtesy turn (power turn); face out`, `Partner
        // courtesy turn 2; face clockwise around the major set` — but every one
        // of them uses a SEMICOLON, and `parseFigureLines`' all-or-nothing
        // `;`-compound rule keeps such a line whole-`custom` (its `; face down`
        // clause structures to nothing). They therefore never reach this slot.
        // Stated explicitly because it is a live hazard: anyone who later
        // loosens that `;` handling would start feeding `down`/`out` into a
        // dancer domain. If a cardinal ending facing is ever genuinely needed
        // here it needs its OWN param, not this one.
        //
        // Full dancer domain plus the sentinel (cf. `gate.who`/`gate.whom`):
        // the recognizer only ever fills what a line states, so widening the
        // domain beyond the three attested tokens fabricates nothing.
        'endFacing': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _dancerOrUnspecified,
        ),
        'beats': _beats4,
      },
      // Canonical (dedupe/FTS) line, deliberately FLAT — a `renderTemplate`
      // cannot express a conditional. The maintainer's stated wording
      // (`{who} courtesy turn {whom, when present} {direction, when not
      // clockwise} {"to face" + endFacing, when set}`) is the DISPLAY render
      // and lives in `renderer.dart`'s `_displayBaseRenderers`, exactly as the
      // merged `gate`'s "to face …" clause does. `whom`/`endFacing` are the
      // `unspecified` sentinel unless stated and render as the empty string, so
      // an imported line reads "partners courtesy turn clockwise" — carrying
      // the default direction the same way `right_left_through` carries its
      // default `across`. `direction` stays IN the canonical text (rather than
      // being display-only like `swing.endFacing`) because that omission was a
      // byte-stability concession a brand-new move does not need, and without
      // it a counterclockwise courtesy turn would dedupe as identical to a
      // clockwise one.
      renderTemplate: '{who} {move} {whom} {direction} {endFacing}',
      // DEFINE THE POPULATION BEFORE ARGUING ABOUT THE TAIL. This list is drawn
      // from the 115 lines this move's GRAMMAR CLAIMS, not from the 228 lines a
      // grep for "courtesy turn" returns — and the two disagree at exactly the
      // margins where a `goodBeats` judgement call feels hardest. Over the
      // claimable population: 4 x97, 2 x8, 3 x6, 6 x4. Over the grep
      // population, a `5` and five `8`s also appear, and both are artifacts:
      // the `5` is `(5) Neighbor promenade across; courtesy turn 3/4` (a `;`
      // compound, kept whole-custom) and the `8`s are
      // `right and left through …("courtesy fling")` lines, which are not
      // courtesy turns at all. Including either would have weakened the
      // atypical-beat warning for every author, to fit data this move never
      // sees. The lesson generalizes past this param: when a corpus statistic
      // decides a taxonomy value, measure the set the code will actually act
      // on.
      //
      // The genuinely marginal values (2, 3, 6) were then checked in context
      // rather than assumed, per the v22 precedent, and are all real timing —
      // see the version-history entry above for the three dances.
      goodBeats: [2, 3, 4, 6],
    ),
    const MoveDef(
      id: 'promenade',
      displayName: 'promenade',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        // Issue #634: a true "single file promenade" travels the whole major
        // set (no per-couple dancer relationship), vs. the ordinary partnered
        // promenade. A canonical render token since taxonomy v27 (issue #749):
        // the display renders show "single file promenade [dir]" when true;
        // canonical emits "single file promenade [dir]" with `who` dropped
        // (an importer artefact carrying no choreographic information).
        'singleFile': ParamSpec(ParamKind.flag, defaultValue: false),
        // Issue #921 (taxonomy v29): destination of the single-file promenade —
        // "to new neighbors" / "to the same neighbors" / etc. Reuses the
        // dancerSet domain + unspecified sentinel. Only meaningful when
        // `singleFile` is true; the ordinary promenade has no destination.
        // Rendered as "to {destination}" appended to the singleFile display and
        // canonical forms; unspecified (= "not stated") suppresses the clause.
        'destination': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _dancerOrUnspecified,
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {dir}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'roll_away',
      displayName: 'roll away',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        // ContraDB roll_away's `whom` (chooser_pairs_or_ones_or_twos): the
        // relationship being rolled away.
        'whom': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'halfSashay': ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move} {whom}',
      goodBeats: [4],
    ),
    // --- Roadmap 2.4a: simple moves (PR1) ---
    // Additive ContraDB moves that fit the existing ParamKind set (no new
    // vocabulary). ContraDB params with "no default" (which force a chooser
    // selection in that editor) get sensible community defaults here, since
    // our ParamSpec requires one.
    const MoveDef(
      id: 'butterfly_whirl',
      displayName: 'butterfly whirl',
      params: {
        // v20 (#295): the whirling pair. TCB names it on 18/18 sampled lines
        // ("Partner butterfly whirl counterclockwise"; glossary: "TWO PEOPLE
        // face the same direction…"), while ContraDB models `beats` alone — so
        // the `unspecified` sentinel default keeps a ContraDB import, and every
        // figure stored before v20, asserting nothing.
        'who': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _pairOrUnspecified,
        ),
        // v20 (#295): TCB glossary — "…and ROTATE CLOCKWISE OR
        // COUNTERCLOCKWISE about a common center"; stated on 18/18 sampled
        // lines. No rotation AMOUNT param: TCB states one on only 4/18 lines
        // and neither ContraDB nor the glossary models it, so those lines stay
        // `custom` (prefer-custom) and `goodBeats` stays `[4]`.
        'direction': ParamSpec(
          ParamKind.spinDirection,
          defaultValue: ParamVocab.unspecified,
          choices: _spinOrUnspecified,
        ),
        'beats': _beats4,
      },
      renderTemplate: '{who} {move} {direction}',
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'arch_and_dive',
      displayName: 'arch and dive',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'beats': _beats4,
      },
      renderTemplate: '{who} {move}',
      searchKeywords: ['arch & dive'],
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'california_twirl',
      displayName: 'California twirl',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'beats': _beats4,
      },
      renderTemplate: '{who} {move}',
      goodBeats: [4],
    ),
    // `star_through`: modeled on `california_twirl` — who + beats only, no
    // `balance` and no `hand` param. Per product decision star through now
    // mirrors california twirl exactly (aside from the name): its handedness is
    // role-fixed like california twirl, and it carries no balance (ContraDB does
    // not model star through, and CallersBox aligns it with california twirl).
    const MoveDef(
      id: 'star_through',
      displayName: 'star through',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'beats': _beats4,
      },
      renderTemplate: '{who} {move}',
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'stand_still',
      displayName: 'stand still',
      params: {'beats': ParamSpec(ParamKind.beats, defaultValue: 8)},
      renderTemplate: '{move}',
      // No goodBeats: any in-domain beat count (0..64) is accepted without a
      // warning. ContraDB's "beats >= 1" min-rule isn't expressible in the
      // list-based goodBeats model and is not enforced here.
    ),
    const MoveDef(
      id: 'slide_along_set',
      displayName: 'slide along set',
      params: {
        'slide': ParamSpec(
          ParamKind.choice,
          defaultValue: 'left',
          choices: ['left', 'right'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 2),
      },
      renderTemplate: '{move} {slide}',
      goodBeats: [2],
    ),
    const MoveDef(
      id: 'mad_robin',
      displayName: 'mad robin',
      params: {
        // ContraDB `subject_pair`: which pair steps IN FRONT first
        // (`madRobinWords` renders "<who> in front"). A DIFFERENT concept from
        // `whom` below — do not conflate them.
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        // ContraDB `once_around`/`circling`: how far you travel around
        // (1.0 == 360°, ContraDB's default). TCB writes "1 & 1/2" / "1/2".
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 1.0),
        // v20 (#295): TCB glossary — "a CLOCKWISE mad robin begins with the
        // left-hand person going in front"; stated on 24/24 sampled lines.
        'direction': ParamSpec(
          ParamKind.spinDirection,
          defaultValue: ParamVocab.unspecified,
          choices: _spinOrUnspecified,
        ),
        // v20 (#295): TCB's "around <whom>" — the pair you travel around. TCB
        // glossary: "you travel in an oval AROUND THE PERSON AT YOUR SIDE…
        // **Who you go around is listed**"; stated on 24/24 sampled lines.
        // ContraDB has no slot for it, hence the `unspecified` sentinel.
        'whom': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _pairOrUnspecified,
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 6),
      },
      renderTemplate: '{who} {move} {turn} {direction} {whom}',
      goodBeats: [6, 8],
    ),
    const MoveDef(
      id: 'revolving_door',
      displayName: 'revolving door',
      params: {
        // The dancers who take hands and lead the figure. Canonically the
        // ladles (role2s) — they take right hands and drop off partners on the
        // far side (verified: ContraDB #2443 + libfigure `revolving door`; and
        // the TCB decomposition's "Women allemande right", women → role2s).
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'role2s'),
        // Canonical revolving door takes RIGHT hands (partner star promenade →
        // women allemande right). ContraDB models this move's hand as a param;
        // the community-canonical value is right.
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        // Whom the leaders drop off on the other side — their partners.
        'whom': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {hand} {whom}',
      goodBeats: [8],
    ),
    // v26 (#843): `who` names the dancer you PICK UP on the side (TCB's
    // reading, per the owner's 2026-08-06 ruling) — NOT the pair with a hand in
    // the center. The `hand` param was removed with this ruling: it described
    // the center pair while rendering as though it qualified `who`. The center
    // survives as a note written by the TCB import; see the v26 entry above.
    const MoveDef(
      id: 'star_promenade',
      displayName: 'star promenade',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s'),
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 0.5),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move} {turn}',
      goodBeats: [4],
    ),
    // Issue #295: `orbit` is a first-class move. The fused `allemande_orbit`
    // (X allemande while Y orbits) was RETIRED at taxonomy v19 and its stored
    // figures migrated to `meanwhile[allemande, orbit]` (CompendiumDatabase
    // schema v18). TCB writes the orbit side standalone, e.g. "Men orbit
    // clockwise 1/2" / "Women orbit counterclockwise 1/2" (ContraDB has no
    // standalone orbit — only the combined allemande orbit — so TCB is the
    // source). `turn` reuses the EXISTING `ParamKind.spinDirection`
    // (clockwise/counterclockwise); `amount` is the orbiter's turn fraction,
    // defaulting to 0.5 to match the old fused `outer`.
    const MoveDef(
      id: 'orbit',
      displayName: 'orbit',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'turn': ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
        'amount': ParamSpec(ParamKind.rotation, defaultValue: 0.5),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {turn} {amount}',
      goodBeats: [8],
    ),
    // --- Roadmap 2.4a: dancer-interaction moves (PR2) ---
    // Additive ContraDB moves that fit the existing ParamKind set (no new
    // vocabulary). ContraDB "no default" choosers get sensible community
    // defaults, since ParamSpec.defaultValue is required.
    // --- v22: the UNIFIED gate (was ContraDB `gate` + TCB `rotation_gate`) ---
    //
    // ONE move carrying a direction, a duration and an ENDING FACING, per the
    // maintainer ruling. The v15 premise that "the two gate vocabularies are
    // disjoint" rested on a misreading of libfigure that is corrected here:
    // ContraDB's `face` is not a travel direction, it is the ending facing, so
    // the two sources were never in conflict — they state COMPLEMENTARY halves
    // of the same figure. ContraDB says how the gate ENDS and never states an
    // amount; TCB says which way and HOW FAR it turns and never states a
    // facing. Every slot therefore defaults to the `unspecified` sentinel: each
    // source fills only what it actually states, and the user corrects the
    // rest.
    //
    // libfigure (github.com/contradb/contra @ master):
    //   figure.js:844  // 'ones gate twos' means: ones, extend a hand to twos -
    //                  // twos walk forward, ones back up, orbiting around the
    //                  // joined hands
    //   figure.js:841  words(ssubject, smove, sobject, "to face", sgate_face)
    //   param.js:711   {up:"up the set", down:"down the set",
    //                   in:"into the set", out:"out of the set"}
    //   chooser.js:114 chooser_pair = [gentlespoons, ladles, ones, twos,
    //                   first corners, second corners]   <- never neighbors/partners
    //
    // ⚠️ THE TRAP THAT CAUSED THE ORIGINAL MISREADING — do not fall into it
    // again. `param.js:714` declares the param as:
    //     defineParam("gate_face", { name: "face", ui: "chooser_gate_direction", … })
    // The `ui:` value is a UI-WIDGET HINT, not the param's meaning. Reading
    // "chooser_gate_direction" as "this is a direction of travel" is exactly how
    // "which way `who` orbits `whom`" got written into this file and then copied
    // into the v15 and v16 version-history entries. The param's `name` is
    // "face", it renders after the literal words "to face", and its value
    // strings are facings. Trust `name` + `words()` + the value strings; treat
    // `ui:` as presentation only.
    const MoveDef(
      id: 'gate',
      displayName: 'gate',
      params: {
        // ContraDB `subject_pair`: the side that EXTENDS THE HAND AND BACKS UP
        // (figure.js:844). NOT the orbiting side — the mover is `whom`.
        // ContraDB's own `chooser_pair` domain is role-sides only
        // (gentlespoons/ladles/ones/twos/corners — never `partners`/
        // `neighbors`), which is precisely why TCB's relationship subject
        // cannot live here; see `pair` below.
        'who': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _dancerOrUnspecified,
        ),
        // ContraDB `object_pairs_or_ones_or_twos`: the side that WALKS FORWARD.
        // TCB states the same thing in its "(ones forward)" parenthetical.
        'whom': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _dancerOrUnspecified,
        ),
        // v22: the PAIRING the gate is danced with — TCB's subject ("Neighbor
        // gate…", "Partner gate…", "N2 neighbor gate…", "Shadow gate…"). A
        // THIRD axis: it names who you gate WITH, not which of you moves, so
        // folding it into `who` would silently reinterpret every TCB-imported
        // gate as a claim about which side backs up. ContraDB has no slot for
        // it. Directly precedented by `mad_robin.whom` (v20), which exists for
        // the same reason.
        'pair': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _pairOrUnspecified,
        ),
        // TCB rotation qualifier. A dedicated choice (NOT
        // ParamKind.spinDirection, which is cw/ccw only and cannot express the
        // two-couple `mirror` gate). ContraDB models no rotation sense.
        'direction': ParamSpec(
          ParamKind.choice,
          defaultValue: ParamVocab.unspecified,
          choices: _gateDirectionOrUnspecified,
        ),
        // Turn fraction in full turns (1/2 -> 0.5, 3/4 -> 0.75, 1 -> 1.0,
        // "1 & 1/4" -> 1.25). The one ParamKind.rotation that opts into the
        // `unspecified` sentinel (see ParamSpec.validate): ContraDB's gate has
        // no amount param at all, so any numeric default would fabricate one
        // for every ContraDB import.
        'turn': ParamSpec(
          ParamKind.rotation,
          defaultValue: ParamVocab.unspecified,
          choices: [ParamVocab.unspecified],
        ),
        // The facing the gate ENDS in — ContraDB `gate_face`, authored and
        // STORED (v22). Previously derived at render time from a nominal `in`
        // start orientation, which is wrong after any orientation-changing
        // figure: a 1/2 gate following a down-the-hall ends facing UP, but the
        // derivation always claimed `out`. A start-relative rule cannot yield
        // an absolute cardinal without simulating the preceding choreography,
        // so the derivation is withdrawn and the value is stored instead.
        'face': ParamSpec(
          ParamKind.choice,
          defaultValue: ParamVocab.unspecified,
          choices: _gateFacingOrUnspecified,
        ),
        // ContraDB pins 8 (`beats_8`); TCB is variable and layers the source
        // line's own count on top. The default applies only to a beats-absent
        // line.
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      // Canonical (byte-stable) line. Every `unspecified` slot renders empty
      // and the runs collapse, so a ContraDB gate reads "ones gate neighbors
      // up" and a TCB gate reads "neighbors gate mirror once" — each
      // byte-identical to what its own predecessor move produced, which keeps
      // dedupe/FTS text stable across the merge. `who` and `pair` both precede
      // the move name because they are alternative grammatical subjects (a
      // source fills one or the other, never both). The display renderer
      // rewords `mirror` ahead of the move name and expands `face` into
      // ContraDB's "to face …" clause (see renderer.dart
      // `_displayBaseRenderers`); canonical stays template-driven.
      renderTemplate: '{who} {pair} {move} {whom} {direction} {turn} {face}',
      searchKeywords: ['rotation gate', 'mirror gate'],
      // ContraDB pins 8. TCB's 24,107-dance corpus attests 8x122, 4x33, 6x15,
      // 2x13 and 3x3 across its 186 gate lines.
      //
      // `3` was checked before being included, since a spurious `goodBeats`
      // entry quietly weakens the atypical-beat warning for everyone. All three
      // lines (TCB #6819, #20257, #19476) are the SAME real pattern — a 6-beat
      // compound split evenly into 3 + 3:
      //     (6) Modified right and left through with partner:
      //          (3) Pass through across (NR)
      //          (3) Partner gate counterclockwise 1/2
      // Not truncation or a typo, and our own importer emits those children
      // with those beats (the compound-children rule, #295/PR #712) — so
      // excluding `3` would fire a warning on real imported data.
      goodBeats: [2, 3, 4, 6, 8],
    ),
    const MoveDef(
      id: 'give_and_take',
      displayName: 'give & take',
      params: {
        // chooser_role: the giving role.
        'who': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'role1s',
          choices: ['role1s', 'role2s'],
        ),
        'whom': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        // `give` == false is ContraDB's "take only". Like other beat-shaping
        // flags (roll_away.halfSashay, long_lines.goBack) it is not a render
        // token; the give/take wording is a display nuance, not canonical text.
        'give': ParamSpec(ParamKind.flag, defaultValue: true),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {whom}',
      searchKeywords: ['give and take', 'take'],
      // ContraDB range is give -> 4-8, take-only -> 2-4. Issue #634's
      // real-render fixtures confirm take-only at BOTH ends of that range (2
      // beats: The Erik Effect #570; 4 beats: Green Lake Twirl #548), so `2`
      // joins the prior two canonical counts (4 = take only, 8 = give & take).
      goodBeats: [2, 4, 8],
    ),
    const MoveDef(
      id: 'pull_by_dancers',
      displayName: 'pull by',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 2),
      },
      renderTemplate: '{who} {move} {hand}',
      searchKeywords: ['pull by dancers'],
      goodBeats: [2, 4],
    ),
    const MoveDef(
      id: 'pull_by_direction',
      displayName: 'pull by',
      params: {
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'along'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 2),
      },
      renderTemplate: '{move} {dir} {hand}',
      searchKeywords: ['pull by direction'],
      goodBeats: [2, 4],
    ),
    const MoveDef(
      id: 'cross_trails',
      displayName: 'cross trails',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        // Available for %S dialect injection (cf. pass_through/shoulder_round);
        // intentionally not a render token.
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        'who2': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move} {dir} {who2}',
      searchKeywords: ['cross trail'],
      goodBeats: [4],
    ),
    // --- Roadmap 2.4a: choice-enum moves (PR3) ---
    // Additive ContraDB moves whose variants are move-specific enums
    // (ParamKind.choice). Secondary modifiers — enders, figure-8 `dir`, embedded
    // custom text (contra_corners/turn_alone), the who-coupled `moving`, and the
    // single-dancer `lead` — are structured params but NOT render-template
    // tokens: the terse canonical line carries the identifying phrase, while
    // these are surfaced by the verbose/dialect renderer (design-doc TODO) and
    // structural search. Swing's `prefix` follows the same "no literal sentinel
    // words" rule (its `none` renders to nothing) even though it is now a
    // render-template token (see the swing MoveDef); several of the choices
    // below likewise include a "none"/unspecified value.
    const MoveDef(
      id: 'down_the_hall',
      displayName: 'down the hall',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'everyone'),
        // Who moves; ContraDB couples this to `who` (everyone <-> all).
        'moving': ParamSpec(
          ParamKind.choice,
          defaultValue: 'all',
          choices: ['all', 'center', 'outsides'],
        ),
        'facing': ParamSpec(
          ParamKind.choice,
          defaultValue: 'forward',
          choices: ['forward', 'forwardThenBackward', 'backward'],
        ),
        'ender': ParamSpec(
          ParamKind.choice,
          defaultValue: 'turnCouple',
          choices: _downTheHallEnders,
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {facing}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'up_the_hall',
      displayName: 'up the hall',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'everyone'),
        'moving': ParamSpec(
          ParamKind.choice,
          defaultValue: 'all',
          choices: ['all', 'center', 'outsides'],
        ),
        'facing': ParamSpec(
          ParamKind.choice,
          defaultValue: 'forward',
          choices: ['forward', 'forwardThenBackward', 'backward'],
        ),
        'ender': ParamSpec(
          ParamKind.choice,
          defaultValue: 'circle',
          choices: _downTheHallEnders,
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {facing}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'zig_zag',
      displayName: 'zig zag',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'turn': ParamSpec(
          ParamKind.choice,
          defaultValue: 'left',
          choices: ['left', 'right'],
        ),
        // Default "none": structured, not a render token.
        'ender': ParamSpec(
          ParamKind.choice,
          defaultValue: 'none',
          choices: ['none', 'ring', 'allemande'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 6),
      },
      renderTemplate: '{who} {move} {turn}',
      goodBeats: [6],
    ),
    const MoveDef(
      id: 'slice',
      displayName: 'slice',
      params: {
        'slice': ParamSpec(
          ParamKind.choice,
          defaultValue: 'left',
          choices: ['left', 'right'],
        ),
        'by': ParamSpec(
          ParamKind.choice,
          defaultValue: 'couple',
          choices: ['couple', 'dancer'],
        ),
        'return': ParamSpec(
          ParamKind.choice,
          defaultValue: 'straight',
          choices: ['straight', 'diagonal', 'none'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{move} {slice} {by} {return}',
      // ContraDB sliceGoodBeats/sliceChange: `beats === (return === 'none' ? 4
      // : 8)` — a returning slice (straight/diagonal) is 8 beats, no return 4.
      goodBeats: [4, 8],
      paramBeats: ParamBeats(
        param: 'return',
        byValue: {'straight': 8, 'diagonal': 8, 'none': 4},
      ),
    ),
    const MoveDef(
      id: 'contra_corners',
      displayName: 'contra corners',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        // Embedded turning-figure text; structured (the value humanizer would
        // mangle free-text case), surfaced by the verbose renderer.
        'custom': ParamSpec(ParamKind.text, defaultValue: ''),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 16),
      },
      renderTemplate: '{who} {move}',
      goodBeats: [16],
    ),
    const MoveDef(
      id: 'turn_alone',
      displayName: 'turn alone',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'everyone'),
        'custom': ParamSpec(ParamKind.text, defaultValue: ''),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move}',
      // ContraDB turnAlone uses goodBeatsMinMaxFn(0, 4) — a pure 0..4 range
      // with no driver param and no `change` function, so beats are NOT
      // param-value-dependent. Left unset (any in-domain count accepted); no
      // paramBeats (nothing discrete to derive).
    ),
    const MoveDef(
      id: 'figure_8',
      displayName: 'figure 8',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        // Default "none": structured, not a render token.
        'dir': ParamSpec(
          ParamKind.choice,
          defaultValue: 'none',
          choices: ['none', 'above', 'below', 'across'],
        ),
        // Single-dancer lead (ContraDB "first ladle" = ones' role2).
        'lead': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'onesRole2',
          choices: ['onesRole1', 'onesRole2', 'twosRole1', 'twosRole2'],
        ),
        'half': ParamSpec(ParamKind.fraction, defaultValue: 'half'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {half}',
      // ContraDB figure8GoodBeats: `beats === half_or_full * 16` (an exact
      // equality, and figure8Change auto-sets it on a fraction flip): half
      // (0.5) -> 8, full (1.0) -> 16.
      goodBeats: [8, 16],
      paramBeats: ParamBeats(param: 'half', byValue: {'half': 8, 'full': 16}),
    ),
    const MoveDef(
      id: 'poussette',
      displayName: 'poussette',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'whom': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'half': ParamSpec(ParamKind.fraction, defaultValue: 'half'),
        'turn': ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 6),
      },
      renderTemplate: '{who} {move} {whom} {half} {turn}',
      // ContraDB poussetteGoodBeats is a RANGE, `6 <= beats/(2*half_or_full) <=
      // 8` (half -> 6-8, full -> 12-16), and — unlike figure_8/hey — poussette
      // has NO `change` function, so ContraDB never auto-recomputes its beats
      // on a fraction flip. There is no single canonical per-value count, so no
      // paramBeats: beats stay on the flat default (6) unless set manually. The
      // two disjoint ranges also can't be expressed by the list-based goodBeats.
    ),
    const MoveDef(
      id: 'rory_o_more',
      displayName: "Rory O'More",
      params: {
        'who': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'everyone',
          choices: ['everyone', 'role1s', 'role2s', 'centers', 'ones', 'twos'],
        ),
        'balance': ParamSpec(ParamKind.flag, defaultValue: true),
        'slide': ParamSpec(
          ParamKind.choice,
          defaultValue: 'right',
          choices: ['left', 'right'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {slide}',
      searchKeywords: ['rory o more', 'rory'],
      // ContraDB roryOMoreGoodBeats/roryOMoreChange: `beats === (balance ? 8 :
      // 4)` — a balanced Rory O'More is 8 beats, without the balance 4.
      goodBeats: [4, 8],
      paramBeats: ParamBeats(param: 'balance', byValue: {true: 8, false: 4}),
    ),
    // --- Roadmap 2.4a: places family (PR4) ---
    // Moves whose travel is measured in "places" around a ring/star
    // (ParamKind.places, int 1..10). Each move keeps a simple typical-beats
    // list in goodBeats, but ContraDB's *conditional* rules — square through's
    // 2-4 place restriction and the moves' param-dependent places/beats ratios
    // — are intentionally not encoded/enforced (they can't be captured by the
    // list model without false warnings; cf. poussette). box_circulate is
    // intentionally NOT here: it carries no places param (ContraDB lists it
    // under moveCaresAboutPlaces only for angle display).
    //
    // No paramBeats for the places family: ContraDB derives beats from a
    // continuous RATIO on the places-as-angle encoding (circleGoodBeats /
    // starGoodBeats / facingStarGoodBeats: `angle/beats === 45`, i.e. one place
    // per two beats) plus a special RANGE case (270deg / 3 places accepted at
    // 6-8 beats), and square_through has its own multi-param expected-beats
    // formula. That is a ratio/range over an int 1..10 domain, not a discrete
    // per-value count, so it can't populate a clean paramBeats map — deferred.
    const MoveDef(
      id: 'circle',
      displayName: 'circle',
      params: {
        'turn': ParamSpec(
          ParamKind.choice,
          defaultValue: 'left',
          choices: ['left', 'right'],
        ),
        'places': ParamSpec(ParamKind.places, defaultValue: 4),
        // Issue #634: ContraDB free text occasionally renders a single-file
        // circulation around the ring as "promenade single file around the
        // circle N places" (real render: Travels with Rick and Kim #455) — a
        // single-file circle, not the `promenade` move (no separate
        // `circle_left` id exists in this taxonomy; `turn` already covers
        // left/right). A canonical render token since taxonomy v27 (issue
        // #749 / #840): display renders prefix "single file circle clockwise N
        // places"; canonical emits "single file promenade clockwise N places
        // (circle)" — the parenthetical retains "circle" in the FTS index.
        'singleFile': ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{move} {turn} {places}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'star',
      displayName: 'star',
      params: {
        // ContraDB forces a hand selection (no default); 'right' is the
        // community default.
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'places': ParamSpec(ParamKind.places, defaultValue: 4),
        // grip is a canonical render token since taxonomy v27 (issue #749):
        // emitted in ALL render paths (render / renderVerbose / renderSummary /
        // renderCanonical) as a " - wrist grip - " / " - hands across - " clause
        // (ContraDB `starWords` parity). 'none' is the unspecified value — no
        // clause in any render path. The FTS inclusion makes stars searchable
        // by "wrist grip" or "hands across".
        'grip': ParamSpec(
          ParamKind.choice,
          defaultValue: 'none',
          choices: ['none', 'wristGrip', 'handsAcross'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{move} {hand} {places}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'facing_star',
      displayName: 'facing star',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'turn': ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
        'places': ParamSpec(ParamKind.places, defaultValue: 3),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {turn} {places}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'square_through',
      displayName: 'square through',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'who2': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'balance': ParamSpec(ParamKind.flag, defaultValue: true),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        // ContraDB restricts to 2-4 places; that restriction is typical-only
        // (the domain stays the full 1..10), not enforced.
        'places': ParamSpec(ParamKind.places, defaultValue: 4),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 16),
      },
      renderTemplate: '{who} {move} {places}',
      goodBeats: [16],
    ),
    // --- Roadmap 2.4a: hey / wave family (PR5) — completes the 2.4a set ---
    // The heys and wave-formations. All fit the existing ParamKind set (no new
    // vocabulary). ContraDB attaches rich "words" functions and editor-only
    // auto-beat recomputation to these; we keep the identifying phrase in the
    // canonical template and hold the descriptive modifiers (ricochet flags,
    // hey length, direction, wave in/out/balance flags, ocean-wave hands) as
    // structured params for the verbose renderer + structural search. ContraDB
    // conditional beat rules aren't encoded (goodBeats carries a simple typical
    // list or is omitted, cf. poussette).
    const MoveDef(
      id: 'pass_by',
      displayName: 'pass by',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        // Available for %S dialect injection (cf. pass_through); structured.
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 2),
      },
      renderTemplate: '{who} {move}',
      goodBeats: [2],
    ),
    const MoveDef(
      id: 'hey',
      displayName: 'hey',
      params: {
        // Which pair starts in the center (ContraDB ladles -> role2s).
        'pass1': ParamSpec(ParamKind.dancerSet, defaultValue: 'role2s'),
        // Full set of ContraDB named hey-length durations. The dynamic
        // dancer%%N meeting *target* is now captured by `meetTarget` (issue
        // #576); `length` retains only the meeting *count* (partial → 1st/2nd
        // meeting). Ordered ahead of `pass2` because callers almost always set
        // the hey length, whereas `pass2` usually stays 'unspecified' —
        // surfacing length in the inline (first-3) fields saves a trip into
        // "More options".
        'length': ParamSpec(
          ParamKind.choice,
          defaultValue: 'half',
          choices: ['lessThanHalf', 'half', 'betweenHalfAndFull', 'full'],
        ),
        // issue #576: which pair you run the hey until you meet, meaningful only
        // for the two partial lengths (`lessThanHalf`/`betweenHalfAndFull`).
        // ContraDB's `dancer%%N` meeting target (chooser_pairz); default
        // `unspecified` keeps existing data + beat math byte-stable (the
        // renderer only names the target when set; beats stay driven by
        // `length`). Ordered right after `length` so the editor can surface it
        // inline the moment a partial length is chosen.
        'meetTarget': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _heyMeetTargetChoices,
        ),
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        // The ends pair, or 'unspecified' (ContraDB chooser_pairz_or_unspecified).
        'pass2': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _heyPass2Choices,
        ),
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        // Four ricochet flags: (1st/2nd meeting) x (center/ends dancers).
        // Structured; kept for fidelity per the approved reduced model.
        'rico1': ParamSpec(ParamKind.flag, defaultValue: false),
        'rico2': ParamSpec(ParamKind.flag, defaultValue: false),
        'rico3': ParamSpec(ParamKind.flag, defaultValue: false),
        'rico4': ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{pass1} {move} {shoulder}',
      // ContraDB heyChange/heyGoodBeats: beats = heyLengthMeetTimes(length)*8,
      // where parseHeyLength maps half/lessThanHalf -> 1 meeting and
      // full/betweenHalfAndFull -> 2. So the four named lengths collapse into
      // two beat groups: {lessThanHalf, half} -> 8, {betweenHalfAndFull,
      // full} -> 16.
      goodBeats: [8, 16],
      paramBeats: ParamBeats(
        param: 'length',
        byValue: {
          'lessThanHalf': 8,
          'half': 8,
          'betweenHalfAndFull': 16,
          'full': 16,
        },
      ),
    ),
    const MoveDef(
      id: 'dolphin_hey',
      displayName: 'dolphin hey',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        // The lead (dolphin) dancer — a single-dancer identity.
        'whom': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'onesRole1',
          choices: _singleDancers,
        ),
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 16),
      },
      renderTemplate: '{who} {move} {shoulder}',
      goodBeats: [16],
    ),
    const MoveDef(
      id: 'form_long_waves',
      displayName: 'form long waves',
      params: {
        // ContraDB `formLongWavesWords` subject: the pair that faces IN (the
        // other pair faces out). TCB states the same fact ("…, women face in"),
        // so v21's decoding writes the facing-IN role here — the meaning is
        // unchanged from v20.
        //
        // The domain is narrowed to ContraDB's `chooser_pair` — exactly the six
        // tokens `ParamVocab.pairInverse` can invert. The display line names the
        // OTHER pair ("{who} facing in, {other} facing out"), so an
        // un-narrowed `who` could hold e.g. `neighbors` (all four dancers) and
        // the clause would then assert a facing for an empty set. The
        // renderer's `others` fallback stays as defence in depth (it is still
        // right for a wildcard `*` or out-of-domain imported data); this makes
        // the empty-set case unreachable from the model itself.
        'who': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'role1s',
          choices: _invertiblePairs,
        ),
        // v21 (#295): TCB states which pair you hold and by which hand —
        // `Balance long wave (NR, women face in)` = neighbors by the right.
        // ContraDB models neither, so both take the `unspecified` sentinel
        // (cf. `mad_robin.whom`, v20) and a figure that omits them renders
        // exactly as it did at v20.
        'whom': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: ParamVocab.unspecified,
          choices: _pairOrUnspecified,
        ),
        'hand': ParamSpec(
          ParamKind.handedness,
          defaultValue: ParamVocab.unspecified,
          choices: _handOrUnspecified,
        ),
        // v21 (#295): TCB writes "balance an existing long wave" as its own
        // line; the CallersBox importer maps such a line onto THIS move with
        // the flag set (either by folding a trailing balance into a preceding
        // form line, or by promoting the standalone balance line). Default
        // false, so no existing figure's output changes.
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        // A formation label: 0 beats is valid and typical.
        'beats': ParamSpec(ParamKind.beats, defaultValue: 0),
      },
      renderTemplate: '{who} {move}',
      searchKeywords: ['long waves'],
      // 0 for the bare formation label; 4 for a TCB balance-a-long-wave line,
      // which carries the balance's own beats (the balanced beat count comes
      // from the source line / the merge sum, never a fabricated rule — cf.
      // box_the_gnat, which likewise carries no `paramBeats`).
      goodBeats: [0, 4],
    ),
    const MoveDef(
      id: 'form_a_long_wave',
      displayName: 'form a long wave',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'role2s'),
        'in': ParamSpec(ParamKind.flag, defaultValue: true),
        'out': ParamSpec(ParamKind.flag, defaultValue: false),
        'balance': ParamSpec(ParamKind.flag, defaultValue: true),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move}',
      searchKeywords: ['long wave'],
      // ContraDB recomputes beats from in/out/balance (editor UX, out of
      // scope); the typical full case is 8. Not encoding the conditional rule.
      goodBeats: [8],
    ),
    // v13 split of the overloaded `form_an_ocean_wave` (issue #290). That move
    // conflated "form a short wave [and balance]" (the default short-wave case)
    // with "pass the ocean" (the pass-through-to-a-wave figure). Both new moves
    // inherit `form_an_ocean_wave`'s sourced param set MINUS `passThru`: the
    // pass-through is intrinsic to `pass_the_ocean` and intrinsically absent
    // from the short wave. Neither invents a beat count — they mirror the
    // legacy move's flat, param-dependent (unencoded) beats exactly.
    // `form_an_ocean_wave` itself was REMOVED at taxonomy v14 (CompendiumDatabase
    // schema v12 migrates stored figures onto these two moves by `passThru`).
    // v21 RENAMED this move from `form_a_short_wave` to `form_short_waves`
    // (issue #295): the figure is the whole set's short waves, and TCB always
    // writes "wave of four" / "short waves". Stored figures under the old id are
    // rewritten by CompendiumDatabase schema v19.
    const MoveDef(
      id: 'form_short_waves',
      displayName: 'form short waves',
      params: {
        // ContraDB set_direction_acrossish (across/rightDiagonal/leftDiagonal);
        // all in our direction vocabulary.
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        'center': ParamSpec(ParamKind.dancerSet, defaultValue: 'role2s'),
        'centerHand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'sides': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{move}',
      searchKeywords: [
        'short wave',
        'wavy line',
        'wave of four',
        'short waves',
        // The pre-v21 display label, kept searchable so the picker still finds
        // this move under the name it used to render with.
        'form a wave',
      ],
      // Beats mirror form_an_ocean_wave: param-dependent (balance), not encoded.
    ),
    const MoveDef(
      id: 'pass_the_ocean',
      displayName: 'pass the ocean',
      params: {
        // Same sourced param set as form_an_ocean_wave minus `passThru`, which
        // is intrinsic to this figure (dancers pass through to the wave).
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        'balance': ParamSpec(ParamKind.flag, defaultValue: false),
        'center': ParamSpec(ParamKind.dancerSet, defaultValue: 'role2s'),
        'centerHand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'sides': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{move}',
      searchKeywords: [
        'ocean wave',
        'pass to an ocean wave',
        'pass through to an ocean wave',
      ],
      // Beats mirror form_an_ocean_wave: param-dependent (balance), not encoded.
    ),
    const MoveDef(
      id: customMoveId,
      displayName: 'custom',
      params: {
        'text': ParamSpec(ParamKind.text, defaultValue: ''),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{text}',
    ),
  ],
  aliases: [
    const MoveAlias(
      id: 'see_saw',
      displayName: 'see saw',
      targetMove: 'do_si_do',
      pinnedParams: {'shoulder': 'left'},
      inversePairId: 'do_si_do',
    ),
    const MoveAlias(
      id: 'swat_the_flea',
      displayName: 'swat the flea',
      targetMove: 'box_the_gnat',
      pinnedParams: {'hand': 'left'},
      inversePairId: 'box_the_gnat',
    ),
    const MoveAlias(
      id: 'meltdown_swing',
      displayName: 'meltdown swing',
      targetMove: 'swing',
      pinnedParams: {'prefix': 'meltdown'},
    ),
  ],
);
