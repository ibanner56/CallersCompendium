/// Which way a dancer faces.
///
/// See `docs/fundamentals.md` §6. Facing is tracked because it drives position
/// normalization (§8) and progression handling at the ends of the set (§10),
/// but it is deliberately **excluded from success-state equality**
/// (`docs/architecture.md` §3.5) — which is why it is stored on the dancer and
/// never inside the matrix cell value.
enum Facing {
  /// Toward the top of the hall / row 0 (North).
  up(label: 'up'),

  /// Toward the bottom of the hall / the last row (South).
  down(label: 'down'),

  /// Toward higher column indices / c4 (East).
  acrossEast(label: 'across->'),

  /// Toward lower column indices / c0 (West).
  acrossWest(label: 'across<-'),

  /// Context-dependent — not yet fixed, and resolved by the following figure.
  ///
  /// Flexible propagates until a figure consumes it (by normalizing relative
  /// to facing) or a progression sets a concrete facing.
  flexible(label: 'flex');

  const Facing({required this.label});

  /// Short tag used in diagnostics and the debug renderer.
  final String label;

  /// Whether this facing runs along the hall (up/down) rather than across it.
  bool get isAlongHall => this == Facing.up || this == Facing.down;

  /// Whether this facing runs across the set (east/west) rather than along it.
  bool get isAcross => this == Facing.acrossEast || this == Facing.acrossWest;

  /// Whether the direction is concrete (i.e. anything but [Facing.flexible]).
  bool get isConcrete => this != Facing.flexible;

  /// The 180° reversal of this facing.
  ///
  /// [Facing.flexible] reverses to itself: the opposite of an undetermined
  /// direction is still undetermined. This is the shared primitive behind
  /// `turn_alone`, `california_twirl`, `turn_as_couples`, and the half-turn
  /// case of the allemande family.
  Facing get reversed => switch (this) {
    Facing.up => Facing.down,
    Facing.down => Facing.up,
    Facing.acrossEast => Facing.acrossWest,
    Facing.acrossWest => Facing.acrossEast,
    Facing.flexible => Facing.flexible,
  };

  /// The direction on this dancer's **left**, i.e. a quarter turn
  /// counterclockwise (`docs/fundamentals.md` §7).
  ///
  /// Facing up, left is West/c0; facing down, left is East/c4; facing across
  /// east, left is North/toward r0; facing across west, left is South.
  Facing get turnedLeft => switch (this) {
    Facing.up => Facing.acrossWest,
    Facing.down => Facing.acrossEast,
    Facing.acrossEast => Facing.up,
    Facing.acrossWest => Facing.down,
    Facing.flexible => Facing.flexible,
  };

  /// The direction on this dancer's **right** — a quarter turn clockwise (§7).
  Facing get turnedRight => turnedLeft.reversed;
}
