import '../model/dance.dart';
import '../model/figure_source.dart';
import '../model/provenance.dart';
import '../storage/repositories/repositories.dart';

/// [existing] with only its choreography — figures, formation and
/// progression — taken from [incoming].
///
/// This is the whole of what a re-import changes, from every source: the
/// detail screen's **Re-import choreography** and the import review's
/// **Re-import onto** row alike (maintainer decisions, 2026-10-29 and
/// 2026-10-30, INTAKE-7: "Your own ratings, tags and notes are never
/// overwritten by a re-import"). Title, authors, notes, walkthrough, status,
/// rating, tags, links, tunes, custom fields, citations and every other field
/// stay as [existing] has them. [provenance], when given, replaces the
/// existing provenance; otherwise it is kept.
///
/// [alsoTitleAndCredit] also takes [incoming]'s title and authors (its
/// `authorIds`, which the caller has already resolved to this library's
/// choreographers). The import review offers it per re-import row, off by
/// default (maintainer decision, 2026-10-30: "Ask per import"). An incoming
/// empty credit keeps the existing one: a source that sent no credit must not
/// erase the dance's. (A [Dance] title is never blank.)
///
/// An incoming transcription that is unreadable, or decoded to no figures,
/// keeps the existing one whole, an unreadable one included: a source that
/// sent no usable figures (The Caller's Box withholds them below its `full`
/// permission tier) must not erase the dance's transcription.
Dance withReimportedChoreography(
  Dance existing,
  Dance incoming, {
  required DateTime updatedAt,
  Provenance? provenance,
  bool alsoTitleAndCredit = false,
}) => existing.copyWith(
  // `null` keeps the existing value.
  title: alsoTitleAndCredit ? incoming.title : null,
  authorIds: alsoTitleAndCredit && incoming.authorIds.isNotEmpty
      ? incoming.authorIds
      : null,
  // `null` keeps the existing `figuresSource`, whatever it holds.
  figures: switch (incoming.figuresSource) {
    DecodedFigures(:final figures) when figures.isNotEmpty => figures,
    _ => null,
  },
  formation: incoming.formation,
  progression: incoming.progression,
  provenance: provenance ?? existing.provenance,
  updatedAt: updatedAt,
);

/// The outcome of [replaceDanceChoreography].
enum DanceReimportResult { replaced, targetMissing, targetChanged }

/// The safe, deliberately narrow update used by the detail-screen re-import.
///
/// Replaces only the choreography of [targetDanceId] (see
/// [withReimportedChoreography]), and only if it is still the version the user
/// previewed: a dance deleted or edited since then is reported, not written.
Future<DanceReimportResult> replaceDanceChoreography(
  CompendiumRepositories repos, {
  required String targetDanceId,
  required Dance incoming,
  required DateTime expectedUpdatedAt,
  DateTime? now,
}) async {
  return repos.db.transaction(() async {
    final existing = await repos.dances.getById(targetDanceId);
    if (existing == null) return DanceReimportResult.targetMissing;
    if (existing.updatedAt != expectedUpdatedAt) {
      return DanceReimportResult.targetChanged;
    }
    // Deliberately no `localUserEdit`, even though the user asked for this.
    // sync-spec §6.8 gates a held tombstone's cancellation on the write's
    // provenance, and provenance is about where the *content* comes from, not
    // about who pressed the button: the fields written here are the source's
    // choreography, not anything the user authored. Cancelling a peer's
    // deletion on the strength of imported content is the asymmetry ADR-004
    // ranks worst. Editing the dance afterwards still cancels the hold,
    // because that write is authored.
    await repos.dances.update(
      withReimportedChoreography(
        existing,
        incoming,
        updatedAt: now ?? DateTime.now().toUtc(),
      ),
    );
    return DanceReimportResult.replaced;
  });
}
