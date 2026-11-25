part of '../operation.dart';

/// `shift` (taxonomy v40) — one named group sidesteps one place while the
/// others stand or dance something else, as in Caller's Box's "Women
/// allemande right 3/4 || Men shift left" (Mary Cay's Reel, 10579).
///
/// `left` and `right` are the dancer's own: a dancer facing across the set
/// steps one row along it, as a [SlideAlongSet] moves them. `up` and `down`
/// are one row toward the top or the bottom of the hall.
final class Shift extends Operation {
  const Shift({this.who = WhoSet.role1s, this.direction = 'left'});

  /// Which dancers shift.
  final WhoSet who;

  /// `left`, `right`, `up` or `down`.
  final String direction;

  @override
  String get name => 'shift';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  /// A shift steps into the next hands four along, as a slide does.
  @override
  int get hands4Contribution => 1;

  /// Only the shifting dancers move, so a wave the others stand in is kept:
  /// a meanwhile's other part has usually just formed it.
  @override
  bool get preservesWaveOffsets => true;

  /// The row step for [state], or null when this shift has no reading for it.
  int? _rowStep(DancerState state) => switch (direction) {
    'up' => -1,
    'down' => 1,
    'left' when state.facing == Facing.acrossEast => -1,
    'left' when state.facing == Facing.acrossWest => 1,
    'right' when state.facing == Facing.acrossEast => 1,
    'right' when state.facing == Facing.acrossWest => -1,
    _ => null,
  };

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      danceTogether(formation, [this]);

  /// Where each of this shift's dancers would step, before fuzzy travel.
  Result<Map<DancerId, DancerState>, OpError> _steps(Formation formation) {
    final steps = <DancerId, DancerState>{};
    for (final entry in formation.dancers.entries) {
      if (!whoIncludes(formation, entry.key, who)) continue;
      final state = entry.value;
      // Out at an end, a dancer has no line to shift along (agent's call).
      if (state.waitingOut) continue;
      final step = _rowStep(state);
      if (step == null) {
        return Err(
          OpError(
            ErrorKind.unsupportedParam,
            'a shift $direction by ${entry.key} facing '
            '${state.facing.label} is deferred',
          ),
        );
      }
      steps[entry.key] = state.copyWith(
        position: Position(state.row + step, state.col),
      );
    }
    return Ok(steps);
  }

  /// [shifts] danced at once, as the shift parts of one `meanwhile` are: every
  /// step is gathered first and fuzzy travel settles them together, so the
  /// result does not depend on the order the parts are written in. A dancer
  /// two of them name is refused, as two parts of a meanwhile moving one
  /// dancer are.
  static Result<Formation, OpError> danceTogether(
    Formation formation,
    List<Shift> shifts,
  ) {
    final steps = <DancerId, DancerState>{};
    for (final shift in shifts) {
      switch (shift._steps(formation)) {
        case Err(:final error):
          return Err(error);
        case Ok(:final value):
          for (final MapEntry(key: id, value: state) in value.entries) {
            if (steps.containsKey(id)) {
              return Err(
                OpError(
                  ErrorKind.unresolvableDancerSet,
                  'meanwhile: two shifts both move $id; the parts of a '
                  'meanwhile are danced by different dancers',
                ),
              );
            }
            steps[id] = state;
          }
      }
    }
    // Fuzzy travel: a shift is a step toward the next place, not a claim on a
    // cell, so a dancer whose place is taken, or who would step off an end of
    // the set, goes no further than there is room for and stays where they
    // are (user-asked 2026-11-24, that shifting dancers must not run into
    // each other; staying put is the agent's call, 2026-11-25).
    steps.removeWhere(
      (_, state) => state.row < 0 || state.row > formation.lastRow,
    );
    while (true) {
      _stopBlocked(formation, steps);
      final shifted = formation.withUpdates(steps);
      if (_settles(shifted)) return Ok(shifted);
      // A wave the shifters stand beside settles into the side columns before
      // the next figure, and must find its cells free. A shifter who landed
      // in a row with a dancer off the side columns stays where they are.
      final stopped = [
        for (final MapEntry(key: id, value: state) in steps.entries)
          if (shifted
              .dancersInRow(state.row)
              .any((other) => !shifted.stateOf(other).position.isSideColumn))
            id,
      ];
      if (stopped.isEmpty) {
        return Err(
          OpError(
            ErrorKind.unresolvableDancerSet,
            'shift: the wave beside the shifting dancers could not settle '
            'into the side lines afterwards',
          ),
        );
      }
      stopped.forEach(steps.remove);
    }
  }

  /// Drops every step into a cell someone stays in, or that two steps claim,
  /// until none is left: two shifting into one cell both stay, so the result
  /// does not depend on who is looked at first, and a dancer who stays keeps
  /// their cell and may block another.
  static void _stopBlocked(
    Formation formation,
    Map<DancerId, DancerState> steps,
  ) {
    var blocked = true;
    while (blocked) {
      final staying = <Position>{
        for (final entry in formation.dancers.entries)
          if (!steps.containsKey(entry.key)) entry.value.position,
      };
      final claims = <Position, int>{};
      for (final state in steps.values) {
        claims.update(state.position, (n) => n + 1, ifAbsent: () => 1);
      }
      final stopped = [
        for (final entry in steps.entries)
          if (staying.contains(entry.value.position) ||
              claims[entry.value.position]! > 1)
            entry.key,
      ];
      stopped.forEach(steps.remove);
      blocked = stopped.isNotEmpty;
    }
  }

  /// Whether the wave offsets of [formation] settle without two dancers
  /// meeting in one cell, as the next figure will settle them (§8.5.4).
  static bool _settles(Formation formation) {
    try {
      normalizeWaveOffsets(formation);
      normalizeWaveOffsets(formation, alsoOutsideBands: true);
      return true;
    } on FormationProjectionError {
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Shift && other.who == who && other.direction == direction;

  @override
  int get hashCode => Object.hash(name, who, direction);

  @override
  String toString() => 'shift(${who.key}, $direction)';
}
