import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';

/// A note under a shorthand-token field, shown while the token typed so far
/// already reads as a figure (issue #1827): shorthands are matched before the
/// parser, so saving it would make typing that word insert the shorthand's
/// figures instead. A warning, not an error: it never blocks saving.
///
/// Rebuilds as [controller] changes; renders nothing while the token is empty
/// or does not read as a figure.
class ShorthandShadowWarning extends StatelessWidget {
  const ShorthandShadowWarning({
    super.key,
    required this.warningKey,
    required this.controller,
    this.taxonomy,
  });

  /// Keys the note itself, which is absent while there is nothing to warn of.
  final Key warningKey;

  final TextEditingController controller;

  /// The taxonomy the token is read against; the shipped one by default.
  final Taxonomy? taxonomy;

  @override
  Widget build(BuildContext context) {
    final dialect = ActiveDialectScope.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final token = value.text.trim();
        if (token.isEmpty ||
            token.length > maxShorthandTokenLength ||
            !shorthandTokenShadowsFigure(
              token,
              taxonomy: taxonomy ?? contraTaxonomy,
              dialect: dialect,
            )) {
          return const SizedBox.shrink();
        }
        return Padding(
          key: warningKey,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.shorthandEditorTokenShadowsFigure(token),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
