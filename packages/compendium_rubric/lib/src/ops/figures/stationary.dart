part of '../operation.dart';

/// The figures that leave every dancer in their cell.
///
/// Grouped because they share a proof rather than a mechanism: each is
/// documented in `docs/taxonomy.md` as consuming beats without producing a net
/// displacement. [TurnAlone] joins them because its only effect is on facing,
/// which is excluded from success comparison (`docs/architecture.md` §3.5) —
/// though it is emphatically not a no-op, since downstream facing preconditions
/// read what it writes.

/// `balance` — a step forward and back with the `who` dancers.
///
/// The standalone figure, distinct from the `balance` *prefix* on `swing` and
/// the `balance` *flag* on `petronella`. Both parameters are descriptive: `who`
/// names whom you balance with and `hand` is styling, and neither has an
/// end-state effect.
final class Balance extends Operation {
  const Balance({this.who = WhoSet.neighbors, this.hand});

  /// Whom you balance with. Descriptive; no end-state effect.
  final WhoSet who;

  /// The hand given, when the source states one.
  ///
  /// `null` is the upstream `unspecified` sentinel rather than a missing value:
  /// most balances state no hand, and defaulting to a side would assert
  /// something the source never said.
  final Hand? hand;

  @override
  String get name => 'balance';

  /// Balancing the wave you are standing in is this figure's canonical use, so
  /// it reads the offsets rather than settling them away (§8.5.4).
  @override
  bool get preservesWaveOffsets => true;

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(formation);

  @override
  bool operator ==(Object other) =>
      other is Balance && other.who == who && other.hand == hand;

  @override
  int get hashCode => Object.hash(name, who, hand);

  @override
  String toString() => 'balance(${who.key}, ${hand?.key ?? 'unspecified'})';
}

/// `balance_the_ring` — all four join hands and balance in and out.
///
/// The ring counterpart of [Balance], and equally a positional identity. No
/// precondition is imposed: dancing it requires a ring of four with hands
/// joined, but since nothing moves there is no arrangement it could corrupt.
///
/// It does **not** declare [Operation.preservesWaveOffsets], unlike [Balance].
/// Moving nobody is not the test — the test is whether the figure is danceable
/// from a wave, and a ring needs hands joined all the way round, which a wave
/// is not. Dancers standing in one come out of it first (§8.5.4).
final class BalanceTheRing extends Operation {
  const BalanceTheRing();

  @override
  String get name => 'balance_the_ring';

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(formation);

  @override
  bool operator ==(Object other) => other is BalanceTheRing;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'balance_the_ring()';
}

/// `long_lines` — the two side lines go forward and back.
///
/// Only the go-and-return case is defined. `goBack: false` leaves dancers
/// displaced toward the centre, a position the side-column matrix has no cell
/// for, so it raises [ErrorKind.unsupportedParam] rather than being flattened
/// to an identity it is not.
///
/// Forward-and-back is danced **in the two side lines**, so this does not
/// declare [Operation.preservesWaveOffsets]: dancers standing in a short wave
/// are not in the lines and settle back to them first (§8.5.4). For a long
/// wave, whose dancers already stand at `c0`/`c4`, settling is a no-op.
final class LongLines extends Operation {
  const LongLines({this.goBack = true});

  /// Whether the lines return to place. Only `true` is implemented.
  final bool goBack;

  @override
  String get name => 'long_lines';

  @override
  OpError? checkPreconditions(Formation formation) {
    if (!goBack) {
      return const OpError(
        ErrorKind.unsupportedParam,
        'long_lines supports goBack:true only; the forward-only case leaves '
        'dancers displaced toward the centre, which the matrix cannot express',
      );
    }
    return null;
  }

  @override
  Result<Formation, OpError> perform(Formation formation) => Ok(formation);

  @override
  bool operator ==(Object other) =>
      other is LongLines && other.goBack == goBack;

  @override
  int get hashCode => Object.hash(name, goBack);

  @override
  String toString() => 'long_lines(goBack: $goBack)';
}

/// `turn_alone` — each `who` dancer turns 180° in place.
///
/// Facing is excluded from equality (D4), so this never changes the *compared*
/// state on its own — but it does change the state downstream figures read, and
/// `pass_through` will refuse to run if this has left dancers facing the wrong
/// axis. Treating it as a no-op would therefore be wrong twice over.
///
/// **Inside a line of four** "position unchanged" means the **column slots**
/// are preserved, not the row: a line's row is derived from its facing
/// (`docs/fundamentals.md` §8.1), so reversing facing migrates the whole line
/// to its band's other row. That is precisely what leaves the line *inverted*
/// relative to its new direction, and it must not be normalized away.
///
/// The migration is applied only when the entire line turns. A partial turn
/// breaks the line rather than moving it, and there is no defined shape to move
/// it to.
final class TurnAlone extends Operation {
  const TurnAlone({this.who = WhoSet.everyone, this.custom = ''});

  /// Which dancers turn.
  final WhoSet who;

  /// Free-text embellishment carried for fidelity; no structured effect.
  final String custom;

  @override
  String get name => 'turn_alone';

  @override
  Iterable<WhoSet?> get dancerSets => [who];

  @override
  Result<Formation, OpError> perform(Formation formation) {
    final changes = <DancerId, DancerState>{};
    for (final band in handsFourBands(formation)) {
      final members = [
        ...formation.dancersInRow(band.topRow),
        ...formation.dancersInRow(band.bottomRow),
      ];
      final turning = [
        for (final id in members)
          if (whoIncludes(formation, id, who)) id,
      ];
      if (turning.isEmpty) continue;

      final lineRow = lineOfFourRow(formation, band);
      final wholeLineTurns =
          lineRow != null && turning.length == members.length;

      for (final id in turning) {
        final state = formation.stateOf(id);
        final turned = state.facing.reversed;
        final destinationRow = wholeLineTurns ? lineRowFor(band, turned) : null;
        changes[id] = state.copyWith(
          facing: turned,
          position: destinationRow == null
              ? state.position
              : Position(destinationRow, state.col),
        );
      }
    }
    return Ok(formation.withUpdates(changes));
  }

  @override
  bool operator ==(Object other) =>
      other is TurnAlone && other.who == who && other.custom == custom;

  @override
  int get hashCode => Object.hash(name, who, custom);

  @override
  String toString() => 'turn_alone(${who.key})';
}
