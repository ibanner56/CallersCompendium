import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets both the render surface size and the [MediaQuery] physical size to
/// [size]. `tester.binding.setSurfaceSize` alone only affects layout
/// constraints (what a [LayoutBuilder] would see) — `MediaQuery.sizeOf`,
/// which `ResponsiveAutocomplete` uses for its compact-width/compact-height
/// breakpoints (matching real-device keyboard-obscuring geometry rather than
/// a possibly-unbounded local layout box), reads `FlutterView.physicalSize`
/// instead, so both must be set to faithfully simulate a given screen size
/// in tests. Forgetting either half of this pair produces a test that
/// silently exercises the wrong (usually wide/inline) layout path while
/// still appearing green — the worst failure mode for a responsive-layout
/// feature, since it looks like coverage but proves nothing.
///
/// Registers `addTearDown` calls that reset both the surface size and the
/// physical size, so a modified screen size can never leak into a later,
/// unrelated test in the same file.
Future<void> setScreenSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
}
