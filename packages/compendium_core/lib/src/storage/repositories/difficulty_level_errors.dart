/// The person-facing refusals of `DifficultyLevelRepository`.
///
/// They subclass the type each site threw before ([ArgumentError] for an empty
/// label, [StateError] for the other two) so every existing
/// `on StateError` / `on ArgumentError` site (archive restore's guard, sync,
/// import) keeps working, while the settings screen can catch them by type and
/// say so in its own localized sentence. The English [message] stays for logs.
library;

/// A level's label was empty once sanitized and trimmed.
///
/// Screens MUST render their own localized sentence and MUST NOT surface
/// [toString], which is English text naming internal argument names (CWE-209).
class DifficultyLevelLabelEmpty extends ArgumentError {
  DifficultyLevelLabelEmpty(Object? raw)
    : super.value(raw, 'label', 'must not be empty');
}

/// Another live level already holds [label], compared ignoring case.
///
/// A [StateError], not an [ArgumentError], because both throw sites raised a
/// `StateError` before this class existed and `sync_apply` routes the two
/// supertypes to different branches (§6.7: a natural-key collision from a peer
/// is reported to reconciliation).
///
/// [label] is user-entered text. Screens MUST render it as plain text in their
/// own localized sentence and MUST NOT surface [toString] (CWE-209).
class DifficultyLevelLabelDuplicate extends StateError {
  DifficultyLevelLabelDuplicate(this.label)
    : super('difficulty level labels must be unique: "$label"');

  /// The normalized label that collided.
  final String label;
}

/// A level cannot be deleted because [count] dances (including deleted ones
/// that can be restored) still refer to it.
///
/// [id] is an internal identifier. Screens MUST NOT surface it or [toString]
/// (CWE-209); they show the level's display label in their own localized
/// sentence. [label] is only set by a caller that already knows it.
class DifficultyLevelInUse extends StateError {
  DifficultyLevelInUse({required this.id, required this.count, this.label})
    : super(
        'cannot delete difficulty level "$id": still referenced by '
        '$count dance(s)',
      );

  final String id;
  final int count;
  final String? label;
}
