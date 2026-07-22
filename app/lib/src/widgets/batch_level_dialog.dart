import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

/// The level chosen in the batch-level dialog: either a concrete [DanceLevel]
/// to set across the selection, or "clear" ([level] `null`, [clear] `true`) to
/// unset the level. Cancelling the dialog returns `null` instead of this.
class BatchLevelChoice {
  const BatchLevelChoice({this.level, this.clear = false});

  /// The level to set; `null` together with [clear] means "unset".
  final DanceLevel? level;

  /// Whether the user picked the explicit "Unspecified (clear)" option.
  final bool clear;
}

/// Shows the batch **set level** picker for the Collection multi-select flow
/// (parallel to [showBatchTagDialog]). Unlike batch tagging, setting a level is
/// a *replace*, so the picker is a single-choice radio list — explicit and
/// reversible via the caller's Undo. Includes an explicit "Unspecified (clear)"
/// option so the selection's level can be removed.
///
/// Returns the [BatchLevelChoice], or `null` if the user cancelled. Choices use
/// [RadioListTile] so state is exposed to assistive tech (radio role + selected
/// state) paired with a text label — never color alone.
Future<BatchLevelChoice?> showBatchLevelDialog(BuildContext context) {
  return showDialog<BatchLevelChoice>(
    context: context,
    builder: (_) => const _BatchLevelDialog(),
  );
}

class _BatchLevelDialog extends StatefulWidget {
  const _BatchLevelDialog();

  @override
  State<_BatchLevelDialog> createState() => _BatchLevelDialogState();
}

/// Sentinel for the "clear level" radio option, distinct from a concrete
/// [DanceLevel] and from "nothing selected yet".
enum _LevelSelection { unspecified }

class _BatchLevelDialogState extends State<_BatchLevelDialog> {
  // Holds either a `DanceLevel` or `_LevelSelection.unspecified`; `null` until
  // the user picks something (keeps the confirm button disabled).
  Object? _selected;

  void _select(Object value) => setState(() => _selected = value);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('batch-level-dialog'),
      title: Text(l10n.collectionSetLevel),
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
              for (final v in DanceLevel.values)
                RadioListTile<Object>(
                  key: ValueKey('batch-level-option-${v.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: v,
                  title: Text(danceLevelLabel(v)),
                ),
              RadioListTile<Object>(
                key: const ValueKey('batch-level-option-unspecified'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _LevelSelection.unspecified,
                title: Text(l10n.collectionBatchLevelUnspecified),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('batch-level-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('batch-level-confirm'),
          onPressed: _selected == null
              ? null
              : () {
                  final selected = _selected;
                  Navigator.of(context).pop(
                    selected is DanceLevel
                        ? BatchLevelChoice(level: selected)
                        : const BatchLevelChoice(clear: true),
                  );
                },
          child: Text(l10n.collectionBatchLevelConfirm),
        ),
      ],
    );
  }
}
