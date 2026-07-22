import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The rating chosen in the batch-rating dialog: either a concrete star
/// [rating] (1..5) to set across the selection, or "clear" ([rating] `null`,
/// [clear] `true`) to unset it. Cancelling the dialog returns `null` instead.
class BatchRatingChoice {
  const BatchRatingChoice({this.rating, this.clear = false});

  /// The star rating (1..5) to set; `null` together with [clear] means "unset".
  final int? rating;

  /// Whether the user picked the explicit "Unrated (clear)" option.
  final bool clear;
}

/// Shows the batch **set rating** picker for the Collection multi-select flow
/// (parallel to [showBatchLevelDialog]). Setting a rating is a *replace*, so the
/// picker is a single-choice radio list — explicit and reversible via the
/// caller's Undo. Includes an explicit "Unrated (clear)" option so the
/// selection's rating can be removed.
///
/// Returns the [BatchRatingChoice], or `null` if the user cancelled. Choices use
/// [RadioListTile] so state is exposed to assistive tech (radio role + selected
/// state) paired with a text label ("N stars") — never the star icon alone.
Future<BatchRatingChoice?> showBatchRatingDialog(BuildContext context) {
  return showDialog<BatchRatingChoice>(
    context: context,
    builder: (_) => const _BatchRatingDialog(),
  );
}

class _BatchRatingDialog extends StatefulWidget {
  const _BatchRatingDialog();

  @override
  State<_BatchRatingDialog> createState() => _BatchRatingDialogState();
}

/// Sentinel for the "clear rating" radio option, distinct from a concrete
/// star count and from "nothing selected yet".
enum _RatingSelection { unrated }

class _BatchRatingDialogState extends State<_BatchRatingDialog> {
  // Holds either an `int` (1..5) or `_RatingSelection.unrated`; `null` until the
  // user picks something (keeps the confirm button disabled).
  Object? _selected;

  void _select(Object value) => setState(() => _selected = value);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('batch-rating-dialog'),
      title: Text(l10n.collectionSetRating),
      content: SizedBox(
        width: 360,
        child: RadioGroup<Object>(
          groupValue: _selected,
          onChanged: (value) {
            if (value != null) _select(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var stars = 1; stars <= 5; stars++)
                RadioListTile<Object>(
                  key: ValueKey('batch-rating-option-$stars'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: stars,
                  // Icon is decorative; the text label is the accessible name.
                  secondary: Icon(
                    Icons.star,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(l10n.collectionBatchRatingStars(stars)),
                ),
              RadioListTile<Object>(
                key: const ValueKey('batch-rating-option-unrated'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _RatingSelection.unrated,
                title: Text(l10n.collectionBatchRatingUnrated),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('batch-rating-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('batch-rating-confirm'),
          onPressed: _selected == null
              ? null
              : () {
                  final selected = _selected;
                  Navigator.of(context).pop(
                    selected is int
                        ? BatchRatingChoice(rating: selected)
                        : const BatchRatingChoice(clear: true),
                  );
                },
          child: Text(l10n.collectionBatchRatingConfirm),
        ),
      ],
    );
  }
}
