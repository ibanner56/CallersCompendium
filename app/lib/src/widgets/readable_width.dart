import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The widest a reading column is allowed to get, in logical pixels, including
/// its own gutters. Dance detail, the dance editor form, the Settings content
/// pane and the user guide's text stop growing here, so a wide desktop window
/// does not strand a figure's beats at the far edge from its words.
///
/// This is the single place the width is chosen. 760 is the width the dance
/// detail wireframe draws (`docs/design/wireframes/2-dance-detail.svg`).
const double kReadableContentWidth = 760;

/// Where a readable column sits when its viewport is wider than
/// [kReadableContentWidth].
enum ReadableColumnAlignment {
  /// Equal surplus on both sides, so the column reads as a centred page. The
  /// default, and what a screen of its own wants.
  centre,

  /// The column starts at the leading edge and the surplus stays on the far
  /// side. For a pane beside a navigation column — the Settings content pane
  /// next to its section list — where centring strands the content across the
  /// window from the list that selects it.
  start,
}

/// Declares the [ReadableColumnAlignment] for the readable columns below it.
///
/// A [ReadableListView] or [ReadableScrollView] with no scope above it centres
/// its column. A shell that puts a readable pane beside a navigation column
/// wraps the pane in a scope aligned to [ReadableColumnAlignment.start], so the
/// navigation and the content read as one column at desktop width without
/// every section widget having to thread the choice through.
class ReadableColumnScope extends InheritedWidget {
  const ReadableColumnScope({
    required this.alignment,
    required super.child,
    super.key,
  });

  final ReadableColumnAlignment alignment;

  /// The ambient alignment: [ReadableColumnAlignment.centre] when no
  /// [ReadableColumnScope] is above [context].
  static ReadableColumnAlignment of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReadableColumnScope>()
          ?.alignment ??
      ReadableColumnAlignment.centre;

  @override
  bool updateShouldNotify(ReadableColumnScope oldWidget) =>
      oldWidget.alignment != alignment;
}

/// [base] with its horizontal insets raised so that, in a viewport
/// [viewportWidth] wide, the content between them is at most
/// [kReadableContentWidth] wide and placed according to [alignment].
///
/// The extra room becomes padding *inside* the scrollable rather than a
/// `Center`/`ConstrainedBox` around it, so the scrollbar and the scroll area
/// stay at the window edge. Insets never shrink below [base], so a narrow
/// viewport is laid out exactly as before.
EdgeInsets readableContentPadding(
  double viewportWidth, [
  EdgeInsets base = EdgeInsets.zero,
  ReadableColumnAlignment alignment = ReadableColumnAlignment.centre,
]) {
  if (!viewportWidth.isFinite) return base;
  final surplus = math.max(0.0, viewportWidth - kReadableContentWidth);
  return switch (alignment) {
    ReadableColumnAlignment.centre => base.copyWith(
      left: math.max(base.left, surplus / 2),
      right: math.max(base.right, surplus / 2),
    ),
    ReadableColumnAlignment.start => base.copyWith(
      // Everything the base gutter does not use stays to the trailing side,
      // which keeps the column's own width at the cap.
      right: math.max(
        base.right,
        viewportWidth - kReadableContentWidth - base.left,
      ),
    ),
  };
}

/// A [ListView] whose content column is capped at [kReadableContentWidth].
/// Use it in place of `ListView(...)` for text-and-controls screens.
///
/// The column is centred unless a [ReadableColumnScope] above it says otherwise.
class ReadableListView extends StatelessWidget {
  const ReadableListView({
    required this.children,
    this.padding,
    this.keyboardDismissBehavior,
    this.controller,
    super.key,
  });

  final List<Widget> children;

  /// Drives the list's scroll position, for a screen that scrolls it itself.
  /// When null, as for a [ListView] given no controller: the ambient
  /// primary scroll controller where the platform inherits one (mobile by
  /// default), otherwise the list's own.
  final ScrollController? controller;

  /// The padding the list would have had uncapped; see
  /// [readableContentPadding]. When null, the safe-area insets above and below
  /// apply, as they do to a [ListView] given no padding.
  final EdgeInsets? padding;

  /// When null, the ambient scroll configuration decides (see
  /// `AppScrollBehavior`).
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        controller: controller,
        keyboardDismissBehavior: keyboardDismissBehavior,
        padding: readableContentPadding(
          constraints.maxWidth,
          padding ?? MediaQuery.paddingOf(context).copyWith(left: 0, right: 0),
          ReadableColumnScope.of(context),
        ),
        children: children,
      ),
    );
  }
}

/// A [SingleChildScrollView] whose content column is capped at
/// [kReadableContentWidth]; the counterpart of [ReadableListView] for a single
/// long child such as rendered Markdown.
///
/// The column is centred unless a [ReadableColumnScope] above it says otherwise.
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
        padding: readableContentPadding(
          constraints.maxWidth,
          padding,
          ReadableColumnScope.of(context),
        ),
        child: child,
      ),
    );
  }
}
