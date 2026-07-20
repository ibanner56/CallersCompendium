import 'package:compendium_core/compendium_core.dart';

/// Redacts a [Choreographer]'s private contact data for inclusion in a
/// **shareable** export (any program/dance share path).
///
/// The [Choreographer] model documents (choreographer.dart:6-9) that [email]
/// and [location] are private contact data that are safe in the user's own
/// full-DB snapshot/backup but MUST NOT be emitted in any shareable export.
/// This helper enforces that at the single send-side choke point: it clears
/// `email` and `location` while preserving the public attribution fields
/// (`name`, `website`, `notes`, `deceased`, and identity/timestamps).
///
/// It is intentionally a top-level, reusable function (not private to any one
/// builder): the program-share bundle uses it today, and the forthcoming
/// dance-share path (issue #298) must apply the identical redaction rather than
/// re-deriving an inline copyWith that could silently drift.
Choreographer sanitizeChoreographerForShare(Choreographer choreographer) =>
    choreographer.copyWith(clearEmail: true, clearLocation: true);
