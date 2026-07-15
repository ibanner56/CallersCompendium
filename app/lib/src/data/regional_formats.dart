/// App-only regional-format preferences (ROADMAP G.8).
///
/// Ahead of full app i18n (which we do NOT ship here), this exposes the cheap,
/// genuinely-useful regional pieces: how program event dates render and which
/// day the week starts on. Both are persisted via `SettingsRepository` as
/// stable string tokens.
///
/// The keys, enums, and resolvers below are Flutter-free pure functions so they
/// can be unit-tested directly. Only [formatEventDate] touches Flutter, and only
/// for the `system` default, where it defers to [MaterialLocalizations].
library;

import 'package:flutter/material.dart' show MaterialLocalizations;


/// Key used to persist the program-event-date format preference (ROADMAP G.8).
///
/// Stored as a stable string token: one of `system` (the default),
/// `ymd`, `dmy`, or `mdy`. Absent/unset or an unrecognized value ⇒ [DateFormatPref.system].
const String kDateFormatKey = 'date_format';

/// How program event dates render on screen.
enum DateFormatPref {
  /// Defer to the platform locale via [MaterialLocalizations.formatMediumDate].
  system('system'),

  /// ISO-like year-month-day, e.g. `2026-07-15`.
  ymd('ymd'),

  /// Day/month/year, e.g. `15/07/2026`.
  dmy('dmy'),

  /// Month/day/year, e.g. `07/15/2026`.
  mdy('mdy');

  const DateFormatPref(this.token);

  /// The stable token persisted via `SettingsRepository`.
  final String token;
}

/// Resolves a persisted settings value into a [DateFormatPref].
///
/// Defensive by design: `null`, a non-string, or an unrecognized token all fall
/// back to [DateFormatPref.system], so a corrupted stored value can never leave
/// dates rendering in an unexpected fixed pattern.
DateFormatPref dateFormatPrefFromStored(Object? stored) {
  if (stored is String) {
    for (final pref in DateFormatPref.values) {
      if (pref.token == stored) return pref;
    }
  }
  return DateFormatPref.system;
}

/// Formats a program event [date] for on-screen display per [pref].
///
/// For [DateFormatPref.system] this defers to the platform locale via
/// [l10n] (`formatMediumDate`). For the fixed tokens it uses a dependency-free
/// zero-padded pattern (no `intl`): `ymd` ⇒ `2026-07-15`, `dmy` ⇒ `15/07/2026`,
/// `mdy` ⇒ `07/15/2026`.
String formatEventDate(
  DateTime date,
  DateFormatPref pref,
  MaterialLocalizations l10n,
) {
  final fixed = formatDatePattern(date, pref);
  return fixed ?? l10n.formatMediumDate(date);
}

/// Returns the fixed zero-padded pattern for [date] under [pref], or `null` for
/// [DateFormatPref.system] (which has no fixed pattern and defers to the
/// platform locale). Pure and Flutter-free so the fixed branches are directly
/// unit-testable without a [MaterialLocalizations].
String? formatDatePattern(DateTime date, DateFormatPref pref) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  switch (pref) {
    case DateFormatPref.system:
      return null;
    case DateFormatPref.ymd:
      return '$y-$m-$d';
    case DateFormatPref.dmy:
      return '$d/$m/$y';
    case DateFormatPref.mdy:
      return '$m/$d/$y';
  }
}

/// Key used to persist the first-day-of-week preference (ROADMAP G.8).
///
/// Stored as a stable string token: one of `system` (the default), `sunday`, or
/// `monday`. Absent/unset or an unrecognized value ⇒ [FirstDayOfWeekPref.system].
const String kFirstDayOfWeekKey = 'first_day_of_week';

/// Which day the week starts on in the app's date pickers.
enum FirstDayOfWeekPref {
  /// Defer to the platform locale's first day of week.
  system('system'),

  /// Force weeks to start on Sunday.
  sunday('sunday'),

  /// Force weeks to start on Monday.
  monday('monday');

  const FirstDayOfWeekPref(this.token);

  /// The stable token persisted via `SettingsRepository`.
  final String token;
}

/// Resolves a persisted settings value into a [FirstDayOfWeekPref].
///
/// Defensive by design: `null`, a non-string, or an unrecognized token all fall
/// back to [FirstDayOfWeekPref.system].
FirstDayOfWeekPref firstDayOfWeekPrefFromStored(Object? stored) {
  if (stored is String) {
    for (final pref in FirstDayOfWeekPref.values) {
      if (pref.token == stored) return pref;
    }
  }
  return FirstDayOfWeekPref.system;
}

/// Maps a [FirstDayOfWeekPref] to the weekday index Flutter's date pickers use
/// (`0` = Sunday … `6` = Saturday, matching
/// [MaterialLocalizations.firstDayOfWeekIndex]), or `null` for
/// [FirstDayOfWeekPref.system] (defer to the platform locale).
int? firstDayOfWeekIndexFor(FirstDayOfWeekPref pref) {
  switch (pref) {
    case FirstDayOfWeekPref.system:
      return null;
    case FirstDayOfWeekPref.sunday:
      return 0;
    case FirstDayOfWeekPref.monday:
      return 1;
  }
}
