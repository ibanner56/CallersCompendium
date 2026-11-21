import 'package:flutter/material.dart';

/// Keeps a small input dialog open while it holds edits.
///
/// Dialogs built with `showDialog` close on a tap outside, Escape and Back, so a
/// stray tap discards whatever was typed. `barrierDismissible` cannot express
/// "only while the text has changed": it is fixed when the dialog opens. A
/// [PopScope] can, and it also covers Escape and Back.
///
/// While [isDirty] is true, those routes do nothing. The dialog's own Cancel and
/// Save buttons call `Navigator.pop` directly, which a [PopScope] does not
/// intercept, so they still close it. Once the text is back to its starting
/// value the dialog is clean again and closes as usual.
///
/// [listenable] is what [isDirty] reads (usually the text controllers), so the
/// scope re-evaluates on every edit. [blocked] holds the dialog open regardless,
/// for a dialog that has other reasons to stay (a save in flight).
class DirtyDialogGuard extends StatelessWidget {
  const DirtyDialogGuard({
    super.key,
    required this.listenable,
    required this.isDirty,
    this.blocked = false,
    required this.child,
  });

  final Listenable listenable;
  final bool Function() isDirty;
  final bool blocked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) =>
          PopScope(canPop: !blocked && !isDirty(), child: child),
    );
  }
}
