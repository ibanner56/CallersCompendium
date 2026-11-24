/// The opt-in migration of an English Country Dance stored before the ECD
/// taxonomy existed (ADR-006 §12.1 F5): its contra moves and contra shape
/// become their ECD counterparts where the meaning is clear, and its
/// unrecognized lines are re-read by the ECD parser.
///
/// Nothing here runs on its own. The caller runs it for one dance or for
/// all, after seeing what it would change; a dance it does not touch keeps
/// its contra moves, which still display through the contra taxonomy (§5.1).
library;

import '../dialect/dialect.dart';
import '../dialect/renderer.dart';
import '../model/enums.dart';
import '../model/figure.dart';
import '../storage/figure_reparse.dart';
import '../model/formation.dart';
import '../model/phrase_structure.dart';
import '../taxonomy/contra_taxonomy.dart';
import '../taxonomy/ecd_taxonomy.dart';
import '../taxonomy/taxonomy_registry.dart';
import '../validation/validation.dart';
import 'ecd_figure_parser.dart';
import 'ecd_formation.dart';
import 'figure_text_scrub.dart';
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

  /// Contra moves that became ECD figures: a one-to-one twin, or a reading
  /// of the move's displayed words by the ECD grammar.
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
///   stores has the same meaning there ([ecdTwinOfContraMove]);
/// - any other contra move is read again from its displayed words by the ECD
///   grammar ([ecdReadingOfContraWording]), and stays as it is when they do
///   not read in full, when its words mean something else in ECD, or when
///   the reading would drop or change a value it stores;
/// - an import-gap custom line is re-read by the ECD parser
///   ([reparseImportGapFigures] with ECD's taxonomy), a bar range counted by
///   [meter], or [phraseStructure] when it states none, or, where
///   [phraseStructure]'s phrases differ in beats per bar, by the phrase each
///   bar falls in;
/// - the shape becomes the ECD shape it names ([ecdFormationFromContra]).
///
/// In a twin, only a value the contra figure *stores* is carried, never a contra
/// default, so the migrated figure states nothing the dance did not (R2). The
/// exceptions are values the contra move's own name states (a see saw is a
/// left-shoulder back to back; a forward and back goes back, and its distance
/// is a double, §9.1 point 3) and a figure's count: one with no stored beats
/// keeps the count it danced in contra when the twin's would differ, so the
/// dance keeps its length.
EcdMigration migrateEcdDance({
  required List<Figure> figures,
  required Formation formation,
  String? meter,
  PhraseStructure? phraseStructure,
}) {
  var converted = 0;
  List<Figure>? rewritten;
  final ecdShape = ecdFormationFromContra(formation);
  final ringDancers = ecdRingDancers(ecdShape.shape);
  for (var i = 0; i < figures.length; i++) {
    final result = _convert(figures[i], ringDancers);
    if (result == null) continue;
    rewritten ??= List<Figure>.of(figures);
    rewritten[i] = result.figure;
    converted += result.count;
  }
  // A line's bar range counts by the dance's meter or phrases, as in Re-check.
  final reread = reparseImportGapFigures(
    rewritten ?? figures,
    taxonomy: shippedTaxonomies.forForm(DanceForm.ecd),
    meter: meter,
    phraseStructure: phraseStructure,
  );
  return EcdMigration(
    figures: reread.figures,
    formation: ecdShape,
    movesConverted: converted,
    linesReread: reread.upgradedCount,
  );
}

({Figure figure, int count})? _convert(
  Figure figure,
  int? ringDancers, {
  bool inContainer = false,
}) {
  if (figure.isContainer) {
    final children = figure.subFigures;
    List<Figure>? next;
    var count = 0;
    for (var i = 0; i < children.length; i++) {
      final result = _convert(children[i], ringDancers, inContainer: true);
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
  var twin = ecdTwinOfContraMove(figure);
  if (twin == null) {
    final read = ecdReadingOfContraWording(figure, ringDancers: ringDancers);
    // A container stays a step of no other container (the nesting rule
    // Re-check keeps), so a reading that is one replaces only a top-level
    // figure.
    if (read != null && !(inContainer && read.isContainer)) twin = read;
  }
  return twin == null ? null : (figure: twin, count: 1);
}

final FigureRenderer _contraWords = FigureRenderer(contraTaxonomy);

/// Contra moves never re-read from their wording: the ones [_twins] leaves
/// out because their `who` names another group in ECD, form short waves,
/// whose center and sides the reading would lose, and a petronella, whose
/// contra display hides whether it includes the balance.
const Set<String> _unlikeInEcd = {
  'hey',
  'poussette',
  'mad_robin',
  'circular_hey',
  'form_long_waves',
  'form_short_waves',
  'petronella',
};

/// [figure], a contra move with no one-to-one twin, read again from its
/// displayed words by the ECD grammar (Hudson's decision: twins first, then
/// "figures that can parse from ECD we should try to parse"). Null when the
/// words do not read in full as ECD figures.
///
/// The words are the contra display (`renderSummary` in the canonical
/// dialect, role tokens kept, the wording override ignored), which leaves out
/// the defaults contra silences, so what is read is what the person saw. A
/// value the display shows that the figure did not store can become a stated
/// one here; that is the price of this step, accepted with it. The reverse is
/// refused: a non-default value the words hide, or a stored value (its contra
/// default included, since the contra editor seeds every param) that the
/// reading would drop ([_keepStoredValues]). A figure whose subject the
/// importer assumed ([Figure.assumedSubject]) is not read this way, since its
/// words state that subject (R2). Its note, progression mark, walkthrough and
/// wording overrides are kept, and with no stored count it keeps the count it
/// danced in contra. [ringDancers] counts a ring fraction in places, as for
/// typed entry.
Figure? ecdReadingOfContraWording(Figure figure, {int? ringDancers}) {
  if (figure.isContainer || figure.isCustom || figure.assumedSubject) {
    return null;
  }
  if (contraTaxonomy.resolve(figure.move) == null) return null;
  if (_unlikeInEcd.contains(figure.move)) return null;
  if (contraTaxonomy
      .validateFigure(figure)
      .any((issue) => issue.severity == ValidationSeverity.error)) {
    return null;
  }
  final String? words = _shownWords(figure);
  if (words == null) return null;
  // A value the figure states that its words do not show (a promenade's
  // destination) would be lost: such a figure is not read this way.
  final def = contraTaxonomy.resolve(figure.move)!;
  for (final entry in figure.params.entries) {
    if (entry.key == 'beats' || entry.value == null) continue;
    if (entry.value == def.params[entry.key]?.defaultValue) continue;
    final without = Figure(
      move: figure.move,
      params: {...figure.params}..remove(entry.key),
    );
    if (_shownWords(without) == words) return null;
  }
  final stored = figure.params['beats'];
  final read = recognizeEcdLine(
    scrubFigureText(words),
    beats: stored is int ? stored : 0,
    ringDancers: ringDancers,
  );
  if (read == null || !_allEcd(read)) return null;
  final kept = _keepStoredValues(figure, read);
  if (kept == null) return null;
  // A note the reading made (an uncounted ring fraction) and the figure's
  // own note: keep both only when one is absent.
  if (read.note != null && figure.note != null) return null;
  var out = kept.copyWith(
    note: read.note ?? figure.note,
    progression: figure.progression,
    walkthroughOverride: figure.walkthroughOverride,
    wordingOverride: figure.wordingOverride,
  );
  if (stored == null) {
    final danced = contraTaxonomy.effectiveParams(figure)['beats'];
    // A container's span is always stored; a leaf's count may be its usual.
    final usual = out.isContainer
        ? out.params['beats']
        : ecdTaxonomy.effectiveParams(out)['beats'];
    if (danced != null && usual != danced) {
      out = out.copyWith(params: {...out.params, 'beats': danced});
    }
  }
  // Containers are structural, not taxonomy moves: each leaf is checked.
  final invalid = !_leavesValidInEcd(out);
  return invalid ? null : out;
}

/// [figure]'s own words as the figure list shows them, summary modifiers
/// such as a balance included, never the person's wording override (which
/// can name another move); null when it cannot be rendered.
String? _shownWords(Figure figure) {
  try {
    return _contraWords.renderSummary(
      figure.copyWith(wordingOverride: null),
      Dialect.canonical,
    );
  } catch (_) {
    return null;
  }
}

/// Whether [value] states something: not absent, `false`, `unspecified`,
/// empty text or an empty list (or one holding only `unspecified`).
bool _states(Object? value) => switch (value) {
  null || false || 'unspecified' || '' => false,
  List(:final isEmpty) when isEmpty => false,
  List() => value.any(_states),
  _ => true,
};

/// [reading], [figure]'s ECD reading, holding every value [figure] stores,
/// its contra default included (the contra editor seeds them all), or null
/// when it would drop or change one.
///
/// A value is held when a step states its param with the same value (a
/// contra `who` as ECD's one-dancer list), when it is a balance the reading
/// made a step of its own (a swing's `prefix: balance`, a pull by's
/// `balance: true`), or when it is a formation the reading states as `who`
/// (side couples forward and back). A param a step states with another value
/// changes the figure, so the reading is refused. A param no step has a place
/// for is dropped, so the reading is refused. Otherwise, when the twin table
/// carries the param with the same meaning and exactly one step is the move's
/// twin, the value is set on that step (a hand-entered swing's `endFacing:
/// in`, which its words hide); else the reading is refused.
Figure? _keepStoredValues(Figure figure, Figure reading) {
  final twin = _twins[figure.move];
  var out = reading;
  for (final entry in figure.params.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key == 'beats' || !_states(value)) continue;
    if (_noOpValues[key] == value) continue;
    final leaves = _leaves(out).toList();
    if (_madeBalanceStep(key, value, leaves)) continue;
    if (key == 'formation' &&
        leaves.any((leaf) => _sameValue(value, leaf.params['who']))) {
      continue;
    }
    final placed = leaves
        .where(
          (leaf) =>
              ecdTaxonomy.resolve(leaf.move)?.params.containsKey(key) ?? false,
        )
        .toList();
    if (placed.isEmpty) return null;
    final stating = placed.where((leaf) => _states(leaf.params[key]));
    if (stating.isNotEmpty) {
      if (stating.every((leaf) => _sameValue(value, leaf.params[key]))) {
        continue;
      }
      return null;
    }
    final twinLeaves = placed.where((leaf) => leaf.move == twin?.id).toList();
    if (twin == null || !twin.carried.contains(key) || twinLeaves.length != 1) {
      return null;
    }
    out = _replaceLeaf(
      out,
      twinLeaves.single,
      twinLeaves.single.copyWith(
        params: {
          ...twinLeaves.single.params,
          key: key == 'who' && value is String ? [value] : value,
        },
      ),
    );
  }
  return out;
}

/// Whether [held], an ECD value, says what [stored], a contra value, says: the
/// same value, or a contra `who` as a one-dancer list.
bool _sameValue(Object? stored, Object? held) {
  if (stored == held) return true;
  if (held is! List) return false;
  if (stored is List) {
    return stored.length == held.length &&
        stored.every((value) => held.contains(value));
  }
  return held.length == 1 && held.single == stored;
}

/// Whether [key] is a balance (a `prefix: balance` or `balance: true`) that
/// the reading made a step of its own.
bool _madeBalanceStep(String key, Object? value, List<Figure> leaves) =>
    ((key == 'prefix' && value == 'balance') ||
        (key == 'balance' && value == true)) &&
    leaves.length > 1 &&
    leaves.any((leaf) => leaf.move == 'ecd_balance');

/// [figure] with [from], one of its leaves, replaced by [to].
Figure _replaceLeaf(Figure figure, Figure from, Figure to) {
  if (identical(figure, from)) return to;
  if (!figure.isContainer) return figure;
  final subs = [
    for (final sub in figure.subFigures) _replaceLeaf(sub, from, to),
  ];
  return figure.copyWith(
    params: {...figure.params, 'figures': List<Figure>.unmodifiable(subs)},
  );
}

Iterable<Figure> _leaves(Figure figure) sync* {
  if (figure.isContainer) {
    for (final sub in figure.subFigures) {
      yield* _leaves(sub);
    }
  } else {
    yield figure;
  }
}

bool _leavesValidInEcd(Figure figure) => figure.isContainer
    ? figure.subFigures.every(_leavesValidInEcd)
    : !ecdTaxonomy
          .validateFigure(figure)
          .any((issue) => issue.severity == ValidationSeverity.error);

bool _allEcd(Figure figure) => figure.isContainer
    ? figure.subFigures.every(_allEcd)
    : !figure.isCustom && ecdTaxonomy.resolve(figure.move) != null;

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
  'pass_through': _Twin('ecd_pass_through', {
    ..._who,
    'where',
    'shoulder',
    'beats',
  }),
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
const Map<String, Object> _noOpValues = {
  'grip': 'none',
  'prefix': 'none',
  // A figure 8's `none` says no direction (contra_taxonomy.dart).
  'where': 'none',
};

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
  Formation formation, {
  String? meter,
  PhraseStructure? phraseStructure,
}) {
  final out = migrateEcdDance(
    figures: figures,
    formation: formation,
    meter: meter,
    phraseStructure: phraseStructure,
  );
  return EcdDanceMigrationResult(
    figures: out.figures,
    formation: out.formation,
    movesConverted: out.movesConverted,
    linesReread: out.linesReread,
    shapeChanged: out.shapeChanged(formation),
  );
}
