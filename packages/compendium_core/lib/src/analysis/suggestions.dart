/// Suggest the next dance (#2343): ranks candidate dances for one position in
/// a program and says why, factor by factor.
///
/// Pure and Flutter-free. The app runs [rankSuggestions] off the UI thread over
/// the builder picker's current results. The factors, their effects and the
/// shipped weights are described in `docs/design/suggestions.md`.
///
/// The position is given as the program's slots before it and after it: the
/// builder ranks for the end with every slot before and none after, for an
/// add before or after a slot with the slots on either side of the new dance,
/// and for **Replace…** with the slots on either side of the slot being
/// replaced, which is in neither (#2344). One scorer serves every position.
///
/// Ranking only reorders. Every candidate comes back, once.
library;

import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/difficulty_level.dart';
import '../model/enums.dart';
import '../model/event_rule.dart';
import '../model/figure.dart' show Figure, customMove;
import '../model/figure_source.dart';
import '../model/formation.dart';
import '../model/phrase_structure.dart';
import '../model/program.dart';
import '../search/collection_search_state.dart' show calendarMonthsBefore;
import '../taxonomy/taxonomy.dart';
import '../taxonomy/user_figure_use.dart';
import 'matrix_column_config.dart';
import 'program_matrix.dart';
import 'suggestion_settings.dart';
import 'suggestion_worker.dart' show SuggestionWorker;

/// Which side of the position a neighbour is on.
enum SuggestionNeighbor { previous, next }

/// Why a candidate moved, or a note about its ranking. The app turns each kind
/// into a sentence.
enum SuggestionReasonKind {
  /// [SuggestionReason.count] moves no other dance in the program uses.
  newMoves,

  /// The move [SuggestionReason.moveKey] (a matrix column key) overlaps the
  /// beats of the neighbour [SuggestionReason.neighborDanceId], on the
  /// [SuggestionReason.neighbor] side, by the matrix's exact-beat alert rule;
  /// with [SuggestionReason.count] colliding moves in all.
  beatOverlap,

  /// As [beatOverlap], under the matrix's phrase rule ("Flag exact beat overlap
  /// only" off): the move starts in the same phrase as in the neighbour.
  phraseOverlap,

  /// The dance is already in this program. Not a factor: such a dance is not
  /// scored, and is listed after every other dance, whatever its form.
  alreadyInProgram,

  /// Same formation family as the neighbour
  /// [SuggestionReason.neighborDanceId], on the [SuggestionReason.neighbor]
  /// side.
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
    this.neighborDanceId,
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

  /// The neighbour a [SuggestionReasonKind.beatOverlap],
  /// [SuggestionReasonKind.phraseOverlap] or
  /// [SuggestionReasonKind.sameFormationAsNeighbor] reason compares with: the
  /// first such dance on the [neighbor] side (one of several when that side is
  /// a group of alternates), so the reason can name it (#2344).
  final String? neighborDanceId;
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
      other.neighborDanceId == neighborDanceId &&
      other.date == date;

  @override
  int get hashCode => Object.hash(
    kind,
    factor,
    effect,
    count,
    moveKey,
    formation,
    neighbor,
    neighborDanceId,
  );

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
    this.wouldBreak = const [],
  });

  final String danceId;
  final double score;

  /// False for a dance listed after the ranked ones, unranked: an English
  /// dance, or one already in the program.
  final bool ranked;

  /// Every reason, the ones that moved it first, largest effect first; notes
  /// last. Never empty.
  final List<SuggestionReason> reasons;

  /// The program's applied event rules this dance would break where it is
  /// suggested for, in the order the program applies them (#2345). Empty
  /// from [rankSuggestions]; [markRuleBreakingSuggestions] fills it, and
  /// lists every dance with any after every dance with none. Not a factor:
  /// it never changes [score].
  final List<EventRule> wouldBreak;

  /// This suggestion, marked as breaking [rules] ([wouldBreak]).
  RankedSuggestion withWouldBreak(List<EventRule> rules) => RankedSuggestion(
    danceId: danceId,
    score: score,
    ranked: ranked,
    reasons: reasons,
    wouldBreak: List.unmodifiable(rules),
  );

  /// The reasons a row shows: the top one or two that moved it, or its first
  /// note when nothing did.
  List<SuggestionReason> get headline {
    final moved = reasons.where((r) => r.moved).take(2).toList();
    return moved.isNotEmpty ? moved : [reasons.first];
  }
}

/// The parts of a dance the scorer reads, and nothing else: what crosses to
/// the ranking isolate for each candidate and program dance, instead of a
/// whole [Dance] with its notes, tunes, custom fields and other text.
@immutable
class SuggestionCandidate {
  const SuggestionCandidate({
    required this.id,
    this.form = DanceForm.contra,
    this.formation = const Formation(FormationShape.dupleImproper),
    this.difficultyLevelId,
    this.phraseStructure = PhraseStructure.standard,
    this.figures = const [],
    this.revision = 0,
  });

  /// The projection of [dance]. A transcription that cannot be decoded has no
  /// figures here, as the matrix reads it.
  ///
  /// Its [revision] changes whenever anything the scorer reads may have
  /// changed, even where a bulk path stamps `updatedAt` at whole seconds and
  /// an edit keeps the same stamp: it hashes `updatedAt`, the form, formation,
  /// level and phrase structure, and the identity of the dance's figure list.
  /// A [Dance] is immutable, so changed figures are always a new list. The
  /// identity costs nothing to read, where hashing every figure's content
  /// cost about 40 ms per rank for 20,000 dances; its price is that the same
  /// figures loaded again (a reload of the collection) count as changed, and
  /// are sent to a [SuggestionWorker] again.
  factory SuggestionCandidate.fromDance(Dance dance) {
    final figures = switch (dance.figuresSource) {
      DecodedFigures(:final figures) => figures,
      UnreadableFigures() => const <Figure>[],
    };
    return SuggestionCandidate(
      id: dance.id,
      form: dance.form,
      formation: dance.formation,
      difficultyLevelId: dance.difficultyLevelId,
      phraseStructure: dance.phraseStructure,
      figures: figures,
      revision: Object.hash(
        dance.updatedAt.microsecondsSinceEpoch,
        dance.form,
        dance.formation,
        dance.difficultyLevelId,
        dance.phraseStructure,
        identityHashCode(dance.figuresSource),
      ),
    );
  }

  final String id;
  final DanceForm form;
  final Formation formation;
  final String? difficultyLevelId;
  final PhraseStructure phraseStructure;
  final List<Figure> figures;

  /// Which version of the dance this is: from [fromDance], a fingerprint of
  /// its `updatedAt`, its projected fields and its figure list's identity. A [SuggestionWorker] already
  /// holding this id at this revision is not sent it again.
  final int revision;
}

/// Where in a program a dance would go: the slots before and after it, and
/// whether it takes an alternate's place. The three ways the builder asks for
/// suggestions (#2343, #2344) each make one, so the split is worked out in one
/// place and a later host (#2348) can reuse it.
@immutable
class SuggestionPosition {
  const SuggestionPosition({
    required this.slotsBefore,
    this.slotsAfter = const [],
    this.isAlternate = false,
    this.replaced,
  });

  /// After every slot: adding at the end of the program.
  factory SuggestionPosition.atEnd(List<ProgramSlot> slots) =>
      SuggestionPosition(slotsBefore: List.unmodifiable(slots));

  /// Where a dance added before ([after] false) or after ([after] true) the
  /// alternate group holding the slot at [index] lands, by the rule the
  /// builder adds it with ([Program.insertSlotAtGroupBoundary], #2339):
  /// before the group's primary or after its last alternate, as a primary. A
  /// leading run of orphaned alternates that the add would promote is given
  /// as promoted.
  factory SuggestionPosition.inserting(
    List<ProgramSlot> slots,
    int index, {
    required bool after,
  }) {
    const placeholderId = '\u0000suggestion-position';
    final inserted = Program.insertSlotAtGroupBoundary(
      slots,
      index,
      ProgramSlot(id: placeholderId, position: 0, danceId: placeholderId),
      after: after,
    );
    final at = inserted.indexWhere((slot) => slot.id == placeholderId);
    return SuggestionPosition(
      slotsBefore: List.unmodifiable(inserted.sublist(0, at)),
      slotsAfter: List.unmodifiable(inserted.sublist(at + 1)),
    );
  }

  /// The place of the slot at [index], for **Replace…**: every other slot,
  /// on its side. The slot itself is in neither list, so its current dance is
  /// not a neighbour of the candidates and does not count as already in the
  /// program (unless another slot holds it): replacing a dance with itself
  /// changes nothing the caller cannot see.
  factory SuggestionPosition.replacing(List<ProgramSlot> slots, int index) {
    RangeError.checkValidIndex(index, slots, 'index');
    return SuggestionPosition(
      slotsBefore: List.unmodifiable(slots.sublist(0, index)),
      slotsAfter: List.unmodifiable(slots.sublist(index + 1)),
      isAlternate: slots[index].isAlt,
      replaced: slots[index],
    );
  }

  /// See [SuggestionRequest.slotsBefore].
  final List<ProgramSlot> slotsBefore;

  /// See [SuggestionRequest.slotsAfter].
  final List<ProgramSlot> slotsAfter;

  /// See [SuggestionRequest.candidateIsAlternate].
  final bool isAlternate;

  /// The slot the chosen dance replaces ([SuggestionPosition.replacing]), in
  /// neither [slotsBefore] nor [slotsAfter]; null for an add. The ranking
  /// never reads it; checking a candidate against the program's event rules
  /// (#2345) does, to tell a rule the program meets now from one it already
  /// breaks.
  final ProgramSlot? replaced;

  @override
  bool operator ==(Object other) =>
      other is SuggestionPosition &&
      other.isAlternate == isAlternate &&
      other.replaced == replaced &&
      _sameSlots(other.slotsBefore, slotsBefore) &&
      _sameSlots(other.slotsAfter, slotsAfter);

  @override
  int get hashCode => Object.hash(
    isAlternate,
    replaced,
    Object.hashAll(slotsBefore),
    Object.hashAll(slotsAfter),
  );

  static bool _sameSlots(List<ProgramSlot> a, List<ProgramSlot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Everything [rankSuggestions] reads. Plain data, and only what the scorer
/// needs ([SuggestionCandidate]), so it is cheap to send to another isolate.
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
    this.candidateIsAlternate = false,
  });

  /// The program's slots before the position, in order (every slot, for the
  /// end of the program). For **Replace…**, the slots before the one being
  /// replaced.
  final List<ProgramSlot> slotsBefore;

  /// The program's slots after the position (none, for the end). For
  /// **Replace…**, the slots after the one being replaced: that slot is in
  /// neither list, so its current dance is not compared with, and is not
  /// "already in this program" unless another slot holds it.
  final List<ProgramSlot> slotsAfter;

  /// Whether the candidate takes an alternate's place ([ProgramSlot.isAlt]):
  /// true only for **Replace…** on an alternate. The candidate then belongs
  /// to the alternate group that ends [slotsBefore], so that group's dances
  /// are alternatives to it, not neighbours, as in the matrix; and the curve
  /// reads that group's place in the evening. A new dance added before or
  /// after a slot is always a primary (`Program.insertSlotAtGroupBoundary`).
  final bool candidateIsAlternate;

  /// The dances the slots refer to, by id. A slot whose dance is missing reads
  /// as a dance with no figures, as the matrix shows a deleted one.
  final Map<String, SuggestionCandidate> programDances;

  /// The dances to rank, in the plain order they are shown in. Ties keep it.
  /// A candidate already in the program is kept, listed last
  /// ([SuggestionReasonKind.alreadyInProgram]): ranking never filters.
  final List<SuggestionCandidate> candidates;

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

  /// This request with [candidates] in place of its own.
  SuggestionRequest withCandidates(List<SuggestionCandidate> candidates) =>
      SuggestionRequest(
        slotsBefore: slotsBefore,
        slotsAfter: slotsAfter,
        programDances: programDances,
        candidates: candidates,
        settings: settings,
        today: today,
        collisionMode: collisionMode,
        taxonomy: taxonomy,
        matrixConfig: matrixConfig,
        userFigures: userFigures,
        levels: levels,
        hasVenue: hasVenue,
        calledHere: calledHere,
        candidateIsAlternate: candidateIsAlternate,
      );
}

/// The result: every candidate once, ranked ones first (best first), then the
/// unranked ones in their plain order.
@immutable
class SuggestionRanking {
  const SuggestionRanking(this.order);

  final List<RankedSuggestion> order;
}

/// The effect, and the score, of [SuggestionReasonKind.alreadyInProgram]:
/// below anything the factors can give (every factor at A lot gives at most
/// +5.4 or −12 in all), so the reason reads as lowering the dance. The order
/// does not depend on it: such dances are listed last whatever their score.
const double alreadyInProgramEffect = -20;

/// A formation family: Becket clockwise and counter-clockwise are one.
String _formationFamily(FormationShape shape) => switch (shape) {
  FormationShape.becketCw || FormationShape.becketCcw => 'becket',
  _ => shape.name,
};

/// Ranks [request]'s candidates. See the library comment.
///
/// The order: the ranked dances, best first; then English dances not in the
/// program; then every dance already in the program, whatever its form. The
/// last two groups keep the plain order.
SuggestionRanking rankSuggestions(SuggestionRequest request) {
  final scorer = _Scorer(request);
  final ranked = <(int, RankedSuggestion)>[];
  final unranked = <RankedSuggestion>[];
  final inProgram = <RankedSuggestion>[];
  for (var i = 0; i < request.candidates.length; i++) {
    final dance = request.candidates[i];
    if (scorer.isInProgram(dance.id)) {
      inProgram.add(
        RankedSuggestion(
          danceId: dance.id,
          score: alreadyInProgramEffect,
          ranked: false,
          reasons: const [
            SuggestionReason(
              SuggestionReasonKind.alreadyInProgram,
              effect: alreadyInProgramEffect,
            ),
          ],
        ),
      );
      continue;
    }
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
  return SuggestionRanking([
    for (final (_, r) in ranked) r,
    ...unranked,
    ...inProgram,
  ]);
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
        isAlt: request.candidateIsAlternate,
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
      _programDanceIds.add(danceId);
      final dance = request.programDances[danceId];
      final row = buildMatrixRowFromFigures(
        danceId: danceId,
        figures: dance?.figures ?? const [],
        phraseStructure: dance?.phraseStructure ?? PhraseStructure.standard,
        formation:
            dance?.formation ?? const Formation(FormationShape.dupleImproper),
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
        () => (neighbor, probe.rows[r].danceId),
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
    // The curve reads the candidate's place in the evening: the planned
    // dances before its alternate group (for an alternate, before its
    // primary), and the evening's length counting it only when it is itself
    // a planned dance.
    var groupStart = candidateSlot;
    while (groupStart > 0 && groups[groupStart - 1] == _candidateGroup) {
      groupStart--;
    }
    _plannedBefore = Program.plannedDanceCountOf(slots.take(groupStart));
    _plannedLength =
        Program.plannedDanceCountOf(request.slotsBefore) +
        Program.plannedDanceCountOf(request.slotsAfter) +
        (slots[candidateSlot].isPlannedDance ? 1 : 0);
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
  final _otherDances = <SuggestionCandidate?>[];

  /// Every dance id the program's slots hold, before and after the position.
  final _programDanceIds = <String>{};

  /// Whether a slot of the program, before or after the position, holds
  /// [danceId].
  bool isInProgram(String danceId) => _programDanceIds.contains(danceId);
  final _programMoves = <String>{};
  final _formationCounts = <String, int>{};
  final _neighborFamilies = <String, (SuggestionNeighbor, String)>{};
  int _candidateRow = 0;
  int? _candidateSection;
  int? _candidateGroup;
  late final Map<String, int> _levelPositions;
  int _minLevel = 0;
  int _maxLevel = 0;
  int _plannedBefore = 0;
  int _plannedLength = 1;
  double? _meanLevel;
  late final DateTime _venueCutoff;

  RankedSuggestion score(SuggestionCandidate dance) {
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
    String? neighborDanceId,
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
        neighborDanceId: neighborDanceId,
        date: date,
      ),
    );
  }

  /// Variety on the matrix: moves no other dance uses raise it; a move that
  /// overlaps a neighbour's beats, under the matrix's own alert rule, lowers
  /// it.
  void _variety(SuggestionCandidate dance, List<SuggestionReason> into) {
    const factor = SuggestionFactor.matrixVariety;
    if (_settings.matrixVariety == SuggestionWeight.off) return;
    if (_otherDances.isEmpty) return;
    final row = buildMatrixRowFromFigures(
      danceId: dance.id,
      figures: dance.figures,
      phraseStructure: dance.phraseStructure,
      formation: dance.formation,
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
    // Each colliding move, with the first neighbour it collides with, in
    // [ProgramMatrix.neighborRowIndices] order: the side before, then the
    // side after, nearest row first.
    final colliding = <String, int>{};
    for (final key in row.beatSpansByMove.keys) {
      final first = matrix
          .collidingNeighborRowIndices(_candidateRow, key)
          .firstOrNull;
      if (first != null) colliding[key] = first;
    }
    if (colliding.isNotEmpty) {
      final first = colliding.entries.first;
      _add(
        into,
        factor,
        request.collisionMode == MatrixCollisionMode.phrase
            ? SuggestionReasonKind.phraseOverlap
            : SuggestionReasonKind.beatOverlap,
        -(0.6 * colliding.length).clamp(0, 1).toDouble(),
        count: colliding.length,
        moveKey: first.key,
        neighbor: first.value < _candidateRow
            ? SuggestionNeighbor.previous
            : SuggestionNeighbor.next,
        neighborDanceId: matrix.rows[first.value].danceId,
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
  void _formation(SuggestionCandidate dance, List<SuggestionReason> into) {
    const factor = SuggestionFactor.formationBalance;
    if (_settings.formationBalance == SuggestionWeight.off) return;
    if (_otherDances.isEmpty) return;
    final shape = dance.formation.shape;
    final family = _formationFamily(shape);
    if (_neighborFamilies[family] case (final side, final danceId)) {
      _add(
        into,
        factor,
        SuggestionReasonKind.sameFormationAsNeighbor,
        -0.6,
        formation: shape,
        neighbor: side,
        neighborDanceId: danceId,
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
        final planned = _plannedLength;
        final length = planned > _nominalEvening ? planned : _nominalEvening;
        final t = _plannedBefore / (length - 1);
        final f = t <= 0.7 ? t / 0.7 : 1 - (t - 0.7) / 0.3 * 0.5;
        return _minLevel + f * (_maxLevel - _minLevel);
    }
  }

  static const int _nominalEvening = 12;

  /// Difficulty curve: close to the level the chosen shape wants here.
  void _curve(SuggestionCandidate dance, List<SuggestionReason> into) {
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
    SuggestionCandidate dance,
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
      // [calledHere] leaves this program out, so a dance already in it would
      // read as never called here; such a dance is never scored
      // ([rankSuggestions]).
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
