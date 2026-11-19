/// The opt-in migration of an English Country Dance stored before the ECD
/// taxonomy existed (ADR-006 §12.1 F5): its contra moves and contra shape
/// become their ECD counterparts where the meaning is clear, and its
/// unrecognized lines are re-read by the ECD parser.
///
/// Nothing here runs on its own. The caller runs it for one dance or for
/// all, after seeing what it would change; a dance it does not touch keeps
/// its contra moves, which still display through the contra taxonomy (§5.1).
library;

import '../model/enums.dart';
import '../model/figure.dart';
import '../storage/figure_reparse.dart';
import '../model/formation.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/ecd_taxonomy.dart';
import '../taxonomy/taxonomy_registry.dart';
import '../validation/validation.dart';
import 'ecd_formation.dart';
import 'reparse_custom_figures.dart';

/// What [migrateEcdDance] would change in one dance.
class EcdMigration {
  const EcdMigration({
    required this.figures,
    required this.formation,
    required this.movesConverted,
    required this.linesReread,
  });

  /// The figure list after the migration; the input list itself when no
  /// figure changes.
  final List<Figure> figures;

  /// The formation after the migration (its ECD shape).
  final Formation formation;

  /// Contra moves that became their ECD counterpart.
  final int movesConverted;

  /// Unrecognized lines (import-gap customs) the ECD parser now reads.
  final int linesReread;

  /// Whether the formation's shape changed.
  bool shapeChanged(Formation before) => formation != before;

  /// Whether anything changed at all, given the formation it started from.
  bool changes(Formation before) =>
      movesConverted > 0 || linesReread > 0 || shapeChanged(before);
}

/// [figures] and [formation] of an English Country Dance, migrated to the
/// ECD taxonomy where the meaning is clear (ADR-006 §12.1 F5):
///
/// - a contra move with an ECD twin becomes that twin when every value it
///   stores has the same meaning there ([ecdTwinOfContraMove]); a contra move
///   with no twin, or storing a value its twin cannot hold, stays as it is;
/// - an import-gap custom line is re-read by the ECD parser
///   ([reparseImportGapFigures] with ECD's taxonomy);
/// - the shape becomes the ECD shape it names ([ecdFormationFromContra]).
///
/// Only a value the contra figure *stores* is carried, never a contra
/// default, so the migrated figure states nothing the dance did not (R2). The
/// exceptions are values the contra move's own name states (a see saw is a
/// left-shoulder back to back; a forward and back goes back, and its distance
/// is a double, §9.1 point 3) and a figure's count: one with no stored beats
/// keeps the count it danced in contra when the twin's would differ, so the
/// dance keeps its length.
EcdMigration migrateEcdDance({
  required List<Figure> figures,
  required Formation formation,
}) {
  var converted = 0;
  List<Figure>? rewritten;
  for (var i = 0; i < figures.length; i++) {
    final result = _convert(figures[i]);
    if (result == null) continue;
    rewritten ??= List<Figure>.of(figures);
    rewritten[i] = result.figure;
    converted += result.count;
  }
  final reread = reparseImportGapFigures(
    rewritten ?? figures,
    taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
  );
  return EcdMigration(
    figures: reread.figures,
    formation: ecdFormationFromContra(formation),
    movesConverted: converted,
    linesReread: reread.upgradedCount,
  );
}

({Figure figure, int count})? _convert(Figure figure) {
  if (figure.isContainer) {
    final children = figure.subFigures;
    List<Figure>? next;
    var count = 0;
    for (var i = 0; i < children.length; i++) {
      final result = _convert(children[i]);
      if (result == null) continue;
      next ??= List<Figure>.of(children);
      next[i] = result.figure;
      count += result.count;
    }
    if (next == null) return null;
    return (
      figure: figure.copyWith(
        params: {...figure.params, 'figures': List<Figure>.unmodifiable(next)},
      ),
      count: count,
    );
  }
  final twin = ecdTwinOfContraMove(figure);
  return twin == null ? null : (figure: twin, count: 1);
}

/// One contra move's ECD twin: the twin's id, the contra params carried
/// across unchanged, and values the contra move's name itself states.
class _Twin {
  const _Twin(this.id, this.carried, {this.stated = const {}, this.fill});
  final String id;
  final Set<String> carried;

  /// Values the contra move's name states, stored on the twin whatever the
  /// contra figure stores (`see saw` is a left-shoulder back to back).
  final Map<String, Object> stated;

  /// Values the contra move's name states, stored only when the contra
  /// figure leaves them unstated (`forward and back` goes back).
  final Map<String, Object>? fill;
}

const _who = {'who'};

/// The contra moves with an ECD twin of the same meaning, and which of their
/// params carry across (ADR-006 §12.1 F5). A move not listed here is left as
/// it is: a contra hey, poussette, mad robin, circular hey or form long waves,
/// whose `who` names a different group in each form (the pair that pushes,
/// steps in front, passes first or faces in, against ECD's subject), a
/// petronella, which in contra includes a balance, and form short waves,
/// whose center and sides dancers the ECD short wave does not show.
const Map<String, _Twin> _twins = {
  'circle': _Twin('ecd_circle', {'direction', 'places', 'singleFile', 'beats'}),
  'star': _Twin('ecd_star', {'hand', 'places', 'beats'}),
  'allemande': _Twin('ecd_hand_turn', {..._who, 'hand', 'travel', 'beats'}),
  'two_hand_turn': _Twin('ecd_two_hand_turn', {..._who, 'travel', 'beats'}),
  'do_si_do': _Twin('ecd_back_to_back', {
    ..._who,
    'shoulder',
    'travel',
    'beats',
  }),
  'see_saw': _Twin(
    'ecd_back_to_back',
    {..._who, 'travel', 'beats'},
    stated: {'shoulder': 'left'},
  ),
  'shoulder_round': _Twin('ecd_shoulder_round', {
    ..._who,
    'shoulder',
    'travel',
    'beats',
  }),
  'swing': _Twin('ecd_swing', {..._who, 'endFacing', 'beats'}),
  'chain': _Twin('ecd_chain', {..._who, 'hand', 'where', 'beats'}),
  'dolphin_hey': _Twin('ecd_dolphin_hey', {
    ..._who,
    'whom',
    'shoulder',
    'beats',
  }),
  'hey_for_three': _Twin('ecd_hey_for_three', {
    ..._who,
    'whom',
    'shoulder',
    'beats',
  }),
  'balance': _Twin('ecd_balance', {..._who, 'hand', 'beats'}),
  'balance_the_ring': _Twin('ecd_balance_ring', {'beats'}),
  'box_the_gnat': _Twin('ecd_box_the_gnat', {
    ..._who,
    'hand',
    'balance',
    'beats',
  }),
  'swat_the_flea': _Twin('ecd_swat_the_flea', {
    ..._who,
    'hand',
    'balance',
    'beats',
  }),
  'forward_and_back': _Twin(
    'ecd_forward_and_back',
    {'formation', 'goBack', 'beats'},
    fill: {'goBack': true, 'distance': 'double'},
  ),
  'long_lines': _Twin(
    'ecd_forward_and_back',
    {'goBack', 'beats'},
    fill: {'goBack': true, 'distance': 'double'},
  ),
  'pass_through': _Twin('ecd_pass_through', {'where', 'shoulder', 'beats'}),
  'right_left_through': _Twin('ecd_right_left_through', {'where', 'beats'}),
  'roll_away': _Twin('ecd_rollaway', {..._who, 'whom', 'halfSashay', 'beats'}),
  'orbit': _Twin('ecd_orbit', {..._who, 'direction', 'travel', 'beats'}),
  'gate': _Twin('ecd_gate', {
    ..._who,
    'whom',
    'pair',
    'direction',
    'travel',
    'endFacing',
    'beats',
  }),
  'pull_by': _Twin('ecd_pull_by', {..._who, 'hand', 'where', 'beats'}),
  'contra_corners': _Twin('ecd_contra_corners', {..._who, 'beats'}),
  'turn_alone': _Twin('ecd_turn_alone', {..._who, 'custom', 'beats'}),
};

/// Contra values that state nothing: a star with no grip named, a swing
/// with no balance or meltdown before it.
const Map<String, Object> _noOpValues = {'grip': 'none', 'prefix': 'none'};

/// The contra move ids [ecdTwinOfContraMove] converts.
Set<String> get ecdMigratableContraMoves => _twins.keys.toSet();

/// [figure], a contra move, as its ECD twin, or null when it has none or
/// stores a value the twin cannot hold with the same meaning. Its note,
/// progression mark, walkthrough and wording overrides are kept.
///
/// A `who` the importer assumed rather than read ([Figure.assumedSubject]) is
/// not carried: the twin leaves it unspecified (R2).
Figure? ecdTwinOfContraMove(Figure figure) {
  if (figure.isContainer || figure.isCustom) return null;
  final twin = _twins[figure.move];
  if (twin == null) return null;
  final params = <String, Object?>{};
  for (final entry in figure.params.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value == null) continue;
    if (key == 'who' && figure.assumedSubject) continue;
    if (!twin.carried.contains(key)) {
      // A value that changes nothing in contra (a `false` flag, the
      // `unspecified` sentinel, long lines' own formation) is not a
      // statement the twin must hold.
      if (value == false || value == 'unspecified' || value == '') continue;
      if (_noOpValues[key] == value) continue;
      // A value the move's own name states (a see saw's left shoulder) is
      // the twin's to state too.
      if (twin.stated[key] == value) continue;
      if (key == 'formation' && value == 'longLines') continue;
      return null;
    }
    params[key] = key == 'who' && value is String ? [value] : value;
  }
  // A forward and back in long lines: the formation is the movement's own.
  if (params['formation'] == 'longLines') params.remove('formation');
  for (final entry in (twin.fill ?? const <String, Object>{}).entries) {
    params.putIfAbsent(entry.key, () => entry.value);
  }
  params.addAll(twin.stated);
  var candidate = Figure(
    move: twin.id,
    params: params,
    note: figure.note,
    progression: figure.progression,
    walkthroughOverride: figure.walkthroughOverride,
    wordingOverride: figure.wordingOverride,
  );
  // A figure with no stored count danced the contra move's usual count for
  // what it states (a forward and back that does not go back is 4 beats);
  // keep that length where the twin's usual count differs.
  if (!params.containsKey('beats')) {
    final danced = contraTaxonomy.effectiveParams(figure)['beats'];
    final usual = ecdTaxonomy.effectiveParams(candidate)['beats'];
    if (danced != null && danced != usual) {
      candidate = candidate.copyWith(params: {...params, 'beats': danced});
    }
  }
  final invalid = ecdTaxonomy
      .validateFigure(candidate)
      .any((issue) => issue.severity == ValidationSeverity.error);
  return invalid ? null : candidate;
}

/// [migrateEcdDance] as the repository's [EcdDanceMigrator], for
/// `DanceRepository.previewEcdMigration` and `migrateEcdDances`.
EcdDanceMigrationResult migrateEcdDanceForStorage(
  List<Figure> figures,
  Formation formation,
) {
  final out = migrateEcdDance(figures: figures, formation: formation);
  return EcdDanceMigrationResult(
    figures: out.figures,
    formation: out.formation,
    movesConverted: out.movesConverted,
    linesReread: out.linesReread,
    shapeChanged: out.shapeChanged(formation),
  );
}
