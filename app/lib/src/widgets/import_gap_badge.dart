import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    final resolvedSize =
        size ??
        MediaQuery.textScalerOf(
          context,
        ).scale(theme.textTheme.bodyLarge?.fontSize ?? 16).clamp(16.0, 24.0);
    return Semantics(
      button: true,
      label: l10n.importGapSemanticLabel,
      child: Tooltip(
        message: l10n.importGapMessage,
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

  Future<void> _showExplanation(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.report_gmailerrorred,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        title: Text(l10n.importGapDialogTitle),
        content: Text(l10n.importGapMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
  }
}
