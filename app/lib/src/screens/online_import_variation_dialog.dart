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
  required String existingTitle,
  required String existingId,
}) => showDialog<DedupeResolution>(
  context: context,
  builder: (ctx) => AlertDialog(
    key: const ValueKey('online-import-variation-dialog'),
    title: Text(l10n.importReviewVariationTitle(existingTitle)),
    // Dance titles come from online archives — unbounded external input.
    // SingleChildScrollView prevents overflow at large text scale or
    // with unusually long titles (mirrors published_source_details_dialog.dart).
    content: SingleChildScrollView(
      child: Column(
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
    ),
    actions: [
      TextButton(
        key: const ValueKey('online-import-variation-cancel'),
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(l10n.commonCancel),
      ),
      TextButton(
        key: const ValueKey('online-import-variation-as-variation'),
        onPressed: () =>
            Navigator.of(ctx).pop(DedupeResolution.variation(existingId)),
        child: Text(l10n.onlineImportVariationDialogActionVariation),
      ),
      FilledButton(
        key: const ValueKey('online-import-variation-same-dance'),
        onPressed: () =>
            Navigator.of(ctx).pop(DedupeResolution.link(existingId)),
        child: Text(l10n.onlineImportVariationDialogActionLink),
      ),
    ],
  ),
);

/// Shows a resolution dialog when a confident title+author match with
/// **canonically identical** figures is found during a single-dance online
/// import from a **different source** than the existing collection entry (issue
/// #811).
///
/// Three options:
/// - **Cancel** (FilledButton, primary/safe): nothing is imported.
/// - **Same dance** (TextButton): links the existing dance to the incoming
///   online record via [DedupeResolution.link], updating its provenance.
///   **Destructive** — replaces the existing dance wholesale (figures, notes,
///   tags, rating, custom fields); its place in programs and calling history
///   survive because the dance id is preserved.
/// - **Import a second copy** (TextButton): creates a new dance via
///   [DedupeResolution.duplicate] alongside the existing one.
///
/// "Import as a variation" is not offered: the figures are canonically
/// identical (same moves and order; beats and notes may differ), so a variation
/// would be indistinguishable in its figures from the original — the original
/// problem wearing a button. The user who wants both provenance records in the
/// collection can use "Import a second copy" instead.
///
/// Shared by [DanceListScreen] and [CollectionShell] so both surfaces use
/// identical wording. Add a new online-import surface? Route through here.
///
/// Returns the chosen [DedupeResolution], or `null` if the user cancelled.
Future<DedupeResolution?> showOnlineImportCrossSourceDuplicateDialog(
  BuildContext context,
  AppLocalizations l10n, {
  required String existingTitle,
  required String existingId,
}) => showDialog<DedupeResolution>(
  context: context,
  builder: (ctx) => AlertDialog(
    key: const ValueKey('online-import-cross-source-duplicate-dialog'),
    title: Text(l10n.onlineImportCrossSourceDuplicateDialogTitle),
    // Dance titles come from online archives — unbounded external input.
    // SingleChildScrollView prevents overflow at large text scale or
    // with unusually long titles (mirrors published_source_details_dialog.dart).
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.onlineImportCrossSourceDuplicateDialogBody(existingTitle)),
          const SizedBox(height: 8),
          Text(
            l10n.onlineImportVariationDialogLinkWarning(existingTitle),
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('online-import-cross-source-duplicate-import-copy'),
        onPressed: () => Navigator.of(ctx).pop(DedupeResolution.duplicate()),
        child: Text(l10n.onlineImportCrossSourceDuplicateDialogActionDuplicate),
      ),
      TextButton(
        key: const ValueKey('online-import-cross-source-duplicate-same-dance'),
        onPressed: () =>
            Navigator.of(ctx).pop(DedupeResolution.link(existingId)),
        child: Text(l10n.onlineImportVariationDialogActionLink),
      ),
      FilledButton(
        key: const ValueKey('online-import-cross-source-duplicate-cancel'),
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(l10n.commonCancel),
      ),
    ],
  ),
);
