import 'package:compendium_app/src/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SvgPicture svgOf(WidgetTester tester) => tester.widget<SvgPicture>(
        find.descendant(
          of: find.byType(BrandMark),
          matching: find.byType(SvgPicture),
        ),
      );

  testWidgets('builds and lays out at a range of sizes', (tester) async {
    for (final size in <double>[16, 24, 48, 96]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: BrandMark(size: size))),
        ),
      );
      expect(find.byType(BrandMark), findsOneWidget);
      expect(tester.getSize(find.byType(BrandMark)), Size(size, size));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('default (no tile) tints the mark silhouette', (tester) async {
    const glyph = Color(0xFF3366CC);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BrandMark(size: 128, color: glyph)),
      ),
    );
    final svg = svgOf(tester);
    expect(svg.colorFilter, const ColorFilter.mode(glyph, BlendMode.srcIn));
  });

  testWidgets('showTile renders the full-colour tile (no tint)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BrandMark(size: 128, showTile: true)),
      ),
    );
    // The full-colour illustration is drawn as-authored -> no colour filter.
    expect(svgOf(tester).colorFilter, isNull);
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
