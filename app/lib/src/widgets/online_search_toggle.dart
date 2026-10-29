import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The Online search icon, on the toggle beside the search tools and on the
/// search box while online, so the two read as one control. Shared by the
/// Collection and the collection picker so they cannot drift apart.
const IconData kOnlineSearchIcon = Icons.travel_explore;

/// The Online search switch: an icon at the end of a [SearchPanelBar]'s row
/// rather than a labelled switch, so the row stays one line. Its help text is
/// the tooltip (hover or long-press); screen readers get the name, the on/off
/// state and the help as a hint, and the tooltip itself is kept out of
/// semantics so it is not read twice.
class OnlineSearchToggle extends StatelessWidget {
  const OnlineSearchToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// Whether online search is on.
  final bool enabled;

  /// Called with the new state; null disables the control (an import is in
  /// flight).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final callback = onChanged;
    return Tooltip(
      message: l10n.onlineSearchToggleSubtitle,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        toggled: enabled,
        enabled: callback != null,
        label: l10n.onlineSearchToggleTitle,
        hint: l10n.onlineSearchToggleSubtitle,
        // excludeSemantics drops the button's own tap action, so say it here.
        onTap: callback == null ? null : () => callback(!enabled),
        excludeSemantics: true,
        child: IconButton(
          isSelected: enabled,
          icon: const Icon(kOnlineSearchIcon),
          // Compact, so it adds 40dp rather than 48 to a row that must still
          // hold Filters, By phrase and Advanced on a phone.
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            // Filled like an open tool's chip while online mode is on.
            backgroundColor: enabled ? scheme.secondaryContainer : null,
            foregroundColor: enabled ? scheme.onSecondaryContainer : null,
          ),
          onPressed: callback == null ? null : () => callback(!enabled),
        ),
      ),
    );
  }
}
