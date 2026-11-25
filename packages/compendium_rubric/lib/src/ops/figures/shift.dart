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
  Result<Formation, OpError> perform(Formation formation) {
    final changes = <DancerId, DancerState>{};
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
      final row = state.row + step;
      if (row < 0 || row > formation.lastRow) continue;
      changes[entry.key] = state.copyWith(position: Position(row, state.col));
    }
    // Fuzzy travel: a shift is a step toward the next place, not a claim on a
    // cell, so a dancer whose place is taken goes no further than there is
    // room for and stays where they are (user-asked 2026-11-24, that shifting
    // dancers must not run into each other; staying put is the agent's call,
    // 2026-11-25). Two shifting toward one cell both stay, so the result does
    // not depend on who is looked at first, and a dancer who stays keeps their
    // cell and may block another, so this repeats until nothing changes.
    var blocked = true;
    while (blocked) {
      final staying = <Position>{
        for (final entry in formation.dancers.entries)
          if (!changes.containsKey(entry.key)) entry.value.position,
      };
      final claims = <Position, int>{};
      for (final state in changes.values) {
        claims.update(state.position, (n) => n + 1, ifAbsent: () => 1);
      }
      final stopped = [
        for (final entry in changes.entries)
          if (staying.contains(entry.value.position) ||
              claims[entry.value.position]! > 1)
            entry.key,
      ];
      stopped.forEach(changes.remove);
      blocked = stopped.isNotEmpty;
    }
    return Ok(formation.withUpdates(changes));
  }

  @override
  bool operator ==(Object other) =>
      other is Shift && other.who == who && other.direction == direction;

  @override
  int get hashCode => Object.hash(name, who, direction);

  @override
  String toString() => 'shift(${who.key}, $direction)';
}
