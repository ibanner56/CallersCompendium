/// App-only regional-format preferences (ROADMAP G.8).
///
/// Ahead of full app i18n (which we do NOT ship here), this exposes the cheap,
/// genuinely-useful regional piece: how program event dates render. The
/// preference is persisted via `SettingsRepository` as a stable string token.
///
/// The key, enum, and resolver below are Flutter-free pure functions so they
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
/// Stored as a stable string token: one of `system` (the default), `sunday`,
/// `monday`, or `saturday`. Absent/unset or an unrecognized value ⇒
/// [FirstDayOfWeekPref.system].
const String kFirstDayOfWeekKey = 'first_day_of_week';

/// Which day the week starts on in date UIs the app renders itself.
///
/// NOTE: Flutter's [showDatePicker] derives its first day of week from the
/// active locale and offers no per-call override, so this preference cannot
/// change the system calendar picker. It applies only to date surfaces the app
/// draws directly. See `docs/dev/localization.md`.
enum FirstDayOfWeekPref {
  /// Defer to the platform locale (via `MaterialLocalizations`).
  system('system'),

  /// Start the week on Sunday.
  sunday('sunday'),

  /// Start the week on Monday (ISO-8601).
  monday('monday'),

  /// Start the week on Saturday.
  saturday('saturday');

  const FirstDayOfWeekPref(this.token);

  /// The stable token persisted via `SettingsRepository`.
  final String token;

  /// The [DateTime] weekday constant (Mon=1 … Sun=7) this preference starts the
  /// week on, or `null` for [system] (defer to the platform locale). Provided
  /// so date UIs the app controls can honor the setting without re-deriving it.
  int? get startWeekday => switch (this) {
    FirstDayOfWeekPref.system => null,
    FirstDayOfWeekPref.monday => DateTime.monday,
    FirstDayOfWeekPref.saturday => DateTime.saturday,
    FirstDayOfWeekPref.sunday => DateTime.sunday,
  };
}

/// Resolves a persisted settings value into a [FirstDayOfWeekPref].
///
/// Defensive by design (OWASP: validate untrusted persisted input): `null`, a
/// non-string, or an unrecognized token all fall back to
/// [FirstDayOfWeekPref.system], so a corrupted stored value can never crash or
/// select an out-of-range weekday.
FirstDayOfWeekPref firstDayOfWeekPrefFromStored(Object? stored) {
  if (stored is String) {
    for (final pref in FirstDayOfWeekPref.values) {
      if (pref.token == stored) return pref;
    }
  }
  return FirstDayOfWeekPref.system;
}
