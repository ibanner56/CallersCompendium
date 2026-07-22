import 'package:compendium_core/compendium_core.dart';

/// Resolves the venue label to DISPLAY for [program], bridging the two
/// coexisting venue modes (see [VenueEntityModeScope]).
///
/// When the program links a reusable [Venue] (`venueId`) that resolves in
/// [venuesById], its [Venue.displayName] wins — a linked record is the
/// authoritative, richer source. Otherwise this falls back to the free-text
/// [Program.venue]. Returns `null` when neither is available, so callers can
/// omit the venue line entirely.
///
/// Resolution is independent of the settings toggle: the toggle governs the
/// editor's entry mode only, while both columns persist independently, so a
/// linked venue is always shown when present regardless of the current mode.
String? resolveVenueLabel(Program program, Map<String, Venue> venuesById) =>
    resolveVenueLabelParts(program.venueId, program.venue, venuesById);

/// Field-level variant of [resolveVenueLabel] for callers that hold a program's
/// [venueId] + free-text [venue] without a full [Program] (e.g. a derived
/// calling-history record). Same precedence: a resolvable linked [Venue]'s
/// display name wins, else the trimmed free text, else `null`.
String? resolveVenueLabelParts(
  String? venueId,
  String? venue,
  Map<String, Venue> venuesById,
) {
  if (venueId != null) {
    final linked = venuesById[venueId];
    if (linked != null) return linked.displayName;
  }
  final free = venue?.trim();
  if (free != null && free.isNotEmpty) return free;
  return null;
}
