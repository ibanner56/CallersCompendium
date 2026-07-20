import 'package:flutter/widgets.dart';

/// Keyboard-dismiss behavior for primary text-entry scroll views.
///
/// Dragging down over the content dismisses the soft keyboard, matching the
/// native mobile convention (Messages, Gmail, Safari forms). This is a no-op
/// on desktop and when a hardware keyboard is in use — there's no soft keyboard
/// to dismiss and scroll physics, focus, and gesture handling are unchanged —
/// so it is safe to apply unconditionally to text-entry scrollables.
///
/// Defined once so the behavior stays consistent and future screens can opt in
/// without re-deriving the enum at each call site.
const ScrollViewKeyboardDismissBehavior kTextEntryKeyboardDismiss =
    ScrollViewKeyboardDismissBehavior.onDrag;
