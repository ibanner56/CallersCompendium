import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shows the resolution dialog for a confident title+author match with
/// differing figures (issue #797). Returns the chosen [DedupeResolution], or
/// `null` if the user cancelled.
///
/// Shared by [DanceListScreen] and [CollectionShell] so both surfaces use
/// identical wording. Add a new online-import surface? Route through here.
Future<DedupeResolution?> showOnlineImportVariationDialog(
  BuildContext context,
  AppLocalizations l10n, {
  required String incomingTitle,
  required String existingTitle,
  required String? existingId,
}) => showDialog<DedupeResolution>(
  context: context,
  builder: (ctx) => AlertDialog(
    key: const ValueKey('online-import-variation-dialog'),
    title: Text(l10n.importReviewVariationTitle(existingTitle)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.onlineImportVariationDialogBody(existingTitle)),
        const SizedBox(height: 8),
        Text(
          l10n.onlineImportVariationDialogLinkWarning(existingTitle),
          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const ValueKey('online-import-variation-cancel'),
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(l10n.commonCancel),
      ),
      TextButton(
        key: const ValueKey('online-import-variation-as-variation'),
        onPressed: () => Navigator.of(ctx).pop(
          existingId != null
              ? DedupeResolution.variation(existingId)
              : DedupeResolution.duplicate(),
        ),
        child: Text(l10n.onlineImportVariationDialogActionVariation),
      ),
      if (existingId != null)
        FilledButton(
          key: const ValueKey('online-import-variation-same-dance'),
          onPressed: () =>
              Navigator.of(ctx).pop(DedupeResolution.link(existingId)),
          child: Text(l10n.onlineImportVariationDialogActionLink),
        ),
    ],
  ),
);
