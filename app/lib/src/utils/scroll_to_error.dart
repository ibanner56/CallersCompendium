import 'dart:async';

import 'package:flutter/material.dart';

import '../data/reduce_motion_scope.dart';

/// Scrolls the nearest [Scrollable] so the widget keyed by [target] is on
/// screen, once the frame that shows it has been built.
///
/// An error written into a long scrolled page is invisible when it lands above
/// or below the fold, and nothing in the framework brings it into view:
/// `FormState.validate` only rebuilds the fields. Call this right after the
/// `setState` that adds the error. It does nothing when [target] is not built
/// (the error was cleared again, or a lazy list has not built it) and jumps
/// instead of animating under "Reduce motion".
void scrollToError(BuildContext context, GlobalKey target) {
  final reduceMotion = ReduceMotionScope.of(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final targetContext = target.currentContext;
    if (targetContext == null || !targetContext.mounted) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      alignment: 0.1,
    );
  });
}

/// Scrolls [controller] back to the top, for an error on the first field of a
/// page whose lazily built list may no longer hold that field once the person
/// has scrolled away (see [scrollToError], which needs the target built).
void scrollToTopForError(BuildContext context, ScrollController controller) {
  final reduceMotion = ReduceMotionScope.of(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    final top = controller.position.minScrollExtent;
    if (reduceMotion) {
      controller.jumpTo(top);
    } else {
      unawaited(
        controller.animateTo(
          top,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }
  });
}
