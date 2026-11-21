import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keyboard-dismiss behavior for primary text-entry scroll views.
///
/// On Android and iOS, dragging a scroll view drops focus from the text field,
/// which closes the soft keyboard, matching the native mobile convention
/// (Messages, Gmail, Safari forms). It does drop focus on a touch drag even with
/// a hardware keyboard attached, so a scroll view whose own children need the
/// field to keep focus (an autocomplete's suggestion list) must opt out with
/// `ScrollViewKeyboardDismissBehavior.manual`.
///
/// Everywhere else it is `manual`. Flutter counts a trackpad as a drag device,
/// so a two-finger trackpad scroll on a desktop would otherwise unfocus the
/// field being typed in: Quick search's results stop answering the arrow keys
/// and Enter, and a Move box that commits on blur discards what was half typed.
///
/// The rule goes by platform, not by the device that drags, so it is not
/// exact. A trackpad on an iPad or a Chromebook (iOS and Android) still
/// unfocuses the field, and a finger drag on a Windows tablet does not put its
/// touch keyboard away. Telling the devices apart per drag needs a listener
/// that also honours each scroll view's own `keyboardDismissBehavior`, which
/// the autocomplete overlay relies on to keep its field focused.
///
/// [AppScrollBehavior] applies it to every scrollable by default, so an explicit
/// use is only needed to be unambiguous.
ScrollViewKeyboardDismissBehavior textEntryKeyboardDismiss() =>
    switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => ScrollViewKeyboardDismissBehavior.onDrag,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => ScrollViewKeyboardDismissBehavior.manual,
    };

/// App-wide scroll behavior: the Material defaults, plus, on a phone or
/// tablet, dragging any scroll view dismisses the soft keyboard.
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
  ) => textEntryKeyboardDismiss();
}
