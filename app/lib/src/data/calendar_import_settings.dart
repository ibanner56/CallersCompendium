import 'package:compendium_core/compendium_core.dart';

/// The address of the online calendar feed the calendar import reads (#2352):
/// an `https://` or `webcal://` iCalendar URL. One per device, by the
/// maintainer's decision.
///
/// `deviceLocal` (registry): a private calendar's secret address embeds an
/// access token. It never syncs, is kept out of backup files
/// (`kBackupSettingsDenylist`), is redacted from diagnostics
/// (`collectSensitiveTerms`), and is never put into a message.
const String kCalendarFeedUrlKey = 'calendar_feed_url';

/// How many months ahead a calendar import looks for single events: one of
/// [kCalendarImportWindowChoices]. A preference that travels.
const String kCalendarImportWindowMonthsKey = 'calendar_import_window_months';

/// Only events whose title contains this text are offered, ignoring case.
/// Empty or unset offers every event. A preference that travels.
const String kCalendarImportTitleFilterKey = 'calendar_import_title_filter';

/// The date windows Settings ▸ Program ▸ Calendar offers, in months.
const List<int> kCalendarImportWindowChoices = [3, 6, 12];

/// The date window when none is set.
const int kCalendarImportDefaultWindowMonths = 6;

/// The stored window, or [kCalendarImportDefaultWindowMonths] for anything
/// that is not one of [kCalendarImportWindowChoices].
int calendarImportWindowFromStored(Object? value) =>
    value is int && kCalendarImportWindowChoices.contains(value)
    ? value
    : kCalendarImportDefaultWindowMonths;

/// The calendar import's settings, read together.
class CalendarImportSettings {
  const CalendarImportSettings({
    this.feedUrl,
    this.windowMonths = kCalendarImportDefaultWindowMonths,
    this.titleFilter = '',
  });

  /// Null or blank when no address is set.
  final String? feedUrl;
  final int windowMonths;
  final String titleFilter;

  bool get hasFeed => feedUrl != null && feedUrl!.trim().isNotEmpty;

  static Future<CalendarImportSettings> read(
    SettingsRepository settings,
  ) async {
    final url = await settings.get(kCalendarFeedUrlKey);
    final window = await settings.get(kCalendarImportWindowMonthsKey);
    final filter = await settings.get(kCalendarImportTitleFilterKey);
    return CalendarImportSettings(
      feedUrl: url is String && url.trim().isNotEmpty ? url.trim() : null,
      windowMonths: calendarImportWindowFromStored(window),
      titleFilter: filter is String ? filter : '',
    );
  }
}
