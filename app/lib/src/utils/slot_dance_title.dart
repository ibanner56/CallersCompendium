import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';

/// Whether [dance] is a blank another device's Permanently delete left: the
/// permanently-deleted mark **and** the placeholder title, with no content.
/// See [slotDanceTitle] for why the mark alone is not enough.
bool isBlankedDance(Dance dance) =>
    isPermanentlyDeleted(dance.deletedAt) && dance.title == blankedRecordTitle;

/// The title a program slot shows for [dance].
///
/// A dance permanently deleted on another device arrives here blanked: its
/// title is the placeholder [blankedRecordTitle] ("—") and its content is
/// gone. The device that deleted it rewrote its own programs' slots, but a
/// slot added on this device before the blank arrived still cites it, and
/// used to read "— (deleted dance)". It shows "Deleted dance" instead (the
/// maintainer's decision Q-6, 2026-10-31, recorded in
/// `docs/dev/audits/2026-10-behavior/` on the audit branch).
///
/// Both tests are needed. A retention sweep marks a dance a slot still cites
/// as permanently deleted but keeps its title, which that slot goes on
/// showing (`DanceRepository.removePermanentlyDeleted`); such a dance is
/// treated as any other in Recently deleted.
///
/// With [markDeleted], any other dance in Recently deleted keeps its title
/// followed by "(deleted dance)", as Perform, the builder and the summary
/// mark it. Exports leave that mark out: the band is still playing the dance.
String slotDanceTitle(
  AppLocalizations l10n,
  Dance dance, {
  bool markDeleted = false,
}) {
  if (isBlankedDance(dance)) {
    return l10n.programsBlankedDanceTitle;
  }
  if (markDeleted && dance.isDeleted) {
    return '${dance.title} ${l10n.programsDeletedDanceFallback}';
  }
  return dance.title;
}
