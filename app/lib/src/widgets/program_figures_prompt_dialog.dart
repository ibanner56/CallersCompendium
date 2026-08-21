import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A pre-export prompt that asks whether to include full figure cards in a
/// program text or PDF export (issue #853, asks 2 and 3).
///
/// Result contract (consumed by [ProgramExportMenu]):
/// * `null` — the user cancelled **or** dismissed (tapped outside / back).
///   The caller MUST abort the export entirely; nothing is shared or written.
///   This dismiss==cancel behaviour mirrors [VenueContactShareDialog].
/// * `false` — the user chose "Set list only". Export titles + metadata only.
/// * `true` — the user chose "Set list and figures". Append full dance cards.
///
/// The dialog is shown only when at least one referenced dance has figures.
/// When no figures are available the caller skips this dialog entirely and
/// proceeds as "set list only" — there is nothing to offer.
class ProgramFiguresPromptDialog extends StatefulWidget {
  const ProgramFiguresPromptDialog({super.key});

  /// Shows the dialog. Returns `null` on cancel/dismiss, `false` for set-list
  /// only, `true` for set-list-and-figures.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const ProgramFiguresPromptDialog(),
    );
  }

  @override
  State<ProgramFiguresPromptDialog> createState() =>
      _ProgramFiguresPromptDialogState();
}

class _ProgramFiguresPromptDialogState
    extends State<ProgramFiguresPromptDialog> {
  /// `false` == set-list-only (default), `true` == set-list-and-figures.
  bool _includeFigures = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('program-figures-prompt-dialog'),
      title: Text(l10n.exportIncludeFiguresTitle),
      content: RadioGroup<bool>(
        groupValue: _includeFigures,
        onChanged: (v) {
          if (v != null) setState(() => _includeFigures = v);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<bool>(
              key: const ValueKey('program-figures-prompt-set-list-only'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: false,
              title: Text(l10n.exportIncludeFiguresSetListOnly),
            ),
            RadioListTile<bool>(
              key: const ValueKey(
                'program-figures-prompt-set-list-and-figures',
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: true,
              title: Text(l10n.exportIncludeFiguresSetListAndFigures),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('program-figures-prompt-confirm'),
          onPressed: () => Navigator.of(context).pop(_includeFigures),
          child: Text(l10n.commonContinue),
        ),
      ],
    );
  }
}
