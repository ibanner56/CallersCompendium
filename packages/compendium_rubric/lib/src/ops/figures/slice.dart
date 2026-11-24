part of '../operation.dart';

/// How far a `slice` shifts: a whole couple or a single dancer.
enum SliceBy {
  couple('couple'),
  dancer('dancer');

  const SliceBy(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static SliceBy? fromKey(String key) {
    for (final value in SliceBy.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// How the dancers come back after stepping in on the diagonal.
enum SliceReturn {
  straight('straight'),
  diagonal('diagonal'),
  none('none');

  const SliceReturn(this.key);

  /// The value as it appears in the external JSON.
  final String key;

  static SliceReturn? fromKey(String key) {
    for (final value in SliceReturn.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// `slice` — the Becket shift: couples step in on a diagonal toward the next
/// couple and fall back to the side, which moves everyone along the set.
///
/// **User-ruled (2026-11-22):** a slice lands exactly like a
/// [SlideAlongSet] in the same direction. The `return` decides how far:
/// falling back **straight** across shifts one couple (one slide), and falling
/// back on the **diagonal** shifts two (two slides). So the slide's whole
/// mechanic — the counter-rotating lines, rounding the ends, and re-banding —
/// is reused rather than restated here.
///
/// Like the slide, the slice **is** the progression when it carries the flag:
/// its own displacement is the movement that hands each couple on.
///
/// **A flagged diagonal slice is two progressions** *(user-ruled 2026-11-23:
/// "diagonal is double, straight back is single")*. It is danced as two
/// flagged slides, each with its own change-over ([progressionSteps]), so a
/// double-progression dance can progress on it. The Caller's Box bridge still
/// does not assume one on a Becket opener (`assumedProgressionIndex`, agent's
/// call): single-progression dances open with one too. Inside a container
/// (`modifier`, `meanwhile` or a nested `sequence`) it is a known limit: a
/// flag there counts two progressions (the container reads its children's
/// `progressionsSpent`) but the container is one step, so only one
/// change-over runs. 20 of the 21 Caller's Box double slices import as a
/// `slice`: those written "go forward to S1, fall back to S2" and, since
/// 2026-11-24, those that go forward to a neighbour and back to the next. 5 of
/// them open a dance (`taxonomy.md`, `slice`).
///
/// **Deferred:** `by: dancer` (a shift of a single dancer, which leaves a shape
/// the slide does not model) and `return: none` (the couples stop in the
/// middle, facing the couple on the diagonal rather than standing on the side).
final class Slice extends Operation {
  const Slice({
    this.slice = SlideDirection.left,
    this.by = SliceBy.couple,
    this.back = SliceReturn.straight,
  });

  /// Which diagonal the couples step in on, and so which way the set shifts.
  final SlideDirection slice;

  /// Whether a whole couple or a single dancer shifts.
  final SliceBy by;

  /// How the dancers come back: straight (one couple along), diagonal (two),
  /// or not at all. Named `back` because `return` is reserved in Dart.
  final SliceReturn back;

  @override
  String get name => 'slice';

  /// Each slide reaches one grouping on, and a diagonal return slides twice.
  @override
  int get hands4Contribution => back == SliceReturn.diagonal ? 2 : 1;

  @override
  bool get progressionEligible => true;

  /// See [SlideAlongSet.isItsOwnProgression]: the shift is the progression.
  @override
  bool get isItsOwnProgression => true;

  SlideAlongSet get _slide => SlideAlongSet(slide: slice);

  /// A diagonal return is two slides, and flagged it is two progressions
  /// *(user-ruled 2026-11-23)*. The deferred shapes stay one step, so a flag
  /// on them still refuses with their own error.
  @override
  List<Operation> get progressionSteps =>
      back == SliceReturn.diagonal && by == SliceBy.couple
      ? [_slide, _slide]
      : [this];

  @override
  OpError? checkPreconditions(Formation formation) {
    if (by == SliceBy.dancer) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'slice by:dancer shifts a single dancer, which is half the step a '
        'slide along the set models; it is deferred until a worked example '
        'pins where that leaves the set',
      );
    }
    if (back == SliceReturn.none) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'slice return:none leaves the couples in the middle of the set facing '
        'the couple on the diagonal rather than back on the sides; it is '
        'deferred until a worked example pins that landing',
      );
    }
    return _slide.checkPreconditions(formation);
  }

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final once = _slide.perform(formation);
    if (back != SliceReturn.diagonal) return once;
    return once.flatMap((shifted) {
      final failure = _slide.checkPreconditions(shifted);
      return failure == null ? _slide.perform(shifted) : Err(failure);
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Slice &&
      other.slice == slice &&
      other.by == by &&
      other.back == back;

  @override
  int get hashCode => Object.hash(name, slice, by, back);

  @override
  String toString() => 'slice(${slice.key}, ${by.key}, ${back.key})';
}
