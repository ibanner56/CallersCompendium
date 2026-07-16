import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/widgets/brand_mark.dart';

/// Captures the pixels of a [RepaintBoundary]-wrapped [child] at [size]x[size]
/// (device pixel ratio 1, so widget coordinates == pixel coordinates).
Future<ByteData> _capture(
  WidgetTester tester,
  Widget child,
  double size,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: size, child: child),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });
  return data;
}

({int r, int g, int b, int a}) _pixel(ByteData d, int x, int y, int width) {
  final o = (y * width + x) * 4;
  return (
    r: d.getUint8(o),
    g: d.getUint8(o + 1),
    b: d.getUint8(o + 2),
    a: d.getUint8(o + 3),
  );
}

void main() {
  // In the 128-unit box: left bar center (47, 72); the inter-bar gap at the
  // center (64, 64) is glyph-free; the top-left corner (2, 2) is outside the
  // rounded tile.
  const glyph = Color(0xFF3366CC);

  testWidgets('builds and lays out at a range of sizes', (tester) async {
    for (final size in <double>[16, 24, 48, 96]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: BrandMark(size: size)),
          ),
        ),
      );
      expect(find.byType(BrandMark), findsOneWidget);
      expect(tester.getSize(find.byType(BrandMark)), Size(size, size));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('paints the glyph in the supplied color', (tester) async {
    final data = await _capture(
      tester,
      const BrandMark(size: 128, color: glyph),
      128,
    );

    // Center of the left bar is fully covered -> exactly the glyph color.
    final bar = _pixel(data, 47, 72, 128);
    expect((bar.r, bar.g, bar.b, bar.a), (0x33, 0x66, 0xCC, 0xFF));

    // No tile -> the inter-bar gap is transparent.
    final gap = _pixel(data, 64, 64, 128);
    expect(gap.a, 0);
  });

  testWidgets('showTile paints the petrol tile behind the glyph', (
    tester,
  ) async {
    final data = await _capture(
      tester,
      const BrandMark(size: 128, showTile: true),
      128,
    );

    // Default glyph color on a tile is the brand amber (#FFB784).
    final bar = _pixel(data, 47, 72, 128);
    expect((bar.r, bar.g, bar.b, bar.a), (0xFF, 0xB7, 0x84, 0xFF));

    // The gap between the bars shows the opaque petrol tile (#121A24).
    final gap = _pixel(data, 64, 64, 128);
    expect((gap.r, gap.g, gap.b, gap.a), (0x12, 0x1A, 0x24, 0xFF));

    // The rounded tile clips its corners -> top-left corner is transparent.
    final corner = _pixel(data, 2, 2, 128);
    expect(corner.a, 0);
  });

  testWidgets('is decorative by default and labelled when asked', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark())),
    );
    expect(
      find.descendant(
        of: find.byType(BrandMark),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel("Caller's Compendium"), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BrandMark(semanticLabel: "Caller's Compendium")),
      ),
    );
    expect(find.bySemanticsLabel("Caller's Compendium"), findsOneWidget);
  });
}
