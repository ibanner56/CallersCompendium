import '../model/enums.dart';
import 'move_def.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Version of the English Country Dance taxonomy (ADR-006). Like
/// [contraTaxonomyVersion], a documentary marker that nothing reads at
/// runtime, logged under "Taxonomy version history" in
/// `docs/design/figure-taxonomy.md`. Version 1 is the registry ADR-006 §7
/// accepted.
const int ecdTaxonomyVersion = 1;

/// The prefix of every ECD move ID (ADR-006 §5.1). The IDs in ADR-006's
/// tables are written without it.
const String _p = 'ecd_';

/// The selectors an ECD `who` or `whom` may name (ADR-006 §6.2), in that
/// list's order, then the single-dancer tokens, then
/// [ParamVocab.unspecified].
///
/// Gendered role terms are never a selector: storage is role-neutral
/// (`role1s`/`role2s`), and the dialect names the roles (§4, §9.1 point 7).
const List<String> ecdSelectors = [
  'everyone',
  'role1s',
  'role2s',
  'ones',
  'twos',
  'threes',
  'fours',
  'fives',
  'partners',
  'neighbors',
  'sameRoles',
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
  'firstCorners',
  'secondCorners',
  'corners',
  'longCorners',
  'firstDiagonals',
  'secondDiagonals',
  'diagonal',
  'actives',
  'couples',
  'sideCouples',
  'centers',
  'top',
  'bottom',
  'ends',
  'middles',
  'leftFile',
  'rightFile',
  ...ParamVocab.singleDancers,
  ParamVocab.unspecified,
];

/// The stated endpoints an ECD movement can carry in `destination` (ADR-006
/// §6.4), in camelCase (§6.1), then [ParamVocab.unspecified]. A figure that
/// states none stores none, which reads the same as the sentinel.
const List<String> ecdDestinations = [
  ..._statedDestinations,
  ParamVocab.unspecified,
];

const List<String> _statedDestinations = [
  'place',
  'firstPlace',
  'secondPlace',
  'thirdPlace',
  'fourthPlace',
  'fifthPlace',
  'sixthPlace',
  'originalPlaces',
  'progressedPlace',
  'partnersPlace',
  'neighborsPlace',
  'diagonalsPlace',
  'allImproper',
  'allProper',
];

const _u = ParamVocab.unspecified;

// `who` is a list (§5.2). An unstated one is `["unspecified"]`; the editor
// suggests `["everyone"]` (§9.1 point 5).
const _who = ParamSpec(
  ParamKind.dancerList,
  defaultValue: [_u],
  entryDefault: ['everyone'],
  choices: ecdSelectors,
);
const _whom = ParamSpec(
  ParamKind.dancerSet,
  defaultValue: _u,
  choices: ecdSelectors,
);
const _hand = ParamSpec(
  ParamKind.handedness,
  defaultValue: _u,
  choices: ['right', 'left', _u],
);
const _shoulder = ParamSpec(
  ParamKind.shoulder,
  defaultValue: _u,
  choices: ['right', 'left', _u],
);
const _spin = ParamSpec(
  ParamKind.spinDirection,
  defaultValue: _u,
  choices: ['clockwise', 'counterclockwise', _u],
);
const _side = ParamSpec(
  ParamKind.choice,
  defaultValue: _u,
  choices: ['left', 'right', _u],
);
const _travel = ParamSpec(ParamKind.rotation, defaultValue: _u, choices: [_u]);
const _places = ParamSpec(ParamKind.places, defaultValue: _u, choices: [_u]);
const _changes = ParamSpec(ParamKind.places, defaultValue: _u, choices: [_u]);
const _fraction = ParamSpec(
  ParamKind.fraction,
  defaultValue: _u,
  choices: ['quarter', 'half', 'threeQuarter', 'full', _u],
);
const _endFacing = ParamSpec(
  ParamKind.choice,
  defaultValue: _u,
  choices: ['up', 'down', 'in', 'out', _u],
);
const _destination = ParamSpec(
  ParamKind.choice,
  defaultValue: _u,
  choices: ecdDestinations,
);
// A cast also ends at the top or the bottom of the set, as contra's `cast`
// does ("cast down to bottom"): the maintainer's decision of 2026-11-19.
const _castDestination = ParamSpec(
  ParamKind.choice,
  defaultValue: _u,
  choices: [..._statedDestinations, 'top', 'bottom', _u],
);
const _no = ParamSpec(ParamKind.flag, defaultValue: false);

ParamSpec _where(List<String> values) =>
    ParamSpec(ParamKind.choice, defaultValue: _u, choices: [...values, _u]);

ParamSpec _beats(int beats) => ParamSpec(ParamKind.beats, defaultValue: beats);

const _heyPaths = ['along', 'across', 'diagonally'];

/// The English Country Dance taxonomy: ADR-006 §7's movements, each stored
/// under an `ecd_` ID (§5.1), with its parameters and draft display.
///
/// Every parameter a source can leave out defaults to
/// [ParamVocab.unspecified] (R2, §5.3), so an imported figure never appears
/// to state a value its source did not. The exceptions are the maintainer's:
/// `forward_and_back.distance` stores a double when none is stated (§7.5,
/// §9.1 point 3), and the flags, which state "no" when absent. The editor's
/// suggestions (`everyone`, a set to the right, a right-shoulder turn
/// single, forward for a forward and back) are [ParamSpec.entryDefault]s,
/// which nothing that reads a stored figure consults.
///
/// Templates use the ECD display notation (§6.3), which the renderer expands
/// (`ecd_display.dart`): `{param}` is a value, `[...]` is dropped when a value
/// inside it is empty, and `{?flag}` keeps its group only while the flag is
/// set. A stated `destination` renders as its own phrase ("back to place",
/// "to second place"). Dialects can reword every movement (R4).
///
/// Beat counts are a starting point: ECD timing is entered in bars and
/// stored in beats through the dance's phrase structure (§5.5), so no
/// movement lists typical counts.
///
/// Containers (`sequence`, `meanwhile`, `modifier`) and the free-text
/// `custom` figure are shared by every form and stay unprefixed (§5.1); an
/// ECD dance reaches them through contra's taxonomy underneath
/// (`shippedTaxonomies.forForm`).
final Taxonomy ecdTaxonomy = Taxonomy(
  version: ecdTaxonomyVersion,
  form: DanceForm.ecd,
  moves: [
    // §7.1 Setting, honouring and small gestures.
    MoveDef(
      id: '${_p}set',
      displayName: 'set',
      params: {
        'who': _who,
        'whom': _whom,
        'where': _where(['forward', 'along', 'across']),
        'direction': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          entryDefault: 'right',
          choices: ['right', 'left', _u],
        ),
        'beats': _beats(4),
      },
      renderTemplate: '{who} {move} [{direction}] [{where}] [to {whom}]',
      searchKeywords: const ['set forward', 'setting'],
    ),
    MoveDef(
      id: '${_p}honor',
      displayName: 'honor',
      params: {'who': _who, 'whom': _whom, 'beats': _beats(4)},
      renderTemplate: '{who} step and {move} [{whom}]',
      searchKeywords: const ['honour', 'bow', 'step and honor'],
    ),
    MoveDef(
      id: '${_p}clap',
      displayName: 'clap',
      params: {'beats': _beats(2)},
      renderTemplate: '{move}',
    ),
    MoveDef(
      id: '${_p}set_and_link',
      displayName: 'set and link',
      params: {'beats': _beats(4)},
      renderTemplate: '{move}',
      searchKeywords: const ['link'],
    ),
    // §7.2 Turns.
    MoveDef(
      id: '${_p}turn_single',
      displayName: 'turn single',
      params: {
        'who': _who,
        // The side turned to, or `cloverleaf`: each couple turns away
        // from the other, as the four leaves of a cloverleaf (the
        // maintainer's answer, ADR-006 §9.3).
        'shoulder': const ParamSpec(
          ParamKind.shoulder,
          defaultValue: _u,
          entryDefault: 'right',
          choices: ['right', 'left', 'cloverleaf', _u],
        ),
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate: '{who} {move} [{shoulder}] [{destination}]',
      searchKeywords: const ['cloverleaf turn single'],
    ),
    MoveDef(
      id: '${_p}turn_alone',
      displayName: 'turn alone',
      params: {
        'who': _who,
        'custom': const ParamSpec(ParamKind.text, defaultValue: ''),
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate: '{who} {move} [{custom}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}hand_turn',
      displayName: 'hand turn',
      params: {
        'who': _who,
        'hand': _hand,
        'travel': _travel,
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{hand}-]{move} [{travel}] [and face {endFacing}] '
          '[, {destination}]',
      searchKeywords: const [
        'right-hand turn',
        'left-hand turn',
        'turn by the right',
        'turn by the left',
        'RH turn',
        'LH turn',
      ],
    ),
    MoveDef(
      id: '${_p}two_hand_turn',
      displayName: 'two-hand turn',
      params: {
        'who': _who,
        'travel': _travel,
        'direction': _spin,
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} {move} [{direction}] [{travel}] [and face {endFacing}] '
          '[, {destination}]',
      searchKeywords: const ['two hand turn', 'turn two hands'],
    ),
    MoveDef(
      id: '${_p}arm_turn',
      displayName: 'arm turn',
      params: {
        'who': _who,
        'hand': _hand,
        'travel': _travel,
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} arm [{hand}] [{travel}] [and face {endFacing}] '
          '[, {destination}]',
      searchKeywords: const ['arm right', 'arm left'],
    ),
    MoveDef(
      id: '${_p}shoulder_round',
      displayName: 'shoulder round',
      params: {
        'who': _who,
        'shoulder': _shoulder,
        'travel': _travel,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{shoulder} shoulder] {move} [{travel}] [, {destination}]',
      // "gypsy" is a discouraged term (§7.2): recognised in typed and
      // imported text, flagged by the dialect's discouraged terms
      // (`defaultDiscouragedTerms`), and never offered as a name.
      searchKeywords: const ['gyre', 'gypsy'],
    ),
    MoveDef(
      id: '${_p}swing',
      displayName: 'swing',
      params: {
        'who': _who,
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate: '{who} {move} [and face {endFacing}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}box_the_gnat',
      displayName: 'box the gnat',
      params: {
        'who': _who,
        // The hand that names the figure: box the gnat is by the right, swat
        // the flea by the left, so this is not a value a source leaves out.
        'hand': const ParamSpec(
          ParamKind.handedness,
          defaultValue: 'right',
          choices: ['right', 'left'],
        ),
        'balance': _no,
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate: '{who} [{?balance}balance and] {move} [, {destination}]',
    ),
    MoveDef(
      id: '${_p}gate',
      displayName: 'gate',
      params: {
        'who': _who,
        'whom': _whom,
        'pair': _whom,
        'direction': _spin,
        'travel': _travel,
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} {move} [{whom}] [with {pair}] [{direction}] [{travel}] '
          '[to face {endFacing}] [, {destination}]',
      // A hand cast is a gate (the maintainer's decision of 2026-11-19).
      searchKeywords: const ['hand cast'],
    ),
    MoveDef(
      id: '${_p}orbit',
      displayName: 'orbit',
      params: {
        'who': _who,
        'whom': _whom,
        'direction': _spin,
        'travel': _travel,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} {move} [{direction}] [{travel}] [around {whom}] '
          '[, {destination}]',
    ),
    MoveDef(
      id: '${_p}mad_robin',
      displayName: 'mad robin',
      params: {
        'who': _who,
        'whom': _whom,
        'travel': _travel,
        'direction': _spin,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} {move} [around {whom}] [{direction}] [{travel}] '
          '[, {destination}]',
    ),
    // §7.3 Rings, stars and balances.
    MoveDef(
      id: '${_p}balance',
      displayName: 'balance',
      params: {
        'who': _who,
        'where': _where(['forward', 'back', 'along', 'across', 'diagonally']),
        'hand': _hand,
        'beats': _beats(4),
      },
      renderTemplate: '{who} [{hand} hand] {move} [{where}]',
    ),
    MoveDef(
      id: '${_p}balance_ring',
      displayName: 'balance the ring',
      params: {'beats': _beats(4)},
      renderTemplate: '{move}',
    ),
    MoveDef(
      id: '${_p}petronella',
      displayName: 'petronella',
      params: {
        'who': _who,
        'places': _places,
        'direction': _side,
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [{places}] [to the {direction}] [, {destination}]',
      searchKeywords: const ['petronella turn'],
    ),
    MoveDef(
      id: '${_p}circle',
      displayName: 'circle',
      params: {
        'who': _who,
        // Left/right for a ring, clockwise/counter-clockwise single file
        // (§7.3).
        'direction': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['left', 'right', 'clockwise', 'counterclockwise', _u],
        ),
        'places': _places,
        'singleFile': _no,
        'step': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['slipping', 'skipping', _u],
        ),
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[{who},] [{?singleFile}single file] {move} [{direction}] '
          '[{places}] [, {destination}]',
      // "Chase" is a single-file circle (ADR-006 §9.3).
      searchKeywords: const ['ring', 'slip', 'circle half', 'chase'],
    ),
    MoveDef(
      id: '${_p}star',
      displayName: 'star',
      params: {
        'who': _who,
        'hand': _hand,
        'places': _places,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[{who},] [{hand}] hands across [{places}] [, {destination}]',
      searchKeywords: const ['hands across', 'right hands across'],
    ),
    MoveDef(
      id: '${_p}form_short_wave',
      displayName: 'form short waves',
      params: {
        'axis': _where(['along', 'across']),
        'balance': _no,
        'center': _whom,
        'centerHand': _hand,
        'sides': _whom,
        'beats': _beats(0),
      },
      renderTemplate: '{move} [{axis}] [{?balance}and balance]',
      searchKeywords: const ['short wave', 'wave of four'],
    ),
    MoveDef(
      id: '${_p}form_long_wave',
      displayName: 'form long waves',
      params: {
        'who': _who,
        'whom': _whom,
        'whomHand': _hand,
        'balance': _no,
        'beats': _beats(0),
      },
      renderTemplate:
          '{who} {move} [with {whom}] [by the {whomHand}] '
          '[{?balance}and balance]',
      searchKeywords: const ['long wave', 'long waves'],
    ),
    // §7.4 Heys, chains and rights-and-lefts.
    MoveDef(
      id: '${_p}circular_hey',
      displayName: 'circular hey',
      params: {
        'who': _who,
        'whom': _whom,
        'slow': _no,
        'changes': _changes,
        'where': _where(['along', 'across', 'diagonally']),
        'shoulder': _shoulder,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[{who} dance] [{changes}] [{?slow}slow] changes of a {move} '
          '[, {whom} pass] [{shoulder} shoulder] [{where}] [, {destination}]',
      searchKeywords: const ['square hey'],
    ),
    MoveDef(
      id: '${_p}rights_and_lefts',
      displayName: 'rights and lefts',
      params: {
        'who': _who,
        'whom': _whom,
        'slow': _no,
        'changes': _changes,
        'where': _where(['along', 'across', 'diagonally']),
        'hand': _hand,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[{who} dance] [{changes}] [{?slow}slow] changes of {move} '
          '[, starting with {whom}] [by the {hand}] [{where}] '
          '[, {destination}]',
    ),
    MoveDef(
      id: '${_p}chain',
      displayName: 'chain',
      params: {
        'who': _who,
        'hand': _hand,
        'where': _where(['along', 'across', 'diagonally']),
        'open': _no,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{hand}-hand] [{?open}open] {move} [{where}] '
          '[, {destination}]',
    ),
    MoveDef(
      id: '${_p}figure_eight',
      displayName: 'figure eight',
      params: {
        'who': _who,
        'whom': _whom,
        'where': _where(['up', 'down', 'across']),
        'fraction': _fraction,
        'lead': _whom,
        'double': _no,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{fraction}] [{?double}double] {move} [{where}] '
          '[through {whom}] [{lead} leading] [, {destination}]',
      searchKeywords: const ['figure 8', 'half figure 8', 'double figure 8'],
    ),
    MoveDef(
      id: '${_p}dolphin_hey',
      displayName: 'dolphin hey',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulder,
        'where': _where(_heyPaths),
        'fraction': _fraction,
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate:
          '[{fraction}] {move} [{where}] [: {who}] [pass {whom}] '
          '[{shoulder} shoulder to start] [, end facing {endFacing}] '
          '[, {destination}]',
    ),
    MoveDef(
      id: '${_p}hey_for_three',
      displayName: 'hey for three',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulder,
        'where': _where(_heyPaths),
        'fraction': _fraction,
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate:
          '[{fraction}] {move} [{where}] [, {who}] [pass {whom}] '
          '[{shoulder} shoulder to start] [, {destination}]',
      searchKeywords: const ['reel of three'],
    ),
    MoveDef(
      id: '${_p}hey_for_four',
      displayName: 'hey for four',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulder,
        'where': _where(_heyPaths),
        'fraction': _fraction,
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate:
          '[{fraction}] {move} [{where}] [, {who}] [pass {whom}] '
          '[{shoulder} shoulder to start] [, {destination}]',
      searchKeywords: const ['reel of four', 'straight hey'],
    ),
    MoveDef(
      id: '${_p}hey_for_six',
      displayName: 'hey for six',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulder,
        'where': _where(_heyPaths),
        'fraction': _fraction,
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate:
          '[{fraction}] {move} [{where}] [, {who}] [pass {whom}] '
          '[{shoulder} shoulder to start] [, {destination}]',
      searchKeywords: const ['hey for 6', 'reel of six'],
    ),
    MoveDef(
      id: '${_p}tandem_reel',
      displayName: 'tandem reel',
      params: {
        'who': _who,
        'whom': _whom,
        'shoulder': _shoulder,
        'where': _where(_heyPaths),
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate:
          '{who} [{where}] {move} [with {whom}] [{shoulder} shoulder to start] '
          '[, {destination}]',
      searchKeywords: const ['Shetland reel'],
    ),
    MoveDef(
      id: '${_p}mirror_hey',
      displayName: 'mirror hey',
      params: {
        'who': _who,
        'whom': _whom,
        'fraction': _fraction,
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate:
          '[{fraction}] {move} [, {who} splitting] [{whom} to start] '
          '[, {destination}]',
      searchKeywords: const ['Grimstock hey', 'mirror heys'],
    ),
    MoveDef(
      id: '${_p}grand_chain',
      displayName: 'grand chain',
      params: {
        'who': _who,
        'whom': _whom,
        'changes': _changes,
        'hand': _hand,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[{who} dance] [{changes}] changes of a {move} '
          '[, starting with {whom}] [by the {hand}] [, {destination}]',
    ),
    // §7.5 Crossing, passing and travelling.
    MoveDef(
      id: '${_p}cross',
      displayName: 'cross',
      params: {
        'who': _who,
        'shoulder': _shoulder,
        'where': _where(['diagonally', 'along', 'across', 'up', 'down']),
        'endFacing': _endFacing,
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [passing {shoulder} shoulder] [{where}] '
          '[and face {endFacing}] [, {destination}]',
      searchKeywords: const ['cross over', 'cross the set'],
    ),
    MoveDef(
      id: '${_p}right_left_through',
      displayName: 'right and left through',
      params: {
        // The four dancers who take part, usually two couples (§9.1).
        'who': _who,
        'whom': _whom,
        'where': _where(['along', 'across', 'diagonally']),
        'withHands': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['yes', 'no', _u],
        ),
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[{who} dance a] {move} [{where}] [, {withHands}] '
          '[, courtesy turning {whom}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}fall_back',
      displayName: 'fall back',
      params: {
        'who': _who,
        'whom': _whom,
        // An unstated `where` is read as across, which is not shown (§7.5).
        'where': _where(['across', 'along', 'diagonally', 'up', 'down']),
        'distance': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['double', 'single', _u],
        ),
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [with {whom}] [{where}] [a {distance}] '
          '[, {destination}]',
    ),
    MoveDef(
      id: '${_p}forward_and_back',
      displayName: 'forward and back',
      params: {
        'who': _who,
        // Forward is the editor's suggestion, as a double is.
        'where': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          entryDefault: 'forward',
          choices: ['up', 'down', 'forward', _u],
        ),
        'formation': _where([
          'linesOfThree',
          'linesOfFour',
          'linesOfFive',
          'linesOfSix',
          'inARing',
        ]),
        // A double when the source gives no distance (the one exception to
        // R2, §7.5, §9.1 point 3), so `distance` never stores the sentinel.
        'distance': const ParamSpec(
          ParamKind.choice,
          defaultValue: 'double',
          choices: ['double', 'single'],
        ),
        'goBack': _no,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{formation}] {where} a {distance} [{?goBack}and back]',
      searchKeywords: const [
        'up a double',
        'down a double',
        'lines forward and back',
        'forward a double',
      ],
    ),
    MoveDef(
      id: '${_p}back_to_back',
      displayName: 'back-to-back',
      params: {
        'who': _who,
        'shoulder': _shoulder,
        'travel': _travel,
        'where': _where(['across', 'along']),
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{shoulder}-shoulder] {move} [{where}] [{travel}] '
          '[, {destination}]',
      searchKeywords: const ['back to back'],
    ),
    MoveDef(
      id: '${_p}siding',
      displayName: 'siding',
      params: {
        'who': _who,
        'shoulder': _shoulder,
        'where': _where(['across', 'along']),
        'style': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['straight', 'swirly', _u],
        ),
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{shoulder}-shoulder] [{style}] {move} [{where}] '
          '[, {destination}]',
      searchKeywords: const ['side', 'sharp siding', 'Playford siding'],
    ),
    MoveDef(
      id: '${_p}pass_through',
      displayName: 'pass through',
      params: {
        'who': _who,
        'where': _where(['along', 'across', 'diagonally', 'up', 'down']),
        'shoulder': _shoulder,
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [{shoulder} shoulders] [{where}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}promenade',
      displayName: 'promenade',
      params: {
        'who': _who,
        'where': _where(['along', 'across', 'up', 'down']),
        'direction': _spin,
        'fraction': _fraction,
        'places': _places,
        'singleFile': _no,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} [{?singleFile}single file] {move} [{fraction}] [{places}] '
          '[{direction}] [{where}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}poussette',
      displayName: 'poussette',
      params: {
        // The dancers who push, or push first (§7.5, Q8).
        'who': _who,
        'whom': _whom,
        'fraction': _fraction,
        'direction': _spin,
        // Whether `who` pushes or draws (ADR-006 §9.3). Unstated reads as
        // push, which is what `who` names (Q8).
        'style': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['push', 'draw', _u],
        ),
        'switchPush': _no,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '[with {whom},] [{fraction}] {move} [{direction}] [, {who}] '
          '[{style}] [{?switchPush}first] [, {destination}]',
      searchKeywords: const ['draw poussette'],
    ),
    MoveDef(
      id: '${_p}arch',
      displayName: 'arch',
      params: {'who': _who, 'beats': _beats(4)},
      renderTemplate: '{who} {move}',
    ),
    MoveDef(
      id: '${_p}rollaway',
      displayName: 'roll away',
      params: {
        'who': _who,
        'whom': _whom,
        'where': _where(['along', 'across', 'up', 'down']),
        'halfSashay': _no,
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [{whom}] [{where}] [{?halfSashay}with a half sashay] '
          '[, {destination}]',
      searchKeywords: const ['rollaway'],
    ),
    MoveDef(
      id: '${_p}change_places',
      displayName: 'change places',
      params: {
        'who': _who,
        'whom': _whom,
        // `none` is "without hands" (§7.5).
        'hand': const ParamSpec(
          ParamKind.choice,
          defaultValue: _u,
          choices: ['right', 'left', 'none', _u],
        ),
        'where': _where(['along', 'across', 'diagonally', 'up', 'down']),
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [with {whom}] [{hand}] [{where}] [, {destination}]',
      searchKeywords: const ['change', 'trade places'],
    ),
    MoveDef(
      id: '${_p}pull_by',
      displayName: 'pull by',
      params: {
        'who': _who,
        'whom': _whom,
        'hand': _hand,
        'where': _where(['along', 'across', 'diagonally']),
        'destination': _destination,
        'beats': _beats(2),
      },
      renderTemplate:
          '{who} [{hand} hand] {move} [{whom}] [{where}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}contra_corners',
      displayName: 'contra corners',
      params: {
        // The dancers who turn their corners, usually the 1s.
        'who': _who,
        'destination': _destination,
        'beats': _beats(16),
      },
      renderTemplate: '{who} {move} [, {destination}]',
    ),
    MoveDef(
      id: '${_p}lead',
      displayName: 'lead',
      params: {
        'who': _who,
        'where': _where(['up', 'down', 'out', 'toTheMiddle', 'back']),
        'whom': _whom,
        'destination': _destination,
        'beats': _beats(4),
      },
      renderTemplate:
          '{who} {move} [{where}] [through {whom}] [, {destination}]',
    ),
    MoveDef(
      id: '${_p}cast',
      displayName: 'cast',
      // One parameter shape with contra's `cast` (#770), so a contra-imported
      // English dance re-reads one to one (F5): the maintainer's decision of
      // 2026-11-19 (§7.5, §9.4).
      params: {
        'who': _who,
        // `left`/`right` is the shoulder turned over, not a side of the set:
        // clockwise is over the right shoulder, counterclockwise the left.
        'direction': _where(['left', 'right', 'up', 'down']),
        // "Cast off" is `down`, one place, unless a number is stated.
        'places': _places,
        'whom': _whom,
        'destination': _castDestination,
        'beats': _beats(4),
      },
      // `{direction}` is always worded: "back" when unstated, "back left",
      // "back right", "up" or "down" (`ecdSlotWords`).
      renderTemplate:
          '{who} {move} {direction} [{places}] [around {whom}] '
          '[{destination}]',
      searchKeywords: const ['cast off', 'cast up', 'cast down'],
    ),
    MoveDef(
      id: '${_p}galop',
      displayName: 'galop',
      params: {
        'who': _who,
        'where': _where(['up', 'down', 'along', 'across']),
        'goBack': _no,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{who} {move} [{where}] [{?goBack}and back] [, {destination}]',
      searchKeywords: const ['gallop'],
    ),
    MoveDef(
      id: '${_p}chevron',
      displayName: 'chevron',
      params: {
        // The crossing pair; `whom` is the casting pair (§7.5, Q10d).
        'who': _who,
        'shoulder': _shoulder,
        'whom': _whom,
        'castShoulder': _shoulder,
        'destination': _destination,
        'beats': _beats(8),
      },
      renderTemplate:
          '{move}: {who} cross [passing {shoulder} shoulder] and back into '
          'the other pair\'s places [, as {whom} cast] '
          '[over the {castShoulder} shoulder] [, {destination}]',
      // "Pothooks" is probably another name for chevron (§9.1 point 8).
      searchKeywords: const ['pothooks'],
    ),
    MoveDef(
      id: '${_p}bend_line',
      displayName: 'bending the line',
      params: {'who': _who, 'beats': _beats(0)},
      renderTemplate: '{move}',
      searchKeywords: const ['bend the line'],
    ),
  ],
  aliases: const [
    // Stored under its own ID so the two names never merge (§7.2), as in
    // contra.
    MoveAlias(
      id: '${_p}swat_the_flea',
      displayName: 'swat the flea',
      targetMove: '${_p}box_the_gnat',
      pinnedParams: {'hand': 'left'},
      inversePairId: '${_p}box_the_gnat',
    ),
  ],
);
