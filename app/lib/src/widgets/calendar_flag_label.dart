import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// The words for a program's calendar flag (#2354). An unknown value, from a
/// newer build, reads as a generic flag.
String calendarFlagLabel(AppLocalizations l10n, String? flag) => switch (flag) {
  calendarFlagCancelled => l10n.calendarFlagCancelled,
  calendarFlagMissing => l10n.calendarFlagMissing,
  _ => l10n.calendarFlagOther,
};

/// A program's calendar flag as an icon and text, never colour alone
/// (#2354): "Cancelled in your calendar" or "No longer in your calendar".
/// Renders nothing for an unflagged program.
class CalendarFlagLabel extends StatelessWidget {
  const CalendarFlagLabel({super.key, required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    final flag = program.calendarFlag;
    if (flag == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = calendarFlagLabel(l10n, flag);
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Row(
        key: ValueKey('calendar-flag-${program.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_outlined, size: 16, color: scheme.error),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
