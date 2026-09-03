import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The delivery choices offered for a canonical JSON export.
enum JsonExportChoice { save, copy, share }

/// Shows the JSON delivery choice dialog.
///
/// Dismissing the dialog (including barrier, back, and platform dismissal)
/// returns `null`, which callers treat exactly like [JsonExportChoice] cancel.
Future<JsonExportChoice?> showJsonExportChoiceDialog(BuildContext context) =>
    showDialog<JsonExportChoice>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.exportJsonDialogTitle),
          content: Text(l10n.exportJsonDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(JsonExportChoice.save),
              child: Text(l10n.exportJsonSave),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(JsonExportChoice.copy),
              child: Text(l10n.exportJsonCopy),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(JsonExportChoice.share),
              child: Text(l10n.exportJsonShare),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.exportJsonCancel),
            ),
          ],
        );
      },
    );
