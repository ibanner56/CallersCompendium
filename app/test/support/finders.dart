import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The last vertical scrollable in the tree that is on stage: a page's list,
/// not the horizontal scrollable inside each text field (every drop-down's
/// closed field has one). An open drop-down menu, or a list nested inside the
/// page, would come after the page's list; scroll with neither on screen.
Finder verticalScrollable() => find
    .byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          (w.axisDirection == AxisDirection.down ||
              w.axisDirection == AxisDirection.up),
    )
    .last;

/// The advanced query's "Has figure" move field, whatever its figure's id.
Finder hasFigureMoveField() => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> &&
      key.value.startsWith('has-figure-') &&
      key.value.endsWith('-input');
});
