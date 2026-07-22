// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:flutter/material.dart';
import '../../data/date_format_scope.dart';
import '../../data/first_day_of_week_scope.dart';
import '../../data/locale_scope.dart';
import '../../data/regional_formats.dart';
import '../../data/repositories_scope.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/section_header.dart';

/// The Language & region settings section (ROADMAP G.8): the app-language
/// selector plus regional-format preferences (date format, first day of week).
///
/// Owns the writes for all three controls and reads their live scopes so the UI
/// (and the rest of the app) re-renders immediately when a value changes.
class RegionalSection extends StatefulWidget {
  const RegionalSection({super.key});

  @override
  State<RegionalSection> createState() => _RegionalSectionState();
}

class _RegionalSectionState extends State<RegionalSection> {
  // Instant-notifier-then-persist: flip the live notifier so dependent UI
  // re-renders immediately, then persist the stable token/tag.
  Future<void> _onDateFormatChanged(DateFormatPref value) async {
    DateFormatScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDateFormatKey, value.token);
  }

  Future<void> _onFirstDayOfWeekChanged(FirstDayOfWeekPref value) async {
    FirstDayOfWeekScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kFirstDayOfWeekKey, value.token);
  }

  Future<void> _onLocaleChanged(Locale? value) async {
    // Changing the locale notifier drives MaterialApp.locale, so the whole app
    // re-renders in the selected language live.
    LocaleScope.notifierOf(context).value = value;
    final repos = RepositoriesScope.of(context);
    // Persist the BCP-47 tag; empty string means "follow system" and is
    // validated back to null on load (see localeFromStored).
    await repos.settings.set(kLocaleKey, localeToTag(value));
  }

  @override
  Widget build(BuildContext context) {
    return _RegionalView(
      dateFormat: DateFormatScope.of(context),
      firstDayOfWeek: FirstDayOfWeekScope.of(context),
      locale: LocaleScope.of(context),
      onDateFormatChanged: _onDateFormatChanged,
      onFirstDayOfWeekChanged: _onFirstDayOfWeekChanged,
      onLocaleChanged: _onLocaleChanged,
    );
  }
}

/// The Language & region section's presentational body (ROADMAP G.8).
///
/// Ships three live controls: the app-language selector, the date-format
/// preference (how program event dates render), and the first-day-of-week
/// preference. All strings come from [AppLocalizations] — this section is the
/// extraction proof for the i18n foundation (PR 1).
class _RegionalView extends StatelessWidget {
  const _RegionalView({
    required this.dateFormat,
    required this.firstDayOfWeek,
    required this.locale,
    required this.onDateFormatChanged,
    required this.onFirstDayOfWeekChanged,
    required this.onLocaleChanged,
  });

  final DateFormatPref dateFormat;
  final FirstDayOfWeekPref firstDayOfWeek;
  final Locale? locale;
  final ValueChanged<DateFormatPref> onDateFormatChanged;
  final ValueChanged<FirstDayOfWeekPref> onFirstDayOfWeekChanged;
  final ValueChanged<Locale?> onLocaleChanged;

  static String _dateFormatLabel(AppLocalizations l10n, DateFormatPref pref) {
    switch (pref) {
      case DateFormatPref.system:
        return l10n.commonSystemDefault;
      case DateFormatPref.ymd:
        return l10n.settingsDateFormatYmd;
      case DateFormatPref.dmy:
        return l10n.settingsDateFormatDmy;
      case DateFormatPref.mdy:
        return l10n.settingsDateFormatMdy;
    }
  }

  static String _firstDayLabel(AppLocalizations l10n, FirstDayOfWeekPref pref) {
    switch (pref) {
      case FirstDayOfWeekPref.system:
        return l10n.commonSystemDefault;
      case FirstDayOfWeekPref.sunday:
        return l10n.settingsFirstDayOfWeekSunday;
      case FirstDayOfWeekPref.monday:
        return l10n.settingsFirstDayOfWeekMonday;
      case FirstDayOfWeekPref.saturday:
        return l10n.settingsFirstDayOfWeekSaturday;
    }
  }

  static String _languageLabel(AppLocalizations l10n, Locale? locale) =>
      locale == null ? l10n.commonSystemDefault : nativeLanguageName(locale);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A live example of how today's date renders in the chosen format, shown as
    // the date-format control's subtitle so the choice is concrete.
    final example = formatEventDate(
      DateTime.now(),
      dateFormat,
      MaterialLocalizations.of(context),
    );
    // System default + every locale the app ships a translation for. Dropping a
    // new app_<locale>.arb into lib/l10n/ adds it here with no code change.
    final localeOptions = <Locale?>[null, ...AppLocalizations.supportedLocales];
    return ListView(
      children: [
        SectionHeader(title: l10n.settingsRegionalLanguageHeader),
        ListTile(
          title: Text(l10n.settingsAppLanguageTitle),
          subtitle: Text(l10n.settingsAppLanguageSubtitle),
          isThreeLine: true,
          trailing: DropdownButton<Locale?>(
            key: const ValueKey('regional-language'),
            value: locale,
            // A null value (System default) is not matched to the null-valued
            // menu item by DropdownButton — it renders the hint instead — so the
            // hint carries the localized "System default" label for the closed
            // button on first load and after choosing System default.
            hint: Text(l10n.commonSystemDefault),
            onChanged: onLocaleChanged,
            items: [
              for (final option in localeOptions)
                DropdownMenuItem<Locale?>(
                  value: option,
                  child: Text(_languageLabel(l10n, option)),
                ),
            ],
          ),
        ),
        SectionHeader(title: l10n.settingsRegionalFormatsHeader),
        ListTile(
          title: Text(l10n.settingsDateFormatTitle),
          subtitle: Text(l10n.settingsDateFormatSubtitle(example)),
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
                  child: Text(_dateFormatLabel(l10n, pref)),
                ),
            ],
          ),
        ),
        ListTile(
          title: Text(l10n.settingsFirstDayOfWeekTitle),
          subtitle: Text(l10n.settingsFirstDayOfWeekSubtitle),
          isThreeLine: true,
          trailing: DropdownButton<FirstDayOfWeekPref>(
            key: const ValueKey('regional-first-day-of-week'),
            value: firstDayOfWeek,
            onChanged: (value) {
              if (value != null) onFirstDayOfWeekChanged(value);
            },
            items: [
              for (final pref in FirstDayOfWeekPref.values)
                DropdownMenuItem(
                  value: pref,
                  child: Text(_firstDayLabel(l10n, pref)),
                ),
            ],
          ),
        ),
        // Documents the platform limitation (ROADMAP G.8): showDatePicker takes
        // its first day of week from the locale and can't be overridden.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            l10n.settingsFirstDayOfWeekPickerNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
