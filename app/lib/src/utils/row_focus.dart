import 'package:flutter/material.dart';

/// Whether a keyboard user's focus has been dropped, or is about to be: the app
/// is in keyboard navigation mode and nothing lasting holds focus.
///
/// Removing the focused widget from the tree (a deleted list row, with the ⋮
/// button inside it) leaves the primary focus on a detached node or on a scope
/// itself, from where the next Tab restarts at the top of the page. Focus that
/// sits on a live, traversable widget is never "lost", so a caller can use this
/// to avoid stealing it from wherever the user has since moved it.
bool keyboardFocusIsLost() {
  // A touch or stylus user has nothing focused as a matter of course, and
  // moving focus for them would raise a soft keyboard or announce a button
  // nobody was on, so only keyboard navigation mode counts. This does not
  // exclude a desktop mouse user: Flutter leaves the mode alone on mouse input,
  // and desktop starts in `traditional`, so for them the move still happens
  // (a focus ring on the next row's ⋮ button, harmless, and the same place a
  // keyboard user needs).
  if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
    return false;
  }
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || focus is FocusScopeNode) return true;
  final context = focus.context;
  if (context == null || !context.mounted) return true;
  // Focus on a snackbar's action (Undo) is about to be dropped too: pressing
  // it dismisses the snackbar, which disposes the button a frame or so later.
  return context.findAncestorWidgetOfExactType<SnackBar>() != null;
}

/// Moves focus to the first of [candidateKeys] that names a built row's ⋮
/// button under [scope], else to [fallback], but only if focus is lost
/// ([keyboardFocusIsLost]) and [scope]'s route is the current one.
///
/// Rows of a lazy list that are not built have no element and are skipped, so
/// pass candidates nearest-first. Returns whether focus was moved.
bool restoreFocusToRowMenu(
  BuildContext scope, {
  required List<Key> candidateKeys,
  FocusNode? fallback,
}) {
  if (!scope.mounted || !keyboardFocusIsLost()) return false;
  if (ModalRoute.of(scope)?.isCurrent == false) return false;
  for (final key in candidateKeys) {
    final node = _focusNodeUnder(scope, key);
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
      return true;
    }
  }
  if (fallback != null && fallback.canRequestFocus) {
    fallback.requestFocus();
    return true;
  }
  return false;
}

/// The focus node of the innermost focusable widget inside the widget keyed
/// [key], if one is built below [scope].
FocusNode? _focusNodeUnder(BuildContext scope, Key key) {
  Element? found;
  void search(Element element) {
    if (found != null) return;
    if (element.widget.key == key) {
      found = element;
      return;
    }
    element.visitChildren(search);
  }

  (scope as Element).visitChildren(search);
  final root = found;
  if (root == null) return null;
  // A button's subtree is a single chain, so the first-child walk reaches its
  // leaf; the nearest Focus above that leaf is the button's own node.
  Element leaf = root;
  while (true) {
    Element? child;
    leaf.visitChildren((e) => child ??= e);
    if (child == null) break;
    leaf = child!;
  }
  return Focus.maybeOf(leaf);
}
