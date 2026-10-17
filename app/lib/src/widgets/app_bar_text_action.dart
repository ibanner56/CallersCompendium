import 'package:flutter/material.dart';

/// An [AppBar] action that reads as its [label] while the label fits, and as
/// [icon], with [label] as its tooltip and screen-reader label, when it
/// doesn't.
///
/// A [TextButton] in [AppBar.actions] keeps its natural width, so a long
/// label at a large text size (French "Enregistrer" at 2× on a 320px phone)
/// overflows the toolbar however short the title is. The label is measured
/// as the button would draw it, at the user's text size, against
/// [maxWidthFraction] of the screen's width; the title, which ellipsizes,
/// keeps the rest.
class AppBarTextAction extends StatelessWidget {
  const AppBarTextAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.maxWidthFraction = 0.4,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// The share of the screen's width the label's button may take.
  final double maxWidthFraction;

  /// A [TextButton]'s horizontal padding, both sides: what the label adds to
  /// its width as a button.
  static const double _buttonPadding = 24;

  @override
  Widget build(BuildContext context) {
    final style =
        TextButtonTheme.of(context).style?.textStyle?.resolve(const {}) ??
        Theme.of(context).textTheme.labelLarge;
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final fits =
        painter.width + _buttonPadding <=
        MediaQuery.sizeOf(context).width * maxWidthFraction;
    painter.dispose();
    if (fits) {
      return TextButton(onPressed: onPressed, child: Text(label));
    }
    return IconButton(onPressed: onPressed, tooltip: label, icon: Icon(icon));
  }
}
