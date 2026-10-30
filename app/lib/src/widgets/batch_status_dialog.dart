import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

/// Shows the batch **set status** picker for the Collection multi-select flow
/// (parallel to [showBatchLevelDialog]). Setting a status is a *replace*, so
/// the picker is a single-choice radio list, reversible via the caller's Undo.
/// A status is never null, so unlike level and rating there is no "clear"
/// option. The labels are the editor's ([danceStatusLabel]).
///
/// Returns the chosen [DanceStatus], or `null` if the user cancelled. Choices
/// use [RadioListTile] so state is exposed to assistive tech (radio role +
/// selected state) paired with a text label.
Future<DanceStatus?> showBatchStatusDialog(BuildContext context) {
  return showDialog<DanceStatus>(
    context: context,
    builder: (_) => const _BatchStatusDialog(),
  );
}

class _BatchStatusDialog extends StatefulWidget {
  const _BatchStatusDialog();

  @override
  State<_BatchStatusDialog> createState() => _BatchStatusDialogState();
}

class _BatchStatusDialogState extends State<_BatchStatusDialog> {
  // `null` until the user picks something (keeps the confirm button disabled).
  DanceStatus? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('batch-status-dialog'),
      title: Text(l10n.collectionSetStatus),
      // Scrolls: five options overflow a 320 x 568 screen at the largest text
      // scale.
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: RadioGroup<DanceStatus>(
            groupValue: _selected,
            onChanged: (value) => setState(() => _selected = value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final status in DanceStatus.values)
                  RadioListTile<DanceStatus>(
                    key: ValueKey('batch-status-option-${status.name}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: status,
                    title: Text(danceStatusLabel(l10n, status)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('batch-status-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('batch-status-confirm'),
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: Text(l10n.collectionBatchStatusConfirm),
        ),
      ],
    );
  }
}
