import 'package:flutter/material.dart';

/// User-facing explanation of a parser-gap custom figure, shared by the badge's
/// tooltip (desktop hover), dialog (mobile tap), and Semantics label so screen
/// readers, high-contrast users, and sighted users all get the same message.
const String importGapMessage =
    "Couldn't parse this call — kept verbatim as a custom figure.";

/// Accessible affordance flagging a figure that an import parser could not map
/// to a structured move and kept verbatim (a [CustomOrigin.importGap] custom).
///
/// The signal is **not color-only**: it is a distinct glyph carrying a
/// [Semantics] label, so it survives for screen-reader and high-contrast users
/// even when the accompanying row shading is imperceptible. Desktop shows the
/// explanation on hover (via [Tooltip]); mobile shows it in a dialog on tap.
/// The tap is handled by this widget's own gesture target so it never hijacks
/// the surrounding row's primary tap interaction.
class ImportGapBadge extends StatelessWidget {
  const ImportGapBadge({super.key, this.size});

  /// Optional glyph size; defaults to the ambient body font size, clamped.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedSize =
        size ??
        MediaQuery.textScalerOf(
          context,
        ).scale(theme.textTheme.bodyLarge?.fontSize ?? 16).clamp(16.0, 24.0);
    return Semantics(
      button: true,
      label: 'Unparsed import. $importGapMessage',
      child: Tooltip(
        message: importGapMessage,
        child: InkResponse(
          radius: resolvedSize,
          onTap: () => _showExplanation(context),
          child: Icon(
            Icons.report_gmailerrorred,
            size: resolvedSize,
            color: theme.colorScheme.tertiary,
          ),
        ),
      ),
    );
  }

  Future<void> _showExplanation(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.report_gmailerrorred,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      title: const Text('Custom figure from import'),
      content: const Text(importGapMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
