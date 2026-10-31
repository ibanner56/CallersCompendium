import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';

/// Offers to link older programs that have a venue *typed in* to the venue
/// records in [venues] that share the typed name (GIG-7, maintainer decision
/// 2026-10-29: "Offer to link old programs. When venue records are turned
/// on.").
///
/// Calling history keeps a typed "Grange" and a record "Grange" apart until a
/// program is linked, so a hall called at once under each never shows as a
/// repeat. Matching is [VenueKey]'s, the same folding the repeated-venues list
/// uses, and covers live programs only: a trashed program keeps its typed
/// venue.
///
/// Shows nothing when no program matches, so it is safe to call on every venue
/// creation. A "Not now" answer is not remembered; the offer comes back the
/// next time a matching venue record is created or the setting is turned on
/// (our call: remembering a refusal would need a settings key, which the
/// plan ruled out).
///
/// [excludeProgramId] is the program an open editor is about to save with its
/// own venue link; linking it here too would make the editor's save lose its
/// compare-and-replace.
Future<void> offerToLinkTypedVenues(
  BuildContext context, {
  required Iterable<Venue> venues,
  String? excludeProgramId,
}) async {
  final repos = RepositoriesScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final offers = <({Venue venue, int count})>[];
  for (final venue in venues) {
    final count = await repos.programs.countTypedVenuePrograms(
      venue.name,
      excludeProgramId: excludeProgramId,
    );
    if (count > 0) offers.add((venue: venue, count: count));
  }
  if (offers.isEmpty || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.venueLinkOfferTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.venueLinkOfferBody),
          const SizedBox(height: 12),
          for (final offer in offers)
            Text(l10n.venueLinkOfferRow(offer.venue.name, offer.count)),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('venue-link-offer-decline'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.venueLinkOfferDecline),
        ),
        FilledButton(
          key: const ValueKey('venue-link-offer-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.venueLinkOfferConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  var linked = 0;
  for (final offer in offers) {
    linked += await repos.programs.linkTypedVenues(
      venueId: offer.venue.id,
      name: offer.venue.name,
      updatedAt: DateTime.now().toUtc(),
      excludeProgramId: excludeProgramId,
    );
  }
  if (linked == 0) return;
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.venueLinkOfferDone(linked))),
  );
}
