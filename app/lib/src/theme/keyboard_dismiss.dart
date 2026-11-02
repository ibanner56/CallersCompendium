import 'package:flutter/material.dart';

/// Keyboard-dismiss behavior for primary text-entry scroll views.
///
/// Dragging a scroll view with a finger or stylus drops focus from the text
/// field, which closes the soft keyboard, matching the native mobile convention
/// (Messages, Gmail, Safari forms). Mouse drags do not scroll, so they never
/// trigger it. It does drop focus on a touch drag even with a hardware keyboard
/// attached, so a scroll view whose own children need the field to keep focus
/// (an autocomplete's suggestion list) must opt out with
/// `ScrollViewKeyboardDismissBehavior.manual`.
///
/// Defined once so the behavior stays consistent. [AppScrollBehavior] applies it
/// to every scrollable by default, so an explicit use is only needed to be
/// unambiguous.
const ScrollViewKeyboardDismissBehavior kTextEntryKeyboardDismiss =
    ScrollViewKeyboardDismissBehavior.onDrag;

/// App-wide scroll behavior: the Material defaults, plus dragging any scroll
/// view dismisses the soft keyboard.
///
/// Scroll views read their default dismiss behavior from the ambient
/// scroll configuration, so installing this as `MaterialApp.scrollBehavior`
/// covers every text-entry field in every screen, dialog and sheet — including
/// ones added later — without each scrollable opting in. A scroll view that
/// passes its own `keyboardDismissBehavior` still wins.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => kTextEntryKeyboardDismiss;
}
