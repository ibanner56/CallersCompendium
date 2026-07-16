import 'package:flutter/material.dart';

/// The Caller's Compendium brand mark — "Progression bars" (§4.1).
///
/// Two rounded vertical bars stand for the two facing lines of a longways
/// contra set; the right bar is stepped **up** to imply progression up the set.
/// This is a dependency-free [CustomPainter] (no `flutter_svg`) so the in-app
/// reuse points — the navigation rail mark and empty-state mark (§4.3/§4.4) —
/// can draw the same geometry as the launcher icons without pulling in an SVG
/// runtime. The geometry is the canonical 128-unit box documented in
/// `assets/brand/mark.svg`:
///
/// * left bar  — `x38 y44 w18 h56 rx9`
/// * right bar — `x72 y28 w18 h56 rx9`
///
/// By default the glyph is drawn in [ColorScheme.onSurfaceVariant] (the muted
/// mark tint) so it sits quietly in chrome; pass [color] to override. Set
/// [showTile] to also paint the rounded petrol tile, giving the full-color app
/// icon (amber glyph on petrol) for splash / about surfaces.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 24,
    this.color,
    this.showTile = false,
    this.tileColor,
    this.semanticLabel,
  });

  /// Brand petrol tile color — mirrors `@color/ic_launcher_background` and the
  /// dark scheme surface (`#121A24`).
  static const Color brandBackground = Color(0xFF121A24);

  /// Lantern amber — the glyph color on the full-color brand tile (`#FFB784`).
  static const Color brandForeground = Color(0xFFFFB784);

  /// Edge length of the (square) mark, in logical pixels.
  final double size;

  /// Glyph (bars) color. Defaults to [brandForeground] when [showTile] is set,
  /// otherwise the current theme's [ColorScheme.onSurfaceVariant].
  final Color? color;

  /// Whether to paint the rounded petrol tile behind the glyph.
  final bool showTile;

  /// Tile color when [showTile] is set. Defaults to [brandBackground].
  final Color? tileColor;

  /// Optional accessibility label. When null the mark is treated as decorative
  /// and excluded from the semantics tree.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyphColor =
        color ?? (showTile ? brandForeground : scheme.onSurfaceVariant);
    final tile = showTile ? (tileColor ?? brandBackground) : null;

    final Widget painted = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BrandMarkPainter(glyphColor: glyphColor, tileColor: tile),
      ),
    );

    if (semanticLabel == null) {
      return ExcludeSemantics(child: painted);
    }
    return Semantics(label: semanticLabel, image: true, child: painted);
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({required this.glyphColor, this.tileColor});

  final Color glyphColor;
  final Color? tileColor;

  // Canonical geometry in a 128-unit box (see assets/brand/mark.svg).
  static const double _unit = 128;
  static const Rect _leftBar = Rect.fromLTWH(38, 44, 18, 56);
  static const Rect _rightBar = Rect.fromLTWH(72, 28, 18, 56);
  static const Radius _barRadius = Radius.circular(9);
  static const Radius _tileRadius = Radius.circular(28.4);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _unit;
    if (scale <= 0) return;

    canvas.save();
    // Center the square glyph if the paint area is not square.
    canvas.translate(
      (size.width - _unit * scale) / 2,
      (size.height - _unit * scale) / 2,
    );
    canvas.scale(scale);

    if (tileColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, _unit, _unit),
          _tileRadius,
        ),
        Paint()..color = tileColor!,
      );
    }

    final glyphPaint = Paint()..color = glyphColor;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(_leftBar, _barRadius), glyphPaint)
      ..drawRRect(RRect.fromRectAndRadius(_rightBar, _barRadius), glyphPaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.glyphColor != glyphColor ||
      oldDelegate.tileColor != tileColor;
}
