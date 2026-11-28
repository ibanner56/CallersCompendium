import 'dart:async';

import 'package:flutter/material.dart';

import '../data/reduce_motion_scope.dart';
import '../theme/app_motion.dart';

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
      duration: reduceMotion ? Duration.zero : AppMotion.short,
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
          duration: AppMotion.short,
          curve: Curves.easeOut,
        ),
      );
    }
  });
}

/// Scrolls the first field of the [Form] keyed by [formKey] that shows a
/// validation error into view, once the frame that shows its message has been
/// built.
///
/// `FormState.validate` puts each message on its own field and scrolls
/// nothing, so a message on a field above or below the fold goes unseen. Call
/// this right after a failed `validate()`. "First" is in the order the page
/// reads. Only a field that is built can be found: a field a lazy list has not
/// built is not validated either, so it has no message to show. It does
/// nothing when no field has one.
void scrollToFirstInvalidField(
  BuildContext context,
  GlobalKey<FormState> formKey,
) {
  final reduceMotion = ReduceMotionScope.of(context);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final formContext = formKey.currentContext;
    if (formContext == null || !formContext.mounted) return;
    BuildContext? firstInvalid;
    void visit(Element element) {
      if (firstInvalid != null) return;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is FormFieldState && state.hasError) {
          firstInvalid = element;
          return;
        }
      }
      element.visitChildren(visit);
    }

    (formContext as Element).visitChildren(visit);
    final target = firstInvalid;
    if (target == null || !target.mounted) return;
    Scrollable.ensureVisible(
      target,
      duration: reduceMotion ? Duration.zero : AppMotion.short,
      alignment: 0.1,
    );
  });
}

/// Whether a field under the widget keyed by [key], inside the [Form] keyed by
/// [formKey], shows a validation error. A page that folds fields away (an
/// expansion panel kept mounted while collapsed) asks this after a failed
/// `validate()` to open the panel holding the error, which
/// [scrollToFirstInvalidField] cannot bring into view while it is folded.
bool hasInvalidFieldUnder(GlobalKey<FormState> formKey, Key key) {
  final formContext = formKey.currentContext;
  if (formContext == null) return false;
  var found = false;
  void visitField(Element element) {
    if (found) return;
    if (element is StatefulElement &&
        element.state is FormFieldState &&
        (element.state as FormFieldState).hasError) {
      found = true;
      return;
    }
    element.visitChildren(visitField);
  }

  void visit(Element element) {
    if (found) return;
    if (element.widget.key == key) {
      visitField(element);
      return;
    }
    element.visitChildren(visit);
  }

  (formContext as Element).visitChildren(visit);
  return found;
}

/// Whether a widget keyed by [key] is built inside the [Form] keyed by
/// [formKey]. A lazy list lets go of an item scrolled far enough away, and
/// with it the fields it holds: `validate()` then cannot ask them, so a page
/// asks this first and brings the item back before validating.
bool isBuiltUnder(GlobalKey<FormState> formKey, Key key) {
  final formContext = formKey.currentContext;
  if (formContext == null) return false;
  var found = false;
  void visit(Element element) {
    if (found) return;
    if (element.widget.key == key) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  (formContext as Element).visitChildren(visit);
  return found;
}
