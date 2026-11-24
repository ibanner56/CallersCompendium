part of '../operation.dart';

/// `arch_and_dive` — one couple raises an arch, the couple facing them ducks
/// under it, and the two couples trade places along the set.
///
/// **User-ruled:** the effect is the unconditional row swap of every hands
/// four, `(r0,c) ↔ (r1,c)` — the one place the prior verifier's reading
/// governs over ours. **Also user-ruled (2026-11-22):** nothing more is baked
/// in. Which couple arches (`who`) changes nobody's landing, and the figure
/// carries the dance's progression only when the record flags it (or the
/// Caller's Box bridge assumes it: by its ordinary last-figure rule, or
/// because the arch comes straight after a line of four, user-ruled
/// 2026-11-24), like any other progression-eligible figure. Assuming the progression on the arch
/// itself was measured on the corpus before the ruling and did worse.
///
/// **From a line of four, the line bends into a ring first** *(user-ruled
/// 2026-11-24)*. Callers often leave the bend unwritten: "in a line of four,
/// go up the hall; ones arch, twos dive" means the line bends and then the
/// couples trade places. The ends step forward into the row the line faces
/// and turn to face the centres, who stay in the other row; everyone keeps
/// their own side of the set *(agent's call: the geometry of a bend the line,
/// read so each half of the line becomes one side of the ring)*. Then the row
/// swap runs as for any ring. A line not facing one way along the hall cannot
/// bend, so it is swapped as it stands and raises
/// [WarningKind.archFromLine].
///
/// Facing is preserved: both couples walk forward through.
final class ArchAndDive extends Operation {
  const ArchAndDive({this.who = WhoSet.twos});

  /// The couple that makes the arch. Descriptive; no positional effect.
  final WhoSet who;

  @override
  String get name => 'arch_and_dive';

  /// Empty on purpose: `who` is descriptive (user-ruled), so it must not
  /// re-band the set or reach along it the way a named set otherwise would.
  @override
  Iterable<WhoSet?> get dancerSets => const [];

  @override
  bool get progressionEligible => true;

  /// Warns when a hands four stands as a line of four that cannot bend into
  /// a ring ([WarningKind.archFromLine]): its dancers do not all face the same
  /// way along the hall. The swap still runs as ruled, and from a line it
  /// moves the whole line to the band's other row rather than trading two
  /// facing couples, which usually means the figure list needs a look.
  ///
  /// A line that does bend raises nothing: the bend is how the figure is
  /// danced from a line *(user-ruled 2026-11-24)*, not a fault in the record
  /// *(agent's call; the alternative was a warning naming the unwritten
  /// bend)*.
  @override
  Iterable<Warning> lint(Formation formation) {
    for (final band in handsFourBands(formation)) {
      final row = lineOfFourRow(formation, band);
      if (row == null || _bendFacing(formation, row) != null) continue;
      return [
        Warning(
          WarningKind.archFromLine,
          detail:
              'arch_and_dive was called on a line of four (row $row) that '
              'does not face one way along the hall, so it cannot bend into a '
              'ring; the row swap moves the whole line along the set instead '
              'of trading two facing couples',
        ),
      ];
    }
    return const [];
  }

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok<Formation, OpError>(reflectBands(_bendLines(formation), rows: true));

  /// The way the line of four in [row] faces, when every dancer in it faces
  /// the same way along the hall; otherwise `null`, and it cannot bend.
  static Facing? _bendFacing(Formation formation, int row) {
    final facings = {
      for (final id in formation.dancersInRow(row)) formation.stateOf(id).facing,
    };
    if (facings.length != 1) return null;
    final facing = facings.single;
    return facing == Facing.up || facing == Facing.down ? facing : null;
  }

  /// [formation] with every line of four that can bend bent into a ring.
  ///
  /// The two ends step forward into the row the line faces and turn back to
  /// face the centres; the centres stay in the other row, still facing the
  /// way the line did. The western half of the line ends in the western
  /// column, the eastern half in the eastern one.
  static Formation _bendLines(Formation formation) {
    final changes = <DancerId, DancerState>{};
    for (final band in handsFourBands(formation)) {
      final row = lineOfFourRow(formation, band);
      if (row == null) continue;
      final facing = _bendFacing(formation, row);
      if (facing == null) continue;
      final line = formation.dancersInRow(row).toList()
        ..sort(
          (a, b) =>
              formation.stateOf(a).col.compareTo(formation.stateOf(b).col),
        );
      final ahead = facing == Facing.up ? band.topRow : band.bottomRow;
      final behind = ahead == band.topRow ? band.bottomRow : band.topRow;
      const west = 0;
      const east = kColumnCount - 1;
      final landings = <DancerId, (Position, Facing)>{
        line[0]: (Position(ahead, west), facing.reversed),
        line[1]: (Position(behind, west), facing),
        line[2]: (Position(behind, east), facing),
        line[3]: (Position(ahead, east), facing.reversed),
      };
      for (final MapEntry(key: id, value: (position, faces))
          in landings.entries) {
        changes[id] = formation
            .stateOf(id)
            .copyWith(position: position, facing: faces);
      }
    }
    return changes.isEmpty ? formation : formation.withUpdates(changes);
  }

  @override
  bool operator ==(Object other) => other is ArchAndDive && other.who == who;

  @override
  int get hashCode => Object.hash(name, who);

  @override
  String toString() => 'arch_and_dive(${who.key})';
}
