part of '../operation.dart';

/// The containers: `modifier`, `meanwhile` and a `sequence` nested inside
/// either.
///
/// Each one holds whole figures rather than parameters, and each one is a way of
/// fitting those figures into one slot of the dance. None of them moves anyone
/// itself. What differs is how the children's effects combine. Every child is
/// run through its own [Operation.apply], so a child that reaches along the set
/// or names shadows is resolved exactly as it would be on a line of its own.
///
/// Only a top-level `sequence` is spliced away by the importer
/// (`dancedFigures`). One inside a `meanwhile` is one side of it, so it has to
/// stay together here as a [FiguresInOrder].
///
/// The progression flag sits on the container, never on a child, because the
/// container is the one slot the dance gives these figures.

/// Shared by the two containers: what the engine reads off a figure before it
/// runs, gathered from the children.
sealed class _Container extends Operation {
  const _Container(this.figures);

  /// The children, in the order the source lists them.
  final List<Operation> figures;

  @override
  int get hands4Contribution =>
      figures.fold(0, (sum, figure) => sum + figure.hands4Contribution);

  /// Every child's sets, so the engine's sizing sees a child naming shadows.
  ///
  /// The containers override [apply], so these are never used to choose a
  /// band phase for the container as a whole: each child chooses its own.
  @override
  Iterable<WhoSet?> get dancerSets => [
    for (final figure in figures) ...figure.dancerSets,
  ];

  /// The furthest any one child still has to reach.
  @override
  int reachAfter(int progressions) => figures.fold(
    0,
    (widest, figure) => math.max(widest, figure.reachAfter(progressions)),
  );

  /// Never called: [apply] runs the children instead.
  @override
  Result<Formation, OpError> perform(Formation formation) => apply(formation);

  @override
  String toString() => '$name(${figures.join(', ')})';
}

/// `modifier`, and a `sequence` nested in a container: the children danced one
/// after another.
///
/// A modifier's first child is the main figure and the later ones change how it
/// is danced: "in long lines, go forward and back **while** partner roll away",
/// or "slice left **while** partner roll away". The set ends exactly as if the
/// main figure were danced and then each modifier after it *(user-ruled
/// 2026-11-23)*. A roll away during long lines finishes with the pair swapped
/// and the lines back in place, which is what running long lines and then the
/// roll away gives.
///
/// A modifier carrying the progression carries it for its main figure, so it is
/// its own progression exactly when the main figure is: "slice left while
/// partner roll away" progresses on the slice *(user-ruled 2026-11-23)*.
///
/// The same composition serves a `sequence` inside a `meanwhile`, which
/// `compendium_core` defines as figures danced one after another. A sequence
/// has no main figure, so it is its own progression if any child is: a slide
/// anywhere in it carries the dancers on *(agent's call)*.
///
/// **Known limit.** A flagged modifier is progressed as one figure: the
/// change-over runs after the last modifier, and whether to hold is judged on the
/// state the modifiers leave, not on the main figure's. Splitting the flag's
/// effects at the main figure would need the engine to see inside the
/// container. No importer writes a modifier whose modifiers reach another
/// hands four, where the two readings would differ most.
final class FiguresInOrder extends _Container {
  const FiguresInOrder(super.figures, {required this.name})
    : assert(name == 'modifier' || name == 'sequence');

  @override
  final String name;

  bool get _isModifier => name == 'modifier';

  @override
  bool get progressionEligible => _isModifier
      ? figures.first.progressionEligible
      : figures.any((figure) => figure.progressionEligible);

  @override
  bool get isItsOwnProgression => _isModifier
      ? figures.first.isItsOwnProgression
      : figures.any((figure) => figure.isItsOwnProgression);

  /// A modifier spends what its main figure spends; a sequence, the most any
  /// one child spends, as [isItsOwnProgression] reads any child.
  @override
  int get progressionsSpent => _isModifier
      ? figures.first.progressionsSpent
      : figures.map((figure) => figure.progressionsSpent).reduce(math.max);

  /// The main figure's warnings, read from the state it starts in.
  ///
  /// The later children start from states that only exist part-way through, so
  /// they are not linted. *(Agent's call: the alternative was running the
  /// children here to lint each one, which would make lint depend on a
  /// transform succeeding.)*
  @override
  Iterable<Warning> lint(Formation formation) => figures.first.lint(formation);

  @override
  Result<Formation, OpError> apply(
    Formation formation, {
    int progressions = 0,
  }) {
    Result<Formation, OpError> state = Ok(formation);
    for (final figure in figures) {
      state = state.flatMap(
        (current) => figure.apply(current, progressions: progressions),
      );
    }
    return state;
  }

  @override
  bool operator ==(Object other) =>
      other is FiguresInOrder &&
      other.name == name &&
      _sameFigures(other.figures, figures);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(figures));
}

/// `meanwhile` — two or more figures danced at the same time by different
/// dancers: "women allemande left 1½ **||** men orbit clockwise ½".
///
/// The set ends as if each part were danced on its own *(user-ruled
/// 2026-11-23)*, and that is done literally: every part is danced from the
/// same starting state, and each dancer ends where the part that moved them
/// put them. Running the parts one after another instead would let one part
/// see what another left behind (a wave an allemande ¾ formed would be settled
/// by the next part, which then appears to move those dancers), so the result
/// would depend on the order the parts are written in.
///
/// Two parts that move the same dancer are refused rather than guessed at:
/// two figures cannot both be danced by the same person at once. So are parts
/// that would put two dancers in one cell.
///
/// "Moved" means ended in a different cell *(agent's call)*. Facing is left
/// out because several figures set the facing of their whole hands four (a
/// shoulder round by the women re-faces the men beside them), and facing is
/// not part of what a dance is checked against. A dancer no part moves keeps
/// the facing the last part to change it gave them. **Known limit:** a part
/// whose dancers end in the cells they began in (an allemande once around) is
/// not seen to move anyone, so a dancer named in it and in another part is not
/// caught. Telling who *dances* a part, rather than who it moves, would need
/// each figure to report its dancers, which none does yet.
///
/// It is its own progression if any part is, since a part that carries dancers
/// on to the next couple does so whatever the others do *(agent's call)*.
///
/// A [Shift] part is the exception to "from the same starting state": the
/// shifting dancers step around the others, so it is danced after the other
/// parts are merged, from where they leave the set *(agent's call,
/// 2026-11-25)*. Danced from the start instead, the men of Mary Cay's Reel
/// would be refused for stepping where the women's allemande begins.
final class Meanwhile extends _Container {
  const Meanwhile(super.figures);

  @override
  String get name => 'meanwhile';

  @override
  bool get progressionEligible =>
      figures.any((figure) => figure.progressionEligible);

  @override
  bool get isItsOwnProgression =>
      figures.any((figure) => figure.isItsOwnProgression);

  /// The most any one part spends, as [isItsOwnProgression] reads any part.
  @override
  int get progressionsSpent =>
      figures.map((figure) => figure.progressionsSpent).reduce(math.max);

  /// Every part starts from the same state, so every part is linted on it.
  @override
  Iterable<Warning> lint(Formation formation) => [
    for (final figure in figures) ...figure.lint(formation),
  ];

  @override
  Result<Formation, OpError> apply(
    Formation formation, {
    int progressions = 0,
  }) {
    // Settle any wave offsets once, up front, so every part starts from the
    // same cells and none is blamed for dancers that settling moved.
    final start = figures.every((figure) => figure.preservesWaveOffsets)
        ? formation
        : normalizeWaveOffsets(formation);
    final movedBy = <DancerId, String>{};
    final updates = <DancerId, DancerState>{};
    final refaced = <DancerId, DancerState>{};
    // Shadows a part remembers (`DancerState.shadow`). Kept apart from the
    // moves, because state equality leaves the memory out: a part that
    // remembers a shadow but leaves the dancer where and as they were looks
    // unchanged, and a later part's refacing would overwrite it.
    final remembered = <DancerId, DancerId>{};
    final shifts = [
      for (final figure in figures)
        if (figure is Shift) figure,
    ];
    for (final figure in figures) {
      if (figure is Shift) continue;
      final result = figure.apply(start, progressions: progressions);
      final Formation danced;
      switch (result) {
        case Err():
          return result;
        case Ok(:final value):
          danced = value;
      }
      for (final entry in start.dancers.entries) {
        final now = danced[entry.key];
        final shadow = now?.shadow;
        if (shadow != null && entry.value.shadow == null) {
          remembered.putIfAbsent(entry.key, () => shadow);
        }
        if (now == null || now == entry.value) continue;
        if (now.position == entry.value.position) {
          refaced[entry.key] = now;
          continue;
        }
        final earlier = movedBy[entry.key];
        if (earlier != null) {
          return Err<Formation, OpError>(
            OpError(
              ErrorKind.unresolvableDancerSet,
              'meanwhile: ${figure.name} and $earlier both move '
              '${entry.key}; the parts of a meanwhile are danced by different '
              'dancers',
            ),
          );
        }
        movedBy[entry.key] = figure.name;
        updates[entry.key] = now;
      }
    }
    final merged = {...refaced, ...updates};
    final occupied = <Position, DancerId>{};
    for (final entry in start.dancers.entries) {
      final state = merged[entry.key] ?? entry.value;
      final other = occupied[state.position];
      if (other != null) {
        return Err<Formation, OpError>(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'meanwhile: the parts would put $other and ${entry.key} both at '
            '${state.position}',
          ),
        );
      }
      occupied[state.position] = entry.key;
    }
    final danced = start.withUpdates({
      ...merged,
      for (final MapEntry(key: id, value: shadow) in remembered.entries)
        id: (merged[id] ?? start.stateOf(id)).copyWith(shadow: shadow),
    });
    // A shift travels around the parts danced beside it: it steps from where
    // the others have left the set (agent's call, 2026-11-25).
    var shifted = danced;
    for (final shift in shifts) {
      switch (shift.apply(shifted, progressions: progressions)) {
        case Err() && final error:
          return error;
        case Ok(:final value):
          shifted = value;
      }
    }
    return Ok(shifted);
  }

  @override
  bool operator ==(Object other) =>
      other is Meanwhile && _sameFigures(other.figures, figures);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(figures));
}

bool _sameFigures(List<Operation> a, List<Operation> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
