part of '../operation.dart';

/// `stand_still` — dancers hold position for the given beats.
///
/// A **pure no-op / identity** (`docs/taxonomy.md`): positions, roles, numbers,
/// couple identity, and facing are all preserved. It exists because a dance
/// record may legitimately call for held beats, and because an identity figure
/// is the cleanest possible check that the operation framework itself is wired
/// correctly.
final class StandStill extends Operation {
  const StandStill({this.beats = 8});

  /// Timing only. The Compendium baseline accepts any in-domain beat count
  /// here — there is no `goodBeats` constraint on this figure.
  final int beats;

  @override
  String get name => 'stand_still';

  @override
  bool get preservesWaveOffsets => true;

  @override
  Result<Formation, OpError> perform(Formation formation) =>
      Ok<Formation, OpError>(formation);

  @override
  bool operator ==(Object other) => other is StandStill && other.beats == beats;

  @override
  int get hashCode => Object.hash(StandStill, beats);
}
