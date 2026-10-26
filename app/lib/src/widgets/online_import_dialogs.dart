import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/dance_reimport.dart';
import '../data/default_import_tags.dart';
import '../data/online_search.dart';

/// Shows the resolution dialog for a confident title+author match with
/// differing figures (issue #797). Returns the chosen [DedupeResolution], or
/// `null` if the user cancelled.
///
/// [allowLink] is `false` for a record that brought no figures: "Same dance"
/// would replace the existing dance's figures with nothing, so it is not
/// offered and a note says why.
///
/// Shared by every interactive online-import surface ([DanceListScreen],
/// [CollectionShell], [CollectionPicker] and the incoming-dance flow in
/// `main.dart`) via [resolveAndImportOnline], so all use identical wording.
/// Add a new online-import surface? Route through [resolveAndImportOnline].
Future<DedupeResolution?> showOnlineImportVariationDialog(
  BuildContext context,
  AppLocalizations l10n, {
  required String existingTitle,
  required String existingId,
  bool allowLink = true,
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
            allowLink
                ? l10n.onlineImportVariationDialogLinkWarning(existingTitle)
                : l10n.importFigurelessCannotReplace,
            key: allowLink
                ? null
                : const ValueKey('online-import-no-figures-note'),
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
      if (allowLink)
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
///   **Destructive** — replaces the existing dance's title, figures, notes,
///   tags and rating; its custom fields (#1890), its place in programs and its
///   calling history survive, the last two because the dance id is preserved.
/// - **Import a second copy** (TextButton): creates a new dance via
///   [DedupeResolution.duplicate] alongside the existing one.
///
/// "Import as a variation" is not offered: the figures are canonically
/// identical (same moves and order; beats and notes may differ), so a variation
/// would be indistinguishable in its figures from the original — the original
/// problem wearing a button. The user who wants both provenance records in the
/// collection can use "Import a second copy" instead.
///
/// Shared by every interactive online-import surface ([DanceListScreen],
/// [CollectionShell], [CollectionPicker] and the incoming-dance flow in
/// `main.dart`) via [resolveAndImportOnline], so all use identical wording.
/// Add a new online-import surface? Route through [resolveAndImportOnline].
///
/// [allowLink] is `false` for a record that brought no figures (both sides then
/// compare as having none): "Same dance" is not offered, as in
/// [showOnlineImportVariationDialog].
///
/// Returns the chosen [DedupeResolution], or `null` if the user cancelled.
Future<DedupeResolution?> showOnlineImportCrossSourceDuplicateDialog(
  BuildContext context,
  AppLocalizations l10n, {
  required String existingTitle,
  required String existingId,
  bool allowLink = true,
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
            allowLink
                ? l10n.onlineImportVariationDialogLinkWarning(existingTitle)
                : l10n.importFigurelessCannotReplace,
            key: allowLink
                ? null
                : const ValueKey('online-import-no-figures-note'),
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
      if (allowLink)
        TextButton(
          key: const ValueKey(
            'online-import-cross-source-duplicate-same-dance',
          ),
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

/// Shows the existing dances that may be the incoming one under a differently
/// written title (issue #1907) and lets the user pick one to replace, import a
/// new dance instead, or cancel. Nothing is preselected: a possible match is
/// only ever applied by the user's tap.
///
/// [existing] pairs each candidate's id with its title, in collection order.
/// Returns [DedupeResolution.link] for a picked dance,
/// [DedupeResolution.duplicate] for a new dance, or `null` on cancel.
Future<DedupeResolution?> showOnlineImportPossibleMatchDialog(
  BuildContext context,
  AppLocalizations l10n, {
  required String incomingTitle,
  required List<({String id, String title})> existing,
}) => showDialog<DedupeResolution>(
  context: context,
  builder: (ctx) => AlertDialog(
    key: const ValueKey('online-import-possible-match-dialog'),
    title: Text(l10n.onlineImportPossibleMatchDialogTitle),
    // Titles on both sides are unbounded input; scroll rather than overflow.
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.onlineImportPossibleMatchDialogBody(incomingTitle)),
          const SizedBox(height: 8),
          for (final dance in existing)
            ListTile(
              key: ValueKey('online-import-possible-match-${dance.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.importReviewOptionPossibleTitle(dance.title)),
              onTap: () =>
                  Navigator.of(ctx).pop(DedupeResolution.link(dance.id)),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.onlineImportPossibleMatchDialogLinkWarning,
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('online-import-possible-match-cancel'),
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(l10n.commonCancel),
      ),
      FilledButton(
        key: const ValueKey('online-import-possible-match-new'),
        onPressed: () => Navigator.of(ctx).pop(DedupeResolution.duplicate()),
        child: Text(l10n.onlineImportPossibleMatchDialogActionNew),
      ),
    ],
  ),
);

/// Commits [preview] through [service] and resolves the confirmation outcomes
/// interactively: [OnlineImportKind.needsConfirmation] shows
/// [showOnlineImportVariationDialog] (#797),
/// [OnlineImportKind.needsConfirmationIdentical] shows
/// [showOnlineImportCrossSourceDuplicateDialog] (#811), and
/// [OnlineImportKind.needsPossibleMatchChoice] shows
/// [showOnlineImportPossibleMatchDialog] (#1907); the import is then retried
/// with the chosen [DedupeResolution]. Every interactive online-import
/// surface calls this, so a change to the resolution policy is made once.
///
/// Returns the final [OnlineImportResult] of the import that committed, or
/// `null` when no further import was made: the user cancelled a dialog,
/// [context] was unmounted before a dialog could be shown or while it was open,
/// or the service broke its contract and returned a confirmation outcome with
/// no candidate id (asserted in debug). A result is returned even if [context]
/// unmounted while that import was in flight: the write has happened, so the
/// caller must still see its outcome (the picker relies on this).
///
/// Liveness is [BuildContext.mounted], checked before the context is handed to
/// a dialog and after the dialog closes. It is only as live as the context the
/// caller passes: a State's own context goes away with the State, while a
/// NavigatorState's context outlives a widget removed from a live route (the
/// picker passes the navigator's for that reason). A caller that also needs its
/// own staleness test (the picker's search generation) keeps it around the call.
///
/// The helper deliberately catches nothing: each caller has its own error sink
/// (snackbar, detail-pane messenger, inline picker error) and its own
/// `check_caught_error_logged` obligations. It does not touch
/// `ScaffoldMessenger` or `Navigator` either.
///
/// Every commit adds the user's default import tags (#1476), resolved
/// immediately before it.
///
/// A [preview] that brought no figures ([draftHasNoFigures]) is never offered
/// the choice to replace a dance: [commitPreviewedOnlinePlan] skips the
/// possible-match question, and the confirmation dialogs here drop "Same dance".
Future<OnlineImportResult?> resolveAndImportOnline(
  BuildContext context, {
  required OnlineSearchService service,
  required CompendiumRepositories repos,
  required OnlinePreview preview,
  required AppLocalizations l10n,
}) async {
  Future<OnlineImportResult> commit([DedupeResolution? resolution]) async =>
      service.import(
        repos,
        preview.plan,
        ambiguousResolution: resolution,
        defaultTagIds: await resolveDefaultImportTagIds(repos),
      );

  final first = await commit();
  if (first.kind == OnlineImportKind.needsPossibleMatchChoice) {
    final existing = [
      for (final id in first.possibleMatchIds)
        if ((await repos.dances.getById(id))?.title case final title?)
          (id: id, title: title),
    ];
    // Every candidate was deleted since the preview was planned: nothing is
    // left to choose between, so this is a new dance like any other.
    if (existing.isEmpty) return commit(DedupeResolution.duplicate());
    if (!context.mounted) return null;
    final resolution = await showOnlineImportPossibleMatchDialog(
      context,
      l10n,
      incomingTitle: first.title,
      existing: existing,
    );
    if (resolution == null || !context.mounted) return null;
    return commit(resolution);
  }
  final isVariation = first.kind == OnlineImportKind.needsConfirmation;
  final isIdentical = first.kind == OnlineImportKind.needsConfirmationIdentical;
  if (!isVariation && !isIdentical) return first;

  final existingId = first.danceId;
  // A confirmation outcome requires a candidate id; null is a service bug.
  // Assert in debug, silently cancel in release (better than crashing).
  assert(
    existingId != null,
    '${first.kind.name} must carry an existing dance id',
  );
  if (existingId == null || !context.mounted) return null;
  final existingTitle =
      (await repos.dances.getById(existingId))?.title ?? first.title;
  if (!context.mounted) return null;
  final allowLink = !draftHasNoFigures(preview.plan.draft);
  final resolution = isVariation
      ? await showOnlineImportVariationDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
          allowLink: allowLink,
        )
      : await showOnlineImportCrossSourceDuplicateDialog(
          context,
          l10n,
          existingTitle: existingTitle,
          existingId: existingId,
          allowLink: allowLink,
        );
  if (resolution == null || !context.mounted) return null;
  return commit(resolution);
}
