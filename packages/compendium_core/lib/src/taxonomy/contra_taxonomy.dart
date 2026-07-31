import '../model/enums.dart';
import '../model/figure.dart' show customMoveId;
import 'move_def.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Version of the seeded contra taxonomy. Bumped when moves/params change.
/// v2: roadmap 2.4a PR2 (dancer-interaction moves).
/// v3: roadmap 2.4a PR3 (choice-enum moves + `centers`/single-dancer vocab).
/// v4: roadmap 2.4a PR4 (places family + `ParamKind.places`).
/// v5: roadmap 2.4a PR5 (hey/wave family) — completes the 2.4a move set.
/// v6: full set of ContraDB named hey-length durations (lessThanHalf /
///     betweenHalfAndFull added; dancer%%N meeting encodings remain out of scope).
/// v7: swing renders its `prefix` modifier ("balance & swing" / "meltdown
///     swing"); `none` still renders to nothing.
/// v8: param-value-dependent beat counts — hey `length`, figure_8 `half`,
///     rory_o_more `balance`, and slice `return` carry structured `paramBeats`
///     (ContraDB-sourced) so untouched beats re-derive on a param change.
///     Moves whose ContraDB beats are a range/ratio rather than a discrete
///     per-value count (poussette, the places family, turn_alone) are left on
///     their flat default — see the notes at those moves. See MoveDef.paramBeats.
/// v9: extends `paramBeats` coverage — swing `prefix` (none 8, balance/meltdown
///     16), petronella `balance` (8/4), and long_lines `goBack` (8/4), all
///     ContraDB-sourced. The `meltdown_swing` alias now derives 16 beats.
///     Moves with continuous angle/ratio beat rules (allemande, do_si_do,
///     shoulder_round, circle/star family, box_the_gnat) remain deferred.
/// v10: cross-line merge support — `box_the_gnat` gains a `balance` flag
///     (default false; swat_the_flea inherits it via its box_the_gnat target)
///     and the down/up-the-hall `ender` gains a `bendTheLine` value. Both are
///     additive: no existing figure's derived output changes, and box_the_gnat
///     stays on the continuous-beat-rule deferral (no `paramBeats`). Distinct
///     from CompendiumDatabase.schemaVersion — no DB migration is implied.
/// v11: adds `box_circulate` (ContraDB-sourced; modeled on `box_the_gnat`) and
///     `star_through` (a balance+twirl figure modeled on `california_twirl` +
///     a balance flag), plus the `weave the line` → `zig_zag` recognizer alias.
///     Both new moves carry a neutral `balance` flag (default false) that the
///     CallersBox cross-line merge upgrades to true; like `box_the_gnat` their
///     balanced beat count comes only from that merge sum, so neither takes a
///     `paramBeats`. `box_circulate` carries no places param (ContraDB lists it
///     under moveCaresAboutPlaces for angle display only). Additive: no existing
///     figure's derived output changes; distinct from schemaVersion — no DB
///     migration is implied.
/// v12: `star_through` drops its `balance` flag to mirror `california_twirl`
///     (who + beats only) per product decision, and is removed from the
///     CallersBox cross-line balance-merge set (box_circulate stays). Removing
///     an unused default-false flag changes no existing figure's derived output
///     (a bare `star_through` already rendered without balance) and is distinct
///     from schemaVersion — no DB migration is implied.
/// v13: splits the overloaded `form_an_ocean_wave` (issue #290) into a default
///     short-wave `form_a_short_wave` (renders "form a wave") and a distinct
///     `pass_the_ocean` (renders "pass the ocean"). Both inherit the legacy
///     move's sourced params MINUS `passThru` (intrinsic to pass_the_ocean,
///     absent from the short wave) and mirror its unencoded, param-dependent
///     beats — no fabricated beat count. `form_an_ocean_wave` was RETAINED at
///     v13 for stored-data fidelity; v14 removes it (migrated away — see below).
/// v14: removes the now-superseded `form_an_ocean_wave` MoveDef (issue #290
///     cleanup). Stored figures that reference it are rewritten by the schema
///     migration (CompendiumDatabase schema v12) to `pass_the_ocean` (when
///     `passThru` is true — its default) or `form_a_short_wave` (when false),
///     carrying the remaining params. This is a DB migration (distinct from
///     this taxonomy version), the sanctioned canonical-changing exception.
/// v15: adds the TCB rotation-gate figure kind `rotation_gate` (issue #294,
///     Option B). A NEW move — distinct from the ContraDB `gate` (the two
///     vocabularies are disjoint) — carrying `direction`
///     (clockwise/counterclockwise/mirror) + a `turn` fraction over a VARIABLE
///     beat count. Its resulting facing is derived deterministically at render
///     time (gate_facing.dart), never stored. Purely additive taxonomy change:
///     no existing figure's derived output changes, and distinct from
///     CompendiumDatabase.schemaVersion — NO persisted-data migration is implied
///     (new figures serialize under the existing figure codec; stored figures
///     are untouched).
/// v16: adds an `endFacing` param to `swing` (issue #543) — the body facing a
///     swing ends in, a first-class promotion of what previously lived only in
///     a figure note. A `ParamKind.choice` over the four set-relative facing
///     tokens (`in`/`out`/`up`/`down`, reused from the ContraDB `gate` `face`
///     domain / `gateFacings`), defaulting to `in` (across — where most swings
///     end). Named `endFacing` (NOT `face`) to avoid overloading gate's `face`
///     (which means which way `who` orbits `whom`). Purely additive: the
///     default `in` renders exactly as today (the display renderer appends a
///     `facing …` clause ONLY when non-default; swing's canonical
///     `renderTemplate` is unchanged, so canonical/FTS/dedupe stay byte-stable),
///     it carries no beat cost (absent from `paramBeats`; `goodBeats` unchanged)
///     and does not feed the program-matrix swing column. Distinct from
///     CompendiumDatabase.schemaVersion — the param rides the existing
///     `figures_json` figure codec, so NO persisted-data migration is implied.
/// v17: adds a `meetTarget` param to `hey` (issue #576) — names WHICH pair you
///     run a partial hey until you meet, finally encoding the `dancer%%N`
///     meeting target that had been deferred as out of scope. A
///     `ParamKind.dancerSet` over ContraDB's `chooser_pairz` pair vocabulary
///     (`_heyMeetTargetChoices`), defaulting to `unspecified`. Derived directly
///     from libfigure: ContraDB folds length+target into one `hey_length`
///     (`pair%%1`/`pair%%2`); we already split the meeting *count* into `length`
///     (`lessThanHalf`=%%1, `betweenHalfAndFull`=%%2), so `meetTarget` supplies
///     only the WHO. Purely additive: the default `unspecified` renders exactly
///     as today (the display renderer only names the target when non-default;
///     `renderTemplate` is unchanged, so canonical/FTS/dedupe stay byte-stable),
///     it carries no beat cost (absent from `paramBeats`; `goodBeats` unchanged,
///     beats stay driven by `length`). Like `endFacing`, distinct from
///     CompendiumDatabase.schemaVersion — the param rides the existing
///     `figures_json` figure codec, so NO persisted-data migration is implied.
/// v18: adds `singleFile` flags to `promenade` and `circle` (issue #634,
///     deferred from #585) for ContraDB's "single file promenade along major
///     set" and "promenade single file around the circle N places" free-text
///     phrasings — both additive, default-`false` flags, not render tokens
///     (cf. `star.grip`), so canonical text is byte-stable at the default.
///     There is no separate `circle_left` move: the single existing `circle`
///     move's `turn` param already covers left/right, so the single-file
///     circle case reuses it with `turn` defaulted to `left` (the phrasing
///     never states a direction). Also extends `give_and_take.goodBeats` to
///     include `2` — real "take neighbors" renders (#570, #548) confirmed
///     take-only beats at both ends of the already-documented 2-4 range.
///     Purely additive: no existing figure's derived output changes, and
///     distinct from CompendiumDatabase.schemaVersion — the new flags ride the
///     existing `figures_json` figure codec, so NO persisted-data migration is
///     implied.
const int contraTaxonomyVersion = 18;

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
const _heyPass2Choices = [...ParamVocab.pairDancerSets, 'unspecified'];

// hey's `meetTarget` (issue #576): which pair you run a partial hey until you
// meet. ContraDB's `dancer%%N` meeting target is drawn from `chooser_pairz`
// (pairs only — never single dancers, and NOT `everyone`/`centers`, which are
// nonsensical as a hey meeting target), plus an `unspecified` sentinel default.
// chooser_pairz = pairDancerSets minus {everyone, centers}, so we spell it out
// rather than derive it, keeping the domain explicit and stable.
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
  'unspecified',
];

// The four single-dancer identities (ContraDB chooser_dancer: 1st/2nd couple x
// role), for moves that name an individual dancer.
const _singleDancers = ParamVocab.singleDancers;

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
        // (not `face`) so it is not confused with gate's orbit-direction `face`.
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
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {dir}',
      goodBeats: [8],
    ),
    const MoveDef(
      id: 'promenade',
      displayName: 'promenade',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'dir': ParamSpec(ParamKind.direction, defaultValue: 'across'),
        // Issue #634: a true "single file promenade" travels the whole major
        // set (no per-couple dancer relationship), vs. the ordinary partnered
        // promenade. Additive, not a render token (cf. star.grip): canonical
        // text stays byte-stable, and the flag is surfaced by structural
        // search / the verbose renderer in a future pass.
        'singleFile': ParamSpec(ParamKind.flag, defaultValue: false),
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
      params: {'beats': _beats4},
      renderTemplate: '{move}',
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
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 1.0),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 6),
      },
      renderTemplate: '{who} {move} {turn}',
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
    const MoveDef(
      id: 'star_promenade',
      displayName: 'star promenade',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'right'),
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 0.5),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move} {hand} {turn}',
      goodBeats: [4],
    ),
    const MoveDef(
      id: 'allemande_orbit',
      displayName: 'allemande orbit',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'left'),
        'inner': ParamSpec(ParamKind.rotation, defaultValue: 1.5),
        'outer': ParamSpec(ParamKind.rotation, defaultValue: 0.5),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {hand} {inner} {outer}',
      searchKeywords: ['orbit'],
      goodBeats: [8],
    ),
    // --- Roadmap 2.4a: dancer-interaction moves (PR2) ---
    // Additive ContraDB moves that fit the existing ParamKind set (no new
    // vocabulary). ContraDB "no default" choosers get sensible community
    // defaults, since ParamSpec.defaultValue is required.
    const MoveDef(
      id: 'gate',
      displayName: 'gate',
      params: {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'whom': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        // ContraDB chooser_gate_direction: which way `who` orbits `whom`.
        // Its up/down/in/out are relative to the set — distinct enough from
        // spatial `direction` that it is modeled as a dedicated choice.
        'face': ParamSpec(
          ParamKind.choice,
          defaultValue: 'up',
          choices: ['up', 'down', 'in', 'out'],
        ),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      renderTemplate: '{who} {move} {whom} {face}',
      goodBeats: [8],
    ),
    // --- Issue #294: TCB rotation-gate (Option B, product-owner accepted) ---
    // A DISTINCT figure kind from the ContraDB `gate` above — the two "gate"
    // vocabularies are disjoint (0/62 surveyed TCB gate lines map to `face`; see
    // figure_parser_test.dart and PR #271). ContraDB `gate` encodes a *facing*
    // (up/down/in/out) at a fixed 8 beats; TCB `gate` encodes a *rotation*
    // (clockwise / counterclockwise / mirror + a turn fraction) over a VARIABLE
    // beat count (attested 4 / 6 / 8). Modeling this as `face` would fabricate a
    // facing the source never stated, so it is its own move.
    //
    // The tuple is (who, direction, turn, beats, resulting-facing). The
    // resulting facing is NOT a stored param: it is DERIVED deterministically
    // from (start-orientation, direction, turn) by [gateEndFacing] at render
    // time, so it can never be free-typed, fabricated, or drift from the
    // geometry (see gate_facing.dart).
    const MoveDef(
      id: 'rotation_gate',
      displayName: 'gate',
      params: {
        // role/pair being gated (Partner, Neighbor, N2/N3 neighbor, …).
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
        // TCB rotation qualifier. A dedicated choice (NOT ParamKind.spinDirection,
        // which is cw/ccw only and cannot express the two-couple `mirror` gate).
        'direction': ParamSpec(
          ParamKind.choice,
          defaultValue: 'counterclockwise',
          choices: ['clockwise', 'counterclockwise', 'mirror'],
        ),
        // Turn fraction, reusing ParamKind.rotation (turns, quarter steps):
        // 1/2 -> 0.5, 3/4 -> 0.75, full 1 -> 1.0.
        'turn': ParamSpec(ParamKind.rotation, defaultValue: 0.5),
        // Variable as authored; the source line's beat count is layered on by
        // the parser. The default only applies to a beats-absent line.
        'beats': ParamSpec(ParamKind.beats, defaultValue: 8),
      },
      // Canonical (byte-stable) line. The display renderer rewords `mirror`
      // ahead of the move name and appends the derived facing clause
      // (see renderer.dart `_displayBaseRenderers`); canonical stays template-driven.
      renderTemplate: '{who} {move} {direction} {turn}',
      searchKeywords: ['rotation gate', 'mirror gate'],
      goodBeats: [4, 6, 8],
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
        // left/right). Additive, not a render token (cf. star.grip).
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
        // grip is a structured param, not a render token (cf. PR3 enders): it
        // is never emitted in canonical text, and is surfaced by the
        // verbose/dialect renderer + structural search. 'none' is the
        // unspecified value.
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
          defaultValue: 'unspecified',
          choices: _heyMeetTargetChoices,
        ),
        'shoulder': ParamSpec(ParamKind.shoulder, defaultValue: 'right'),
        // The ends pair, or 'unspecified' (ContraDB chooser_pairz_or_unspecified).
        'pass2': ParamSpec(
          ParamKind.dancerSet,
          defaultValue: 'unspecified',
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
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'role1s'),
        // A formation label: 0 beats is valid and typical.
        'beats': ParamSpec(ParamKind.beats, defaultValue: 0),
      },
      renderTemplate: '{who} {move}',
      searchKeywords: ['long waves'],
      goodBeats: [0],
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
    // from `form_a_short_wave`. Neither invents a beat count — they mirror the
    // legacy move's flat, param-dependent (unencoded) beats exactly.
    // `form_an_ocean_wave` itself was REMOVED at taxonomy v14 (CompendiumDatabase
    // schema v12 migrates stored figures onto these two moves by `passThru`).
    const MoveDef(
      id: 'form_a_short_wave',
      displayName: 'form a wave',
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
    ),
    const MoveAlias(
      id: 'swat_the_flea',
      displayName: 'swat the flea',
      targetMove: 'box_the_gnat',
      pinnedParams: {'hand': 'left'},
    ),
    const MoveAlias(
      id: 'meltdown_swing',
      displayName: 'meltdown swing',
      targetMove: 'swing',
      pinnedParams: {'prefix': 'meltdown'},
    ),
  ],
);
