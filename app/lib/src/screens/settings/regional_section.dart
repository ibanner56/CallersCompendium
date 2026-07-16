// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';
import '../../data/date_format_scope.dart';
import '../../data/regional_formats.dart';
import '../../data/repositories_scope.dart';
import '../../widgets/section_header.dart';

/// The Language & region settings section: owns the date-format write and
/// reads the live [DateFormatScope].
class RegionalSection extends StatefulWidget {
  const RegionalSection({super.key});

  @override
  State<RegionalSection> createState() => _RegionalSectionState();
}

class _RegionalSectionState extends State<RegionalSection> {
  Future<void> _onDateFormatChanged(DateFormatPref value) async {
    // Instant-notifier-then-persist (ROADMAP G.8): flip the live notifier so
    // on-screen event dates re-render immediately, then persist the token.
    DateFormatScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDateFormatKey, value.token);
  }

  @override
  Widget build(BuildContext context) {
    return _RegionalView(
      dateFormat: DateFormatScope.of(context),
      onDateFormatChanged: _onDateFormatChanged,
    );
  }
}

/// The Language & region section (ROADMAP G.8): regional-format preferences and
/// a home for future regional/localization options.
///
/// Ships the cheap, genuinely-functional piece — how program event dates render
/// (the Date format control) — alongside explicit disabled placeholder rows for
/// options that are not available yet: a first-day-of-week control (Flutter's
/// date pickers can't yet consume a custom first day without a heavy
/// localizations override) and a future UI-language selector.
class _RegionalView extends StatelessWidget {
  const _RegionalView({
    required this.dateFormat,
    required this.onDateFormatChanged,
  });

  final DateFormatPref dateFormat;
  final ValueChanged<DateFormatPref> onDateFormatChanged;

  static String _dateFormatLabel(DateFormatPref pref) {
    switch (pref) {
      case DateFormatPref.system:
        return 'System default';
      case DateFormatPref.ymd:
        return 'Year-month-day (2026-07-15)';
      case DateFormatPref.dmy:
        return 'Day/month/year (15/07/2026)';
      case DateFormatPref.mdy:
        return 'Month/day/year (07/15/2026)';
    }
  }

  @override
  Widget build(BuildContext context) {
    // A live example of how today's date renders in the chosen format, shown as
    // the date-format control's subtitle so the choice is concrete.
    final example = formatEventDate(
      DateTime.now(),
      dateFormat,
      MaterialLocalizations.of(context),
    );
    return ListView(
      children: [
        SectionHeader(title: 'Formats'),
        ListTile(
          title: const Text('Date format'),
          subtitle: Text('How program event dates appear. Example: $example'),
          isThreeLine: true,
          trailing: DropdownButton<DateFormatPref>(
            key: const ValueKey('regional-date-format'),
            value: dateFormat,
            onChanged: (value) {
              if (value != null) onDateFormatChanged(value);
            },
            items: [
              for (final pref in DateFormatPref.values)
                DropdownMenuItem(
                  value: pref,
                  child: Text(_dateFormatLabel(pref)),
                ),
            ],
          ),
        ),
        const ListTile(
          key: ValueKey('regional-first-day-of-week'),
          enabled: false,
          title: Text('First day of week'),
          subtitle: Text(
            'Choose which day the week starts on. Not available yet.',
          ),
          isThreeLine: true,
          trailing: Text('Coming soon'),
        ),
        SectionHeader(title: 'Language'),
        const ListTile(
          key: ValueKey('regional-language-placeholder'),
          enabled: false,
          title: Text('App language'),
          subtitle: Text(
            'Choose the language of the app’s interface. Full localization is '
            'not available yet.',
          ),
          isThreeLine: true,
          trailing: Text('Coming soon'),
        ),
      ],
    );
  }
}
