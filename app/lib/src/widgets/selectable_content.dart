import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Makes the text under [child] selectable and copyable with a pointer, on
/// desktop only (design note N5, `docs/design/selectable-text.md`).
///
/// On Windows, macOS and Linux the child is wrapped in a [SelectionArea], so a
/// drag selects, Ctrl/Cmd-C copies, Ctrl/Cmd-A selects all, and a secondary tap
/// shows the Copy / Select all menu. On Android, iOS and Fuchsia the child is
/// returned unchanged: phones keep **Copy dance** as their only copy path
/// (maintainer decision N5-1 = a).
///
/// This is the one place the platform gate lives, so turning selection on for
/// phones later is a change to [selectionEnabledOnThisPlatform] alone.
///
/// A copy is what the screen shows (N5-3 = a): the active dialect, the verbose
/// text and capitalisation preferences. It differs from **Copy dance** on those
/// two preferences.
///
/// Wrap a subtree that is not text — chips, badges, the beats column — in
/// [SelectionContainer.disabled] so a drag over it neither selects it nor puts
/// it in the copied text.
class SelectableContent extends StatelessWidget {
  const SelectableContent({super.key, required this.child});

  final Widget child;

  /// Whether text selection is offered on the running platform.
  @visibleForTesting
  static bool get selectionEnabledOnThisPlatform =>
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => false,
      };

  @override
  Widget build(BuildContext context) {
    if (!selectionEnabledOnThisPlatform) return child;
    return SelectionArea(child: child);
  }
}
