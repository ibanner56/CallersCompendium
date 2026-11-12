import 'package:flutter/material.dart';

/// The `selectedItemBuilder` for a dropdown whose items are user-typed text.
///
/// The open menu is as wide as the button, so an item that ellipsizes there
/// can never be read in full. Give the menu items plain wrapping [Text] (and
/// `itemHeight: null` so they may grow), and use this for the closed field,
/// which stays one line tall and ellipsizes. [labels] must be in the same
/// order as the dropdown's items.
List<Widget> Function(BuildContext) ellipsizedSelection(
  Iterable<String> labels,
) {
  final shown = labels.toList(growable: false);
  return (_) => [
    for (final label in shown)
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  ];
}
