import '../model/enums.dart';
import 'move_def.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Version of the traditional square taxonomy (ADR-007). Like
/// [contraTaxonomyVersion] and [ecdTaxonomyVersion], a documentary marker that
/// nothing reads at runtime, logged under "Square taxonomy versions" (inside
/// "Taxonomy version history") in `docs/design/figure-taxonomy.md`. Version 1
/// is ADR-007 §7.1's traditional core.
const int squareTaxonomyVersion = 1;

/// The prefix of every square move ID (ADR-007 §5.1). The IDs in ADR-007's
/// tables are written without it.
const String squareMovePrefix = _p;

// Spelled as a literal, not as [squareMovePrefix], so that
// `tools/ci/report_figure_namesakes.py` can read the IDs below.
const String _p = 'sq_';

const _u = ParamVocab.unspecified;

/// The selectors a square `who` or `whom` may name (ADR-007 §6.2), then
/// [ParamVocab.unspecified].
///
/// Couples are contra's `ones` to `fours`, so a square's first couple is the
/// same token a contra dance's is. Gendered role terms are never a selector:
/// storage is role-neutral (`role1s`/`role2s`), and a selector that names a
/// role ([squareRoleSelectorWords]) shows the dialect's role term.
const List<String> squareSelectors = [
  'everyone',
  // Identity in the square: the original heads and sides, and whoever is at
  // the head or side positions now (§5.5).
  'heads',
  'sides',
  'headPosition',
  'sidePosition',
  'ones',
  'twos',
  'threes',
  'fours',
  'role1s',
  'role2s',
  'headRole1s',
  'headRole2s',
  'sideRole1s',
  'sideRole2s',
  // Relationships.
  'partners',
  'corners',
  'opposites',
  'rightHandRole2',
  'leftHandRole2',
  'originalPartners',
  'originalCorners',
  'originalOpposites',
  // Position.
  'facing',
  'centers',
  'ends',
  'centerFour',
  'outsideFour',
  'leaders',
  'trailers',
  _u,
];

/// The words of each square token that names a role, with `{role1}`,
/// `{role1s}`, `{role2}` or `{role2s}` where the dialect's role term goes.
/// With larks and robins they read "head larks", "right-hand robin" and
/// "lark's place".
///
/// A role is never spelled out in stored data, so these tokens cannot
/// humanize the way other tokens do: "head role1s" would show the canonical
/// role token. The canonical render keeps that token, as it does for
/// `role1s` itself.
const Map<String, String> squareRoleSelectorWords = {
  'headRole1s': 'head {role1s}',
  'headRole2s': 'head {role2s}',
  'sideRole1s': 'side {role1s}',
  'sideRole2s': 'side {role2s}',
  'rightHandRole2': 'right-hand {role2}',
  'leftHandRole2': 'left-hand {role2}',
  'role1Place': "{role1}'s place",
  'role2Place': "{role2}'s place",
};

/// [token]'s words from [squareRoleSelectorWords], with each role filled in
/// by [roleTerm] (given `role1`, `role1s`, `role2` or `role2s`), or null when
/// [token] names no role.
String? squareRoleTokenWords(String token, String Function(String) roleTerm) {
  final words = squareRoleSelectorWords[token];
  if (words == null) return null;
  return words.replaceAllMapped(
    RegExp(r'\{(role[12]s?)\}'),
    (match) => roleTerm(match[1]!),
  );
}

/// The CALLERLAB program a square call is also listed in, shown in the
/// glossary as a label (ADR-007 §5.2). Nothing else is derived from it.
enum CallerlabProgram { mainstream, plus, advanced }

/// The CALLERLAB program of each square move or alias that CALLERLAB lists
/// (ADR-007 §7.2's closing note), keyed by ID. A traditional call CALLERLAB
/// does not list (a hey, a shoulder round) has no entry. The label is the 2026 program;
/// it is not versioned by edition.
const Map<String, CallerlabProgram> squareCallPrograms = {
  '${_p}swing': CallerlabProgram.mainstream,
  '${_p}promenade': CallerlabProgram.mainstream,
  '${_p}allemande_left': CallerlabProgram.mainstream,
  '${_p}allemande_right': CallerlabProgram.mainstream,
  '${_p}circle': CallerlabProgram.mainstream,
  '${_p}forward_and_back': CallerlabProgram.mainstream,
  '${_p}pass_through': CallerlabProgram.mainstream,
  '${_p}chain': CallerlabProgram.mainstream,
  '${_p}star': CallerlabProgram.mainstream,
  '${_p}balance': CallerlabProgram.mainstream,
  '${_p}do_si_do': CallerlabProgram.mainstream,
  '${_p}see_saw': CallerlabProgram.plus,
  '${_p}separate': CallerlabProgram.mainstream,
  '${_p}right_left_through': CallerlabProgram.mainstream,
  '${_p}lead': CallerlabProgram.mainstream,
  '${_p}u_turn_back': CallerlabProgram.mainstream,
  '${_p}backtrack': CallerlabProgram.mainstream,
};

// `who` and `whom`. An unstated one is `unspecified` (§5.7); the editor
// starts a new line on everyone.
const _who = ParamSpec(
  ParamKind.dancerSet,
  defaultValue: _u,
  entryDefault: 'everyone',
  choices: squareSelectors,
);
const _whom = ParamSpec(
  ParamKind.dancerSet,
  defaultValue: _u,
  choices: squareSelectors,
);
ParamSpec _whomSeeded(String seed) => ParamSpec(
  ParamKind.dancerSet,
  defaultValue: _u,
  entryDefault: seed,
  choices: squareSelectors,
);
const _hand = ParamSpec(
  ParamKind.handedness,
  defaultValue: _u,
  choices: ['right', 'left', _u],
);
const _shoulderRight = ParamSpec(
  ParamKind.shoulder,
  defaultValue: 'right',
  choices: ['right', 'left'],
);
const _shoulder = ParamSpec(
  ParamKind.shoulder,
  defaultValue: _u,
  choices: ['right', 'left', _u],
);
// How far a turn goes, in full turns: contra's `travel` (§6.1).
const _travel = ParamSpec(ParamKind.rotation, defaultValue: _u, choices: [_u]);
// How far around a circle, star or promenade goes. No `other`: an amount
// between the named ones is the nearest, with the source's words in the
// line's note (§6.1).
const _fraction = ParamSpec(
  ParamKind.fraction,
  defaultValue: _u,
  choices: ['quarter', 'half', 'threeQuarter', 'full', _u],
);
// Dancers in a circle or star; a circle of three is one couple and another
// dancer (§6.1).
const _size = ParamSpec(
  ParamKind.choice,
  defaultValue: _u,
  choices: ['two', 'three', 'four', 'six', 'eight', _u],
);
const _leftRight = ParamSpec(
  ParamKind.choice,
  defaultValue: _u,
  choices: ['left', 'right', _u],
);
ParamSpec _beats(int beats) => ParamSpec(ParamKind.beats, defaultValue: beats);

/// The traditional square taxonomy (ADR-007): §7.1's traditional core.
///
/// Its own definitions throughout, never contra's (§5.1), though parameter
/// names and value tokens follow contra's where the concept is the same
/// (`who`, `hand`, `shoulder`, `travel`, `prefix`, `beats`). Display
/// templates are contra-style, since square wording is close to contra's
/// (ADR-007 §12). Defaults follow the held squares (§7.1).
final Taxonomy squareTaxonomy = Taxonomy(
  version: squareTaxonomyVersion,
  form: DanceForm.square,
  moves: [
    MoveDef(
      id: '${_p}swing',
      displayName: 'swing',
      params: {
        'who': _who,
        'whom': _whomSeeded('partners'),
        // A balance before the swing, as contra's swing names it (§5.1).
        'prefix': const ParamSpec(
          ParamKind.choice,
          defaultValue: 'none',
          choices: ['none', 'balance'],
        ),
        'beats': _beats(8),
      },
      renderTemplate: '{who} {prefix} {move} {whom}',
      goodBeats: const [8, 12, 14, 16],
      paramBeats: const ParamBeats(
        param: 'prefix',
        byValue: {'none': 8, 'balance': 16},
      ),
    ),
    MoveDef(
      id: '${_p}promenade',
      displayName: 'promenade',
      params: {
        'who': _who,
        // A plain promenade states no variant.
        'variant': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['singleFile', 'outside', 'wrongWay', 'star', _u],
        ),
        'fraction': _fraction,
        'destination': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['home', 'role1Place', 'role2Place', _u],
        ),
        'beats': _beats(16),
      },
      renderTemplate: '{who} {variant} {move} {fraction} {destination}',
      searchKeywords: const ['single file'],
      goodBeats: const [4, 8, 12, 16],
      // Sources name a destination more often than a fraction (§7.1); one to
      // home is the full 16.
      paramBeats: const ParamBeats(
        param: 'fraction',
        byValue: {'quarter': 4, 'half': 8, 'threeQuarter': 12, 'full': 16},
      ),
    ),
    MoveDef(
      id: '${_p}hand_turn',
      displayName: 'hand turn',
      params: {
        'who': _who,
        // A bare "allemande left" is the corner (Q8): suggested, not stored.
        'whom': _whomSeeded('corners'),
        'hand': _hand,
        'travel': _travel,
        'beats': _beats(8),
      },
      renderTemplate: '{who} {hand} {move} {whom} {travel}',
      searchKeywords: const ['turn by the hand'],
      goodBeats: const [4, 6, 8],
    ),
    MoveDef(
      id: '${_p}circle',
      displayName: 'circle',
      params: {
        'who': _who,
        'size': _size,
        'direction': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          entryDefault: 'left',
          choices: ['left', 'right', _u],
        ),
        'fraction': _fraction,
        'beats': _beats(8),
      },
      renderTemplate: '{who} {move} {size} {direction} {fraction}',
      searchKeywords: const ['ring'],
      goodBeats: const [4, 6, 8, 12, 16],
      // Parkes's ¾ circle of four is 8, where CALLERLAB has 6 (§7.1).
      paramBeats: const ParamBeats(
        param: 'fraction',
        byValue: {},
        rules: [
          ParamBeatsRule({'size': 'eight', 'fraction': 'full'}, 16),
          ParamBeatsRule({'size': 'eight', 'fraction': 'threeQuarter'}, 12),
          ParamBeatsRule({'size': 'eight', 'fraction': 'half'}, 8),
          ParamBeatsRule({'size': 'eight', 'fraction': 'quarter'}, 4),
          ParamBeatsRule({'size': 'four', 'fraction': 'half'}, 4),
          ParamBeatsRule({'size': 'four', 'fraction': 'quarter'}, 2),
        ],
      ),
    ),
    MoveDef(
      id: '${_p}forward_and_back',
      displayName: 'forward and back',
      params: {'who': _who, 'beats': _beats(8)},
      renderTemplate: '{who} {move}',
      // "Always a full eight beats in New England" (Parkes).
      goodBeats: const [8],
    ),
    MoveDef(
      id: '${_p}pass_through',
      displayName: 'pass through',
      params: {'who': _who, 'beats': _beats(4)},
      renderTemplate: '{who} {move}',
      searchKeywords: const ['pass thru'],
      goodBeats: const [2, 4],
    ),
    MoveDef(
      id: '${_p}chain',
      displayName: 'chain',
      params: {
        'who': const ParamSpec(
          ParamKind.dancerSet,
          defaultValue: _u,
          entryDefault: 'role2s',
          choices: squareSelectors,
        ),
        // "Four [Robins] chain", as against two.
        'four': const ParamSpec(ParamKind.flag, defaultValue: false),
        'where': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['across', 'alongTheLine', _u],
        ),
        // Half is across; three quarters is round the set, as four chain;
        // full is over and back, one line of 16 (§7.1).
        'fraction': const ParamSpec(
          ParamKind.fraction,
          defaultValue: _u,
          choices: ['half', 'threeQuarter', 'full', _u],
        ),
        // Fuerst's "power turn" is a courtesy turn with an extra half. A
        // plain courtesy turn is what every chain ends with, so it is left
        // unstated rather than shown as a word.
        'courtesy': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['powerTurn', _u],
        ),
        'beats': _beats(8),
      },
      renderTemplate: '{four} {who} {move} {where} {fraction} {courtesy}',
      goodBeats: const [8, 10, 16],
      // Three quarters is CALLERLAB's 10; no traditional count was seen
      // (§7.1).
      paramBeats: const ParamBeats(
        param: 'fraction',
        byValue: {'half': 8, 'threeQuarter': 10, 'full': 16},
      ),
    ),
    MoveDef(
      id: '${_p}star',
      displayName: 'star',
      params: {
        'who': _who,
        'size': _size,
        'hand': _hand,
        'fraction': _fraction,
        'beats': _beats(8),
      },
      renderTemplate: '{who} {hand} {move} {size} {fraction}',
      searchKeywords: const ['hands across'],
      goodBeats: const [4, 6, 8],
      paramBeats: const ParamBeats(
        param: 'fraction',
        byValue: {'quarter': 2, 'half': 4, 'threeQuarter': 6, 'full': 8},
      ),
    ),
    MoveDef(
      id: '${_p}balance',
      displayName: 'balance',
      params: {
        'who': _who,
        'whom': _whom,
        'where': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['inPlace', 'inAWave', 'inTheRing', _u],
        ),
        'beats': _beats(4),
      },
      renderTemplate: '{who} {move} {whom} {where}',
      goodBeats: const [4],
    ),
    MoveDef(
      id: '${_p}do_si_do',
      displayName: 'dosido',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulderRight,
        'travel': _travel,
        'beats': _beats(8),
      },
      renderTemplate: '{who} {move} {whom} {travel}',
      searchKeywords: const ['do si do', 'do-si-do', 'dosado', 'docey doe'],
      goodBeats: const [6, 8],
    ),
    MoveDef(
      id: '${_p}separate',
      displayName: 'separate',
      params: {
        'who': _who,
        // Whom the dancers go around (§6.1). The tokens carry "around", as
        // `into`'s carry "into", so the line reads "around one".
        'around': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['aroundOne', 'aroundTwo', _u],
        ),
        'into': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['intoALine', 'intoTheMiddle', 'home', _u],
        ),
        'beats': _beats(8),
      },
      renderTemplate: '{who} {move} {around} {into}',
      goodBeats: const [4, 8],
    ),
    MoveDef(
      id: '${_p}right_left_through',
      displayName: 'right left through',
      params: {
        'who': _who,
        'whom': _whom,
        // A full courtesy turn at the end: 12 beats (§7.1).
        'fullTurn': const ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': _beats(8),
      },
      renderTemplate: '{who} {move} {whom}',
      searchKeywords: const ['right and left thru'],
      goodBeats: const [8, 12],
      paramBeats: const ParamBeats(
        param: 'fullTurn',
        byValue: {true: 12, false: 8},
      ),
    ),
    MoveDef(
      id: '${_p}lead',
      displayName: 'lead',
      params: {'who': _who, 'direction': _leftRight, 'beats': _beats(4)},
      renderTemplate: '{who} {move} {direction}',
      goodBeats: const [2, 4],
    ),
    MoveDef(
      id: '${_p}face',
      displayName: 'face',
      params: {
        'who': _who,
        'direction': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['in', 'out', 'left', 'right', 'theHeads', 'theSides', _u],
        ),
        'beats': _beats(0),
      },
      renderTemplate: '{who} {move} {direction}',
      goodBeats: const [0, 2],
    ),
    MoveDef(
      id: '${_p}pass_by',
      displayName: 'pass by',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulder,
        'beats': _beats(2),
      },
      renderTemplate: '{who} {move} {whom} {shoulder}',
      goodBeats: const [2],
    ),
    MoveDef(
      id: '${_p}pull_by',
      displayName: 'pull by',
      params: {'who': _who, 'whom': _whom, 'hand': _hand, 'beats': _beats(2)},
      renderTemplate: '{who} {move} {whom} {hand}',
      goodBeats: const [2, 4],
    ),
    MoveDef(
      id: '${_p}hey',
      displayName: 'hey',
      params: {
        'who': _who,
        'where': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['alongTheLine', 'inTheCenter', _u],
        ),
        // The shoulder of the first pass.
        'shoulder': _shoulder,
        'beats': _beats(16),
      },
      renderTemplate: '{who} {move} {where} {shoulder}',
      goodBeats: const [8, 16],
    ),
    MoveDef(
      id: '${_p}turn_alone',
      displayName: 'turn alone',
      params: {'who': _who, 'beats': _beats(4)},
      renderTemplate: '{who} {move}',
      searchKeywords: const ['about face'],
      goodBeats: const [2, 4],
    ),
    MoveDef(
      id: '${_p}shoulder_round',
      displayName: 'shoulder round',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulderRight,
        'travel': _travel,
        // Phrase-filling, like the other turning calls; no held square states
        // a count (Q11).
        'beats': _beats(8),
      },
      renderTemplate: '{who} {move} {whom} {travel}',
      // "Gypsy" is a discouraged term: it reads as a shoulder round, as
      // it does for contra (contraTaxonomy's shoulder_round).
      searchKeywords: const ['gypsy', 'gyre'],
      goodBeats: const [6, 8],
    ),
  ],
  aliases: const [
    MoveAlias(
      id: '${_p}allemande_left',
      displayName: 'allemande left',
      targetMove: '${_p}hand_turn',
      pinnedParams: {'hand': 'left'},
    ),
    MoveAlias(
      id: '${_p}allemande_right',
      displayName: 'allemande right',
      targetMove: '${_p}hand_turn',
      pinnedParams: {'hand': 'right'},
    ),
    MoveAlias(
      id: '${_p}see_saw',
      displayName: 'seesaw',
      targetMove: '${_p}do_si_do',
      pinnedParams: {'shoulder': 'left'},
      inversePairId: '${_p}do_si_do',
      searchKeywords: ['see saw', 'see-saw'],
    ),
    MoveAlias(
      id: '${_p}u_turn_back',
      displayName: 'U-turn back',
      targetMove: '${_p}turn_alone',
      searchKeywords: ['u turn back'],
    ),
    MoveAlias(
      id: '${_p}backtrack',
      displayName: 'backtrack',
      targetMove: '${_p}turn_alone',
    ),
  ],
);
