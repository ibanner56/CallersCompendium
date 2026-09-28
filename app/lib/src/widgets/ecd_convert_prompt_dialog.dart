import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The user's answer to [showEcdConvertPromptDialog]: whether to run the
/// conversion, and whether they opted out of seeing the prompt again.
class EcdConvertPromptResult {
  const EcdConvertPromptResult({
    required this.convert,
    required this.dontShowAgain,
  });

  final bool convert;
  final bool dontShowAgain;
}

/// Shows the on-launch prompt offering to convert every non-English dance
/// tagged "ECD" to `DanceForm.ecd` and drop the tag.
///
/// Returns `null` if the dialog was dismissed without an explicit choice
/// (e.g. a barrier tap), which the caller treats the same as declining —
/// without persisting a "don't show again" opt-out, so the prompt returns on
/// the next launch that still finds a matching dance.
Future<EcdConvertPromptResult?> showEcdConvertPromptDialog(
  BuildContext context,
) => showDialog<EcdConvertPromptResult>(
  context: context,
  builder: (_) => const _EcdConvertPromptDialog(),
);

class _EcdConvertPromptDialog extends StatefulWidget {
  const _EcdConvertPromptDialog();

  @override
  State<_EcdConvertPromptDialog> createState() =>
      _EcdConvertPromptDialogState();
}

class _EcdConvertPromptDialogState extends State<_EcdConvertPromptDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('ecd-convert-prompt-dialog'),
      title: Text(l10n.startupEcdConvertTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.startupEcdConvertMessage),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('ecd-convert-prompt-dont-show-again'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontShowAgain,
            onChanged: (checked) =>
                setState(() => _dontShowAgain = checked ?? false),
            title: Text(l10n.startupEcdConvertDontShowAgain),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('ecd-convert-prompt-decline'),
          onPressed: () => Navigator.of(context).pop(
            EcdConvertPromptResult(
              convert: false,
              dontShowAgain: _dontShowAgain,
            ),
          ),
          child: Text(l10n.startupEcdConvertDecline),
        ),
        FilledButton(
          key: const ValueKey('ecd-convert-prompt-confirm'),
          onPressed: () => Navigator.of(context).pop(
            EcdConvertPromptResult(
              convert: true,
              dontShowAgain: _dontShowAgain,
            ),
          ),
          child: Text(l10n.startupEcdConvertConfirm),
        ),
      ],
    );
  }
}
