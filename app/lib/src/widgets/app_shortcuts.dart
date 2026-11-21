/// The desktop keyboard map's app-wide intents and bindings (PLAT-7;
/// `docs/user/accessibility.md` "Using the keyboard").
///
/// The root `MaterialApp` binds the keys in [appShortcuts] and supplies the
/// app-wide actions. A screen that owns a command adds its own action nearer
/// the focus: the dance and program editors handle [SaveIntent], and nothing
/// else does, so Ctrl/Cmd-S does nothing outside an editor. Ctrl/Cmd-A works
/// the same way: only the Collection's list handles it. The macOS menu bar
/// (`AppMenuBar`) invokes the same intents, so a menu item and its key always
/// do the same thing.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Saves the open editor. Handled by the dance and program editors only.
class SaveIntent extends Intent {
  const SaveIntent();
}

/// Opens the new-dance editor in the Collection.
class NewDanceIntent extends Intent {
  const NewDanceIntent();
}

/// Starts a dance import in the Collection. Menu bar only: it has no key.
class ImportDancesIntent extends Intent {
  const ImportDancesIntent();
}

/// Focuses the Collection's search box when the Collection is showing, and
/// opens global search everywhere else.
class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

/// Selects every dance in the Collection's current results (N4, `FIND-8`;
/// `docs/design/bulk-selection.md` Q1). Bound here, but handled only by the
/// Collection's result list: the key does nothing when focus is anywhere else,
/// and never reaches a text field, where Ctrl/Cmd-A keeps selecting text.
class SelectAllDancesIntent extends Intent {
  const SelectAllDancesIntent();
}

/// Shows Settings.
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// Shows the User Guide. Menu bar only: it has no key.
class OpenGuideIntent extends Intent {
  const OpenGuideIntent();
}

/// Goes back one step: closes an open menu, sheet or dialog that a tap outside
/// would close, and otherwise leaves the current page as the system back
/// gesture does, so an editor with unsaved changes asks first. Bound to Esc and
/// Ctrl/Cmd-W, and sent by a mouse's Back button.
///
/// Perform binds Esc itself and never lets it through
/// (`ExitPerformFullScreenIntent`), so Esc never leaves Perform. Ctrl/Cmd-W
/// and mouse Back reach this intent there, and Perform's own guard asks
/// before it closes, as it does for the system back gesture.
class GoBackIntent extends Intent {
  const GoBackIntent();
}

/// The keys of the desktop keyboard map. Each command is bound to both Control
/// and Command, as `searchShortcuts` binds Ctrl-K and Cmd-K. In a macOS text
/// field, Ctrl-F and Ctrl-N keep their system meaning (move the cursor),
/// because Flutter's text-editing keys sit nearer the field; Cmd-F and Cmd-N
/// work there.
///
/// Esc replaces Flutter's default `DismissIntent` binding, and the root
/// [GoBackIntent] action passes a dismiss on to whatever is open; see
/// [GoBackIntent].
const Map<ShortcutActivator, Intent> appShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveIntent(),
  SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, control: true): NewDanceIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, meta: true): NewDanceIntent(),
  SingleActivator(LogicalKeyboardKey.keyF, control: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyF, meta: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyA, control: true):
      SelectAllDancesIntent(),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true): SelectAllDancesIntent(),
  SingleActivator(LogicalKeyboardKey.comma, control: true):
      OpenSettingsIntent(),
  SingleActivator(LogicalKeyboardKey.comma, meta: true): OpenSettingsIntent(),
  SingleActivator(LogicalKeyboardKey.escape): GoBackIntent(),
  SingleActivator(LogicalKeyboardKey.keyW, control: true): GoBackIntent(),
  SingleActivator(LogicalKeyboardKey.keyW, meta: true): GoBackIntent(),
};
