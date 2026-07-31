import 'package:flutter/material.dart';

import '../data/first_day_of_week_scope.dart';
import '../data/regional_formats.dart';

/// A "this week" header strip — the first real consumer of the
/// first-day-of-week preference (ROADMAP G.8): seven day cells for the
/// current week, column-ordered starting at the active
/// [FirstDayOfWeekScope] preference (falling back to the platform locale for
/// [FirstDayOfWeekPref.system] via [orderedWeekdays]). Today's cell is
/// highlighted; any date in [markedDates] shows a small dot — used by callers
/// to surface which days this week have content (e.g. a program event date).
///
/// Purely presentational: the displayed week always centers on [now]
/// (defaults to [DateTime.now()]; overridable so tests don't depend on the
/// wall clock), and reading [FirstDayOfWeekScope.of] registers a rebuild
/// dependency, so this strip reorders live the moment the Settings control
/// changes the preference — no separate wiring needed.
class WeekdayHeaderStrip extends StatelessWidget {
  const WeekdayHeaderStrip({super.key, this.markedDates = const {}, this.now});

  /// Calendar dates (day-precision; time-of-day is ignored) that should show a
  /// marker dot.
  final Set<DateTime> markedDates;

  /// Overrides "today" for the displayed week. Defaults to [DateTime.now()].
  final DateTime? now;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final pref = FirstDayOfWeekScope.of(context);
    final order = orderedWeekdays(pref, material);
    final today = _dateOnly(now ?? DateTime.now());
    // Walk back from today to this ordered week's first day. DateTime weekday
    // is Mon=1…Sun=7; mod 7 keeps the offset in [0, 6] regardless of which
    // weekday `order.first` is.
    final firstOfWeek = today.subtract(
      Duration(days: (today.weekday - order.first) % 7),
    );

    return Row(
      key: const ValueKey('weekday-header-strip'),
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _DayCell(
              // narrowWeekdays is Sunday-first (index 0); DateTime.sunday is 7,
              // so `% 7` maps Mon..Sat (1..6) to themselves and Sun (7) to 0.
              label: material.narrowWeekdays[order[i] % 7],
              date: firstOfWeek.add(Duration(days: i)),
              isToday: _isSameDay(firstOfWeek.add(Duration(days: i)), today),
              isMarked: markedDates.any(
                (d) => _isSameDay(d, firstOfWeek.add(Duration(days: i))),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.label,
    required this.date,
    required this.isToday,
    required this.isMarked,
  });

  final String label;
  final DateTime date;
  final bool isToday;
  final bool isMarked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isToday
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                )
              : null,
          child: Text(
            '${date.day}',
            style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 6,
          width: 6,
          child: isMarked
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
