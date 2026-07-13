import '../model/enums.dart';
import '../model/figure.dart' show customMoveId;
import 'move_def.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Version of the seeded contra taxonomy. Bumped when moves/params change.
/// v2: roadmap 2.4a PR2 (dancer-interaction moves).
/// v3: roadmap 2.4a PR3 (choice-enum moves + `centers`/single-dancer vocab).
const int contraTaxonomyVersion = 3;

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
];

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
      },
      progressionCapable: true,
      renderTemplate: '{who} {move}',
      goodBeats: [8, 16],
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
      progressionCapable: true,
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
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'ones'),
        'hand': ParamSpec(ParamKind.handedness, defaultValue: 'left'),
        'whom': ParamSpec(ParamKind.dancerSet, defaultValue: 'neighbors'),
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
      // ContraDB range is give -> 4-8, take-only -> 2-4; the two canonical
      // counts are 4 (take only) and 8 (give & take).
      goodBeats: [4, 8],
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
    // (ParamKind.choice). Optional/secondary modifiers (enders that default to
    // "none", embedded custom text, single-dancer `lead`, the who-coupled
    // `moving`) are structured params but NOT render-template tokens: the terse
    // canonical line carries the identifying phrase, while these are surfaced by
    // the verbose/dialect renderer (design-doc TODO) and structural search.
    // This mirrors swing.prefix (a "none"-valued choice that is not templated)
    // and keeps default renders free of literal "none" tokens.
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
      renderTemplate: '{who} {move} {facing} {ender}',
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
      renderTemplate: '{who} {move} {facing} {ender}',
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
      // ContraDB: return=="none" -> 4 beats, else 8.
      goodBeats: [4, 8],
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
      // ContraDB rule is 0 <= beats <= 4 (a range the list-based goodBeats
      // can't express); left unset so any in-domain count is accepted.
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
      // half -> 8 beats, full -> 16.
      goodBeats: [8, 16],
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
      // half -> 6-8 beats, full -> 12-16.
      goodBeats: [6, 8],
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
      // ContraDB: balance -> 8 beats, no balance -> 4.
      goodBeats: [4, 8],
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
