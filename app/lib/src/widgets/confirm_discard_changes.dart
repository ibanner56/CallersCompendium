import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/destructive_button_style.dart';

/// What the user chose in [confirmDiscardChanges].
enum DiscardChangesChoice {
  /// Stay in the editor. Also the answer when the dialog is dismissed without
  /// a choice (a tap outside it, or Back).
  keepEditing,

  /// Leave the editor and lose the unsaved changes.
  discard,

  /// Save, then leave. Offered only when the caller passes a `saveLabel`.
  save,
}

/// The shared "Discard changes?" prompt an editor shows before it throws away
/// unsaved work (UX2-1).
///
/// Used by the dance, program, compound-figure and dialect editors, which pass
/// the wording they had before this helper existed, and (through
/// [DiscardChangesGuard], with the generic `common*` strings) by the shorthand,
/// compound-shorthand and theme editors and the venue and custom-field sheets.
///
/// Passing [saveLabel] adds a third action that saves and leaves, as the
/// dialect editor offers. The caller does the saving: this only reports the
/// choice, so a save that fails validation can keep the user in the editor.
///
/// **Layout** (maintainer decision D-1, UX2-2): the safe choice is the filled
/// one and the destructive choice is red text. Without [saveLabel], the actions
/// are Discard (red text) and Keep editing (filled). With [saveLabel], they are
/// Cancel (text), Discard (red text) and Save (filled): saving is also safe,
/// so it keeps the fill it had. Only this function's layout encodes that, not
/// its callers.
///
/// Returns [DiscardChangesChoice.keepEditing] when the dialog is dismissed
/// without a choice.
Future<DiscardChangesChoice> confirmDiscardChanges(
  BuildContext context, {
  String? title,
  String? message,
  String? keepEditingLabel,
  String? discardLabel,
  String? saveLabel,
  Key? dialogKey,
  Key keepEditingKey = const ValueKey('discard-cancel'),
  Key discardKey = const ValueKey('discard-confirm'),
  Key saveKey = const ValueKey('discard-save'),
}) async {
  final l10n = AppLocalizations.of(context);
  final offersSave = saveLabel != null;
  final choice = await showDialog<DiscardChangesChoice>(
    context: context,
    builder: (dialogContext) {
      void choose(DiscardChangesChoice choice) =>
          Navigator.of(dialogContext).pop(choice);
      final discardButton = TextButton(
        key: discardKey,
        style: destructiveTextButtonStyle(Theme.of(dialogContext).colorScheme),
        onPressed: () => choose(DiscardChangesChoice.discard),
        child: Text(discardLabel ?? l10n.commonDiscard),
      );
      return AlertDialog(
        key: dialogKey,
        title: Text(title ?? l10n.commonDiscardChangesTitle),
        content: Text(message ?? l10n.commonDiscardChangesBody),
        actions: [
          if (offersSave) ...[
            TextButton(
              key: keepEditingKey,
              onPressed: () => choose(DiscardChangesChoice.keepEditing),
              child: Text(keepEditingLabel ?? l10n.commonKeepEditing),
            ),
            discardButton,
            FilledButton(
              key: saveKey,
              onPressed: () => choose(DiscardChangesChoice.save),
              child: Text(saveLabel),
            ),
          ] else ...[
            discardButton,
            FilledButton(
              key: keepEditingKey,
              onPressed: () => choose(DiscardChangesChoice.keepEditing),
              child: Text(keepEditingLabel ?? l10n.commonKeepEditing),
            ),
          ],
        ],
      );
    },
  );
  return choice ?? DiscardChangesChoice.keepEditing;
}

/// Blocks leaving the route while [dirty], and asks [confirmDiscardChanges]
/// first: Discard pops the route with no result, Keep editing stays.
///
/// This catches every pop that goes through `Navigator.maybePop`: the system
/// Back button or gesture, the app bar's back arrow, and a tap on a modal
/// sheet's barrier. It does **not** catch a direct `Navigator.pop`, which is
/// what a modal bottom sheet's swipe-down and drag handle call, so a sheet
/// guarded by this must be shown with `enableDrag: false` and no drag handle.
/// An editor's own Save and Cancel buttons pop directly too, and are meant to.
///
/// The caller must rebuild this when [dirty] changes (a `setState`, or a
/// [ListenableBuilder] over the editor's text controllers): `canPop` is read
/// at build time.
class DiscardChangesGuard extends StatelessWidget {
  const DiscardChangesGuard({
    super.key,
    required this.dirty,
    required this.child,
  });

  /// Whether leaving now would lose changes.
  final bool dirty;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final choice = await confirmDiscardChanges(context);
        if (choice != DiscardChangesChoice.discard || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: child,
    );
  }
}
