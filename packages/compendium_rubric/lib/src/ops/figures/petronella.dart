part of '../operation.dart';

/// `petronella` — all four dancers move one place to the right around the hands
/// four (`docs/taxonomy.md`).
///
/// Mechanically identical to `circle` with `turn: right, places: 1`, so it is
/// expressed as exactly that rather than duplicating the ring arithmetic.
///
/// The optional balance lead-in has no end-state effect, matching `swing`'s
/// `prefix: balance`.
final class Petronella extends Operation {
  const Petronella({this.balance = true});

  /// Whether the figure is danced with a balance lead-in. No end-state effect.
  final bool balance;

  /// The equivalent ring figure this delegates to.
  static const Circle _asCircle = Circle(
    turn: CircleDirection.right,
    places: 1,
  );

  @override
  String get name => 'petronella';

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      _asCircle.perform(formation);

  @override
  bool operator ==(Object other) =>
      other is Petronella && other.balance == balance;

  @override
  int get hashCode => Object.hash(name, balance);

  @override
  String toString() => 'petronella(balance: $balance)';
}
