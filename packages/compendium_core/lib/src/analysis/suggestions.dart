/// Suggest the next dance (#2343): ranks candidate dances for one position in
/// a program and says why, factor by factor.
///
/// Pure and Flutter-free. The app runs [rankSuggestions] off the UI thread over
/// the builder picker's current results. The factors, their effects and the
/// shipped weights are described in `docs/design/suggestions.md`.
///
/// The position is given as the program's slots before it and after it, so a
/// later caller can rank for a point inside the program (#2344) without a new
/// scorer; the builder ranks for the end, with every slot before and none
/// after.
///
/// Ranking only reorders. Every candidate comes back, once.
library;

import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/enums.dart';
import '../model/figure.dart' show customMove;
import '../model/formation.dart';
import '../model/program.dart';
import '../search/collection_search_state.dart' show calendarMonthsBefore;
import '../taxonomy/taxonomy.dart';
import '../taxonomy/user_figure_use.dart';
import 'matrix_column_config.dart';
import 'program_matrix.dart';
import 'suggestion_settings.dart';

/// Which side of the position a neighbour is on.
enum SuggestionNeighbor { previous, next }

/// Why a candidate moved, or a note about its ranking. The app turns each kind
/// into a sentence.
enum SuggestionReasonKind {
  /// [SuggestionReason.count] moves no other dance in the program uses.
  newMoves,

  /// The move [SuggestionReason.moveKey] (a matrix column key) overlaps the
  /// [SuggestionReason.neighbor]'s beats, by the matrix's alert rule; with
  /// [SuggestionReason.count] colliding moves in all.
  beatOverlap,

  /// Same formation family as the [SuggestionReason.neighbor].
  sameFormationAsNeighbor,

  /// The program already has [SuggestionReason.count] dances in this
  /// formation family.
  formationCommonTonight,

  /// No other dance in the program is in this formation family.
  firstFormationTonight,

  /// The dance's level fits the difficulty curve here.
  fitsCurve,

  /// Harder than the curve wants here.
  harderThanCurve,

  /// Easier than the curve wants here.
  easierThanCurve,

  /// Called at this venue on [SuggestionReason.date], inside the window.
  calledHereRecently,

  /// Last called at this venue on [SuggestionReason.date], before the window.
  notCalledHereSince,

  /// Never called at this venue.
  neverCalledHere,

  /// Note: the program has no venue, so the venue factor was skipped.
  venueSkippedNoVenue,

  /// Note: no factor moved this dance.
  noFactorApplied,

  /// Note: an English dance, listed after the ranked ones unranked.
  englishNotCovered,
}

/// One reason. [effect] is signed (positive raises the dance) and already
/// weighted; a note has an effect of zero.
@immutable
class SuggestionReason {
  const SuggestionReason(
    this.kind, {
    this.factor,
    this.effect = 0,
    this.count,
    this.moveKey,
    this.formation,
    this.neighbor,
    this.date,
  });

  final SuggestionReasonKind kind;

  /// The factor that gave this reason, or null for a note that belongs to no
  /// factor.
  final SuggestionFactor? factor;
  final double effect;
  final int? count;
  final String? moveKey;
  final FormationShape? formation;
  final SuggestionNeighbor? neighbor;
  final DateTime? date;

  /// Whether this reason moved the dance (a note does not).
  bool get moved => effect != 0;

  @override
  bool operator ==(Object other) =>
      other is SuggestionReason &&
      other.kind == kind &&
      other.factor == factor &&
      other.effect == effect &&
      other.count == count &&
      other.moveKey == moveKey &&
      other.formation == formation &&
      other.neighbor == neighbor &&
      other.date == date;

  @override
  int get hashCode =>
      Object.hash(kind, factor, effect, count, moveKey, formation, neighbor);

  @override
  String toString() => 'SuggestionReason(${kind.name}, $effect)';
}

/// One candidate's place in the ranking.
@immutable
class RankedSuggestion {
  const RankedSuggestion({
    required this.danceId,
    required this.score,
    required this.ranked,
    required this.reasons,
  });

  final String danceId;
  final double score;

  /// False for a dance listed after the ranked ones, unranked (an English
  /// dance).
  final bool ranked;

  /// Every reason, the ones that moved it first, largest effect first; notes
  /// last. Never empty.
  final List<SuggestionReason> reasons;

  /// The reasons a row shows: the top one or two that moved it, or its first
  /// note when nothing did.
  List<SuggestionReason> get headline {
    final moved = reasons.where((r) => r.moved).take(2).toList();
    return moved.isNotEmpty ? moved : [reasons.first];
  }
}

/// Everything [rankSuggestions] reads. Plain data, so it can be sent to
/// another isolate.
@immutable
class SuggestionRequest {
  const SuggestionRequest({
    required this.slotsBefore,
    this.slotsAfter = const [],
    required this.programDances,
    required this.candidates,
    required this.settings,
    required this.today,
    this.collisionMode = MatrixCollisionMode.exactBeats,
    this.taxonomy,
    this.matrixConfig = MatrixColumnConfig.empty,
    this.userFigures = UserFigureCatalog.empty,
    this.levels = const [],
    this.hasVenue = false,
    this.calledHere = const {},
  });

  /// The program's slots before the position, in order (every slot, for the
  /// end of the program).
  final List<ProgramSlot> slotsBefore;

  /// The program's slots after the position (none, for the end).
  final List<ProgramSlot> slotsAfter;

  /// The dances the slots refer to, by id. A slot whose dance is missing reads
  /// as a dance with no figures, as the matrix shows a deleted one.
  final Map<String, Dance> programDances;

  /// The dances to rank, in the plain order they are shown in. Ties keep it.
  final List<Dance> candidates;

  final SuggestionSettings settings;

  /// The caller's calendar day, `DateTime.utc(y, m, d)` (`calendarDayAt`):
  /// the venue window counts back from it.
  final DateTime today;

  /// The "Flag exact beat overlap only" setting, as the matrix reads it.
  final MatrixCollisionMode collisionMode;

  /// The taxonomy, matrix column config and figures of your own the program's
  /// matrix is built with, so a move routes to the same column it shows in.
  final Taxonomy? taxonomy;
  final MatrixColumnConfig matrixConfig;
  final UserFigureCatalog userFigures;

  /// The difficulty vocabulary, for [DifficultyLevel.position].
  final List<DifficultyLevel> levels;

  /// Whether the program has a venue. Without one the venue factor is skipped.
  final bool hasVenue;

  /// Dances called at this program's venue, outside the program itself
  /// (`CalledFilter` with the venue and `currentProgramId`), each mapped to the
  /// date of its latest call there, or to null when no such call has a date
  /// (a slot with no recency date counts as called but falls in no window,
  /// docs/design/history-filters.md Q2). A dance absent was never called
  /// there.
  final Map<String, DateTime?> calledHere;
}

/// The result: every candidate once, ranked ones first (best first), then the
/// unranked ones in their plain order.
@immutable
class SuggestionRanking {
  const SuggestionRanking(this.order);

  final List<RankedSuggestion> order;
}

/// A dance the scorer stands in for a slot whose dance is missing.
Dance _missingDance(String id) => Dance(
  id: id,
  title: id,
  createdAt: DateTime.utc(1970),
  updatedAt: DateTime.utc(1970),
);

/// A formation family: Becket clockwise and counter-clockwise are one.
String _formationFamily(FormationShape shape) => switch (shape) {
  FormationShape.becketCw || FormationShape.becketCcw => 'becket',
  _ => shape.name,
};

/// Ranks [request]'s candidates. See the library comment.
SuggestionRanking rankSuggestions(SuggestionRequest request) {
  final scorer = _Scorer(request);
  final ranked = <(int, RankedSuggestion)>[];
  final unranked = <RankedSuggestion>[];
  for (var i = 0; i < request.candidates.length; i++) {
    final dance = request.candidates[i];
    // English dances are not ranked: the matrix's beat comparison assumes
    // contra's phrases, which English dances do not share (see
    // docs/design/suggestions.md, "English dances").
    if (dance.form == DanceForm.ecd) {
      unranked.add(
        RankedSuggestion(
          danceId: dance.id,
          score: 0,
          ranked: false,
          reasons: const [
            SuggestionReason(SuggestionReasonKind.englishNotCovered),
          ],
        ),
      );
      continue;
    }
    ranked.add((i, scorer.score(dance)));
  }
  ranked.sort((a, b) {
    final byScore = b.$2.score.compareTo(a.$2.score);
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
  });
  return SuggestionRanking([for (final (_, r) in ranked) r, ...unranked]);
}

/// What the scorer works out once per request, then applies per candidate.
class _Scorer {
  _Scorer(this.request)
    : _taxonomy = request.taxonomy,
      _settings = request.settings {
    const candidateId = '\u0000suggestion-candidate';
    final slots = [
      ...request.slotsBefore,
      ProgramSlot(
        id: candidateId,
        position: request.slotsBefore.length,
        danceId: candidateId,
      ),
      ...request.slotsAfter,
    ];
    final sections = Program.sectionsForSlots(slots);
    final groups = Program.alternateGroupsForSlots(slots);
    final candidateSlot = request.slotsBefore.length;
    for (var i = 0; i < slots.length; i++) {
      final danceId = slots[i].danceId;
      if (danceId == null) continue;
      if (i == candidateSlot) {
        _candidateRow = _rowsBefore.length;
        _candidateSection = sections[i];
        _candidateGroup = groups[i];
        continue;
      }
      final dance = request.programDances[danceId];
      final row = buildMatrixRow(
        dance ?? _missingDance(danceId),
        taxonomy: _taxonomy,
        section: sections[i],
        alternateGroup: groups[i],
        config: request.matrixConfig,
        userFigures: request.userFigures,
      );
      (i < candidateSlot ? _rowsBefore : _rowsAfter).add(row);
      _otherDances.add(dance);
    }
    for (final row in [..._rowsBefore, ..._rowsAfter]) {
      _programMoves.addAll(row.presentMoveIds);
    }
    _programMoves.remove(customMove);
    for (final dance in _otherDances.nonNulls) {
      final family = _formationFamily(dance.formation.shape);
      _formationCounts[family] = (_formationCounts[family] ?? 0) + 1;
    }

    // Neighbours do not depend on the candidate: work them out once, against
    // a placeholder row in the candidate's place.
    final probe = ProgramMatrix(
      columns: const [],
      rows: [
        ..._rowsBefore,
        MatrixRow(
          danceId: candidateId,
          title: '',
          firstMoveId: null,
          presentMoveIds: const {},
          section: _candidateSection,
          alternateGroup: _candidateGroup,
        ),
        ..._rowsAfter,
      ],
      collisionMode: request.collisionMode,
    );
    for (final r in probe.neighborRowIndices(_candidateRow)) {
      final neighbor = r < _candidateRow
          ? SuggestionNeighbor.previous
          : SuggestionNeighbor.next;
      final dance = _otherDances[r < _candidateRow ? r : r - 1];
      if (dance == null) continue;
      _neighborFamilies.putIfAbsent(
        _formationFamily(dance.formation.shape),
        () => neighbor,
      );
    }

    final positions = {
      for (final level in request.levels) level.id: level.position,
    };
    _levelPositions = positions;
    if (positions.isNotEmpty) {
      final sorted = positions.values.toList()..sort();
      _minLevel = sorted.first;
      _maxLevel = sorted.last;
    }
    _plannedBefore = Program.plannedDanceCountOf(request.slotsBefore);
    final known = [
      for (final dance in _otherDances.nonNulls)
        ?positions[dance.difficultyLevelId],
    ];
    _meanLevel = known.isEmpty
        ? null
        : known.reduce((a, b) => a + b) / known.length;
    _venueCutoff = calendarMonthsBefore(
      request.today,
      _settings.venueWindow.months,
    );
  }

  final SuggestionRequest request;
  final Taxonomy? _taxonomy;
  final SuggestionSettings _settings;
  final _rowsBefore = <MatrixRow>[];
  final _rowsAfter = <MatrixRow>[];

  /// The program's other dances, in row order; null where a slot's dance is
  /// missing (its row has no figures, and it has no formation or level).
  final _otherDances = <Dance?>[];
  final _programMoves = <String>{};
  final _formationCounts = <String, int>{};
  final _neighborFamilies = <String, SuggestionNeighbor>{};
  int _candidateRow = 0;
  int? _candidateSection;
  int? _candidateGroup;
  late final Map<String, int> _levelPositions;
  int _minLevel = 0;
  int _maxLevel = 0;
  int _plannedBefore = 0;
  double? _meanLevel;
  late final DateTime _venueCutoff;

  RankedSuggestion score(Dance dance) {
    final reasons = <SuggestionReason>[];
    final notes = <SuggestionReason>[];
    _variety(dance, reasons);
    _formation(dance, reasons);
    _curve(dance, reasons);
    _venue(dance, reasons, notes);
    reasons.sort((a, b) => b.effect.abs().compareTo(a.effect.abs()));
    final total = reasons.fold<double>(0, (sum, r) => sum + r.effect);
    return RankedSuggestion(
      danceId: dance.id,
      score: total,
      ranked: true,
      reasons: List.unmodifiable([
        ...reasons,
        if (reasons.isEmpty)
          const SuggestionReason(SuggestionReasonKind.noFactorApplied),
        ...notes,
      ]),
    );
  }

  void _add(
    List<SuggestionReason> into,
    SuggestionFactor factor,
    SuggestionReasonKind kind,
    double raw, {
    int? count,
    String? moveKey,
    FormationShape? formation,
    SuggestionNeighbor? neighbor,
    DateTime? date,
  }) {
    final effect = raw * _settings.weightOf(factor).multiplier;
    if (effect == 0) return;
    into.add(
      SuggestionReason(
        kind,
        factor: factor,
        effect: effect,
        count: count,
        moveKey: moveKey,
        formation: formation,
        neighbor: neighbor,
        date: date,
      ),
    );
  }

  /// Variety on the matrix: moves no other dance uses raise it; a move that
  /// overlaps a neighbour's beats, under the matrix's own alert rule, lowers
  /// it.
  void _variety(Dance dance, List<SuggestionReason> into) {
    const factor = SuggestionFactor.matrixVariety;
    if (_settings.matrixVariety == SuggestionWeight.off) return;
    if (_otherDances.isEmpty) return;
    final row = buildMatrixRow(
      dance,
      taxonomy: _taxonomy,
      section: _candidateSection,
      alternateGroup: _candidateGroup,
      config: request.matrixConfig,
      userFigures: request.userFigures,
    );
    final matrix = ProgramMatrix(
      columns: const [],
      rows: [..._rowsBefore, row, ..._rowsAfter],
      collisionMode: request.collisionMode,
    );
    final colliding = <String, SuggestionNeighbor>{};
    for (final key in row.beatSpansByMove.keys) {
      if (!matrix.isCollisionOnMove(_candidateRow, key)) continue;
      // Which side collided: the first neighbour that holds the move.
      var side = SuggestionNeighbor.previous;
      for (final r in matrix.neighborRowIndices(_candidateRow)) {
        if (matrix.rows[r].beatSpansByMove.containsKey(key)) {
          side = r < _candidateRow
              ? SuggestionNeighbor.previous
              : SuggestionNeighbor.next;
          break;
        }
      }
      colliding[key] = side;
    }
    if (colliding.isNotEmpty) {
      final first = colliding.entries.first;
      _add(
        into,
        factor,
        SuggestionReasonKind.beatOverlap,
        -(0.6 * colliding.length).clamp(0, 1).toDouble(),
        count: colliding.length,
        moveKey: first.key,
        neighbor: first.value,
      );
    }
    final fresh = row.presentMoveIds
        .where((key) => key != customMove && !_programMoves.contains(key))
        .length;
    if (fresh > 0) {
      _add(
        into,
        factor,
        SuggestionReasonKind.newMoves,
        (0.2 * fresh).clamp(0, 0.6).toDouble(),
        count: fresh,
      );
    }
  }

  /// Formation balance: not the neighbour's formation, and not one the
  /// program already has many of; a formation new to the program is a plus.
  void _formation(Dance dance, List<SuggestionReason> into) {
    const factor = SuggestionFactor.formationBalance;
    if (_settings.formationBalance == SuggestionWeight.off) return;
    if (_otherDances.isEmpty) return;
    final shape = dance.formation.shape;
    final family = _formationFamily(shape);
    final neighbor = _neighborFamilies[family];
    if (neighbor != null) {
      _add(
        into,
        factor,
        SuggestionReasonKind.sameFormationAsNeighbor,
        -0.6,
        formation: shape,
        neighbor: neighbor,
      );
    }
    final count = _formationCounts[family] ?? 0;
    if (count == 0) {
      _add(
        into,
        factor,
        SuggestionReasonKind.firstFormationTonight,
        0.4,
        formation: shape,
      );
    } else if (count >= 3 && count * 2 >= _otherDances.length) {
      _add(
        into,
        factor,
        SuggestionReasonKind.formationCommonTonight,
        -0.4,
        formation: shape,
        count: count,
      );
    }
  }

  /// The level the curve wants at this position, or null for none.
  double? get _curveTarget {
    if (_maxLevel <= _minLevel) return null;
    switch (_settings.curveShape) {
      case DifficultyCurveShape.off:
        return null;
      case DifficultyCurveShape.even:
        return _meanLevel;
      case DifficultyCurveShape.buildThenEase:
        // An evening of about [_nominalEvening] dances, or this one's length
        // when it is already longer: rise to the hardest level at 70% of the
        // way, then ease to the middle by the last dance.
        final planned = _plannedBefore + 1 + _plannedAfter;
        final length = planned > _nominalEvening ? planned : _nominalEvening;
        final t = _plannedBefore / (length - 1);
        final f = t <= 0.7 ? t / 0.7 : 1 - (t - 0.7) / 0.3 * 0.5;
        return _minLevel + f * (_maxLevel - _minLevel);
    }
  }

  static const int _nominalEvening = 12;

  int get _plannedAfter => Program.plannedDanceCountOf(request.slotsAfter);

  /// Difficulty curve: close to the level the chosen shape wants here.
  void _curve(Dance dance, List<SuggestionReason> into) {
    const factor = SuggestionFactor.difficultyCurve;
    if (_settings.difficultyCurve == SuggestionWeight.off) return;
    final position = _levelPositions[dance.difficultyLevelId];
    if (position == null) return;
    final target = _curveTarget;
    if (target == null) return;
    final distance = (position - target) / (_maxLevel - _minLevel);
    if (distance.abs() <= 0.25) {
      _add(into, factor, SuggestionReasonKind.fitsCurve, 0.5);
      return;
    }
    _add(
      into,
      factor,
      distance > 0
          ? SuggestionReasonKind.harderThanCurve
          : SuggestionReasonKind.easierThanCurve,
      -(2 * distance.abs()).clamp(0, 1).toDouble(),
    );
  }

  /// Recent calls at this venue: a call inside the window lowers it; a dance
  /// not called here within it is a plus.
  void _venue(
    Dance dance,
    List<SuggestionReason> into,
    List<SuggestionReason> notes,
  ) {
    const factor = SuggestionFactor.venueRecency;
    if (_settings.venueRecency == SuggestionWeight.off) return;
    if (!request.hasVenue) {
      notes.add(
        const SuggestionReason(
          SuggestionReasonKind.venueSkippedNoVenue,
          factor: factor,
        ),
      );
      return;
    }
    if (!request.calledHere.containsKey(dance.id)) {
      _add(into, factor, SuggestionReasonKind.neverCalledHere, 0.3);
      return;
    }
    final last = request.calledHere[dance.id];
    // Called here, but no call has a date: it is in no window (Q2).
    if (last == null) return;
    if (!last.isBefore(_venueCutoff)) {
      _add(
        into,
        factor,
        SuggestionReasonKind.calledHereRecently,
        -1,
        date: last,
      );
    } else {
      _add(
        into,
        factor,
        SuggestionReasonKind.notCalledHereSince,
        0.3,
        date: last,
      );
    }
  }
}
