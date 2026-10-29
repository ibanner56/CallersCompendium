import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The widest a reading column is allowed to get, in logical pixels, including
/// its own gutters. Dance detail, the dance editor form, the Settings content
/// pane and the user guide's text stop growing here, so a wide desktop window
/// does not strand a figure's beats at the far edge from its words.
///
/// This is the single place the width is chosen. 760 is the width the dance
/// detail wireframe draws; the maintainer has not ruled on the number.
const double kReadableContentWidth = 760;

/// [base] with its horizontal insets raised so that, in a viewport
/// [viewportWidth] wide, the content between them is at most
/// [kReadableContentWidth] wide and centred.
///
/// The extra room becomes padding *inside* the scrollable rather than a
/// `Center`/`ConstrainedBox` around it, so the scrollbar and the scroll area
/// stay at the window edge. Insets never shrink below [base], so a narrow
/// viewport is laid out exactly as before.
EdgeInsets readableContentPadding(
  double viewportWidth, [
  EdgeInsets base = EdgeInsets.zero,
]) {
  final inset = math.max(0.0, (viewportWidth - kReadableContentWidth) / 2);
  return base.copyWith(
    left: math.max(base.left, inset),
    right: math.max(base.right, inset),
  );
}

/// A [ListView] whose content column is capped at [kReadableContentWidth].
/// Use it in place of `ListView(...)` for text-and-controls screens.
class ReadableListView extends StatelessWidget {
  const ReadableListView({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    super.key,
  });

  final List<Widget> children;

  /// The padding the list would have had uncapped; see
  /// [readableContentPadding].
  final EdgeInsets padding;

  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        keyboardDismissBehavior: keyboardDismissBehavior,
        padding: readableContentPadding(constraints.maxWidth, padding),
        children: children,
      ),
    );
  }
}

/// A [SingleChildScrollView] whose content column is capped at
/// [kReadableContentWidth]; the counterpart of [ReadableListView] for a single
/// long child such as rendered Markdown.
class ReadableScrollView extends StatelessWidget {
  const ReadableScrollView({
    required this.child,
    this.controller,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final ScrollController? controller;

  /// The padding the view would have had uncapped; see
  /// [readableContentPadding].
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: controller,
        padding: readableContentPadding(constraints.maxWidth, padding),
        child: child,
      ),
    );
  }
}
