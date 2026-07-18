import 'package:compendium_core/compendium_core.dart';

/// Builds a self-contained "share this program + its dances" bundle (ROADMAP
/// §4.3, issue #298 — AirDrop/OS share-sheet sharing, send side).
///
/// The bundle is **not a new format**: it is the canonical [CompendiumArchive]
/// exchange JSON (`docs/design/imports.md` §"Generic JSON (6.6)"), the same
/// format the manual Import flow's `GenericJsonAdapter` already consumes. Here
/// the archive carries a single [program] plus the full definitions of every
/// dance the program references, so the receiving device can re-import the
/// dances through the existing import path with nothing else attached. The
/// program is carried alongside them for the forthcoming receive-side
/// auto-open (issue #298, PR 2), which will import the program itself; the
/// current manual Import flow imports the dances only.
///
/// [danceFor] resolves a slot's `danceId` to its full [Dance]; a referenced id
/// that can't be resolved is skipped (best-effort, never fatal — mirrors the
/// codec's partial-failure tolerance). Repeated `danceId`s are de-duplicated so
/// each dance appears once. Slot order and note-only slots are preserved by the
/// program itself (its `slots` carry their own `text`), so nothing extra is
/// needed for them here.
///
/// [now] stamps the archive's `exportedAt`; it defaults to the current time and
/// is injectable for deterministic tests.
String buildProgramShareBundle(
  Program program, {
  required Dance? Function(String danceId) danceFor,
  DateTime? now,
}) {
  final dances = <Dance>[];
  final seen = <String>{};
  for (final slot in program.slots) {
    final danceId = slot.danceId;
    if (danceId == null || !seen.add(danceId)) continue;
    final dance = danceFor(danceId);
    if (dance != null) dances.add(dance);
  }

  return encodeArchive(
    CompendiumArchive(
      exportedAt: (now ?? DateTime.now()).toUtc(),
      programs: [program],
      dances: dances,
    ),
  );
}

/// A filesystem-safe file name for a program share bundle, derived from the
/// program [title].
///
/// The title is sanitized to `[A-Za-z0-9._-]` (every other character — path
/// separators, spaces, control characters — becomes `_`) so it is safe to use
/// as a temp-file name and share-sheet file name without path traversal or
/// odd-character surprises. An empty/all-illegal title falls back to a stable
/// default. The `.json` extension matches the canonical archive content type
/// and what the importer's file picker accepts.
String programShareBundleFileName(String title) {
  final sanitized = title.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  // Fall back when the title has no alphanumeric content (empty, all
  // whitespace, or only illegal/punctuation characters) so the file always has
  // a meaningful, path-safe name.
  final hasContent = sanitized.contains(RegExp(r'[A-Za-z0-9]'));
  final base = hasContent ? sanitized : 'program';
  return '$base.json';
}
