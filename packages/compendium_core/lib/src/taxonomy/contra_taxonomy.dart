import '../model/enums.dart';
import '../model/figure.dart' show customMoveId;
import 'move_def.dart';
import 'param_types.dart';
import 'taxonomy.dart';

/// Version of the seeded contra taxonomy. Bumped when moves/params change.
const int contraTaxonomyVersion = 1;

// Shared parameter specs.
const _beats4 = ParamSpec(ParamKind.beats, defaultValue: 4);

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
        'halfSashay': ParamSpec(ParamKind.flag, defaultValue: false),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
      renderTemplate: '{who} {move}',
      goodBeats: [4],
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
