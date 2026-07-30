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

import 'custom_date_pattern.dart';

/// Key used to persist the program-event-date format preference (ROADMAP G.8).
///
/// Stored as a stable string token: one of `system` (the default),
/// `ymd`, `dmy`, `mdy`, or `custom`. Absent/unset or an unrecognized value ⇒
/// [DateFormatPref.system].
const String kDateFormatKey = 'date_format';

/// Key used to persist the raw user-entered pattern for [DateFormatPref.custom]
/// (issue #584). Stored as an untrusted string; it is only ever consumed
/// through the defensive [parseCustomDatePattern], which rejects anything that
/// is null/empty/over-long/unrecognized so a corrupted value can never leave
/// dates rendering or parsing in an unexpected way.
const String kDateFormatCustomPatternKey = 'date_format_custom';

/// How program event dates render on screen.
enum DateFormatPref {
  /// Defer to the platform locale via [MaterialLocalizations.formatMediumDate].
  system('system'),

  /// ISO-like year-month-day, e.g. `2026-07-15`.
  ymd('ymd'),

  /// Day/month/year, e.g. `15/07/2026`.
  dmy('dmy'),

  /// Month/day/year, e.g. `07/15/2026`.
  mdy('mdy'),

  /// A user-entered pattern (issue #584); the raw pattern is persisted
  /// separately under [kDateFormatCustomPatternKey].
  custom('custom');

  const DateFormatPref(this.token);

  /// The stable token persisted via `SettingsRepository`.
  final String token;
}

/// The resolved date-format preference plus, for [DateFormatPref.custom], the
/// raw user-entered pattern (issue #584).
///
/// This is the single value that flows through `DateFormatScope` and into every
/// render/parse call site, so a custom pattern reaches display formatting and
/// title date detection without extra plumbing. The raw pattern is untrusted
/// and is always validated at the point of use via [parseCustomDatePattern];
/// [effectivePattern] exposes the validated result (or `null` when invalid).
class DateFormatSetting {
  const DateFormatSetting(this.pref, {this.customPattern});

  /// The system default: no fixed pattern, defers to the platform locale.
  static const DateFormatSetting system = DateFormatSetting(
    DateFormatPref.system,
  );

  /// The selected preference.
  final DateFormatPref pref;

  /// The raw, untrusted pattern string for [DateFormatPref.custom]; `null` for
  /// every other preference.
  final String? customPattern;

  /// The validated custom pattern, or `null` when [pref] is not
  /// [DateFormatPref.custom] or the raw pattern is invalid. Callers treat a
  /// `null` here as "fall back to system".
  CustomDatePattern? get effectivePattern => pref == DateFormatPref.custom
      ? parseCustomDatePattern(customPattern)
      : null;

  /// True when [pref] is [DateFormatPref.custom] but the raw pattern does not
  /// validate — the state the settings screen surfaces as an inline warning
  /// while the app degrades to the system default.
  bool get hasInvalidCustomPattern =>
      pref == DateFormatPref.custom && effectivePattern == null;

  @override
  bool operator ==(Object other) =>
      other is DateFormatSetting &&
      other.pref == pref &&
      other.customPattern == customPattern;

  @override
  int get hashCode => Object.hash(pref, customPattern);

  @override
  String toString() =>
      'DateFormatSetting(${pref.token}, customPattern: $customPattern)';
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

/// Resolves the persisted preference token and raw custom pattern into a
/// [DateFormatSetting] (issue #584).
///
/// Defensive by design: [prefStored] is resolved via [dateFormatPrefFromStored]
/// (unknown ⇒ system). When it resolves to [DateFormatPref.custom] the raw
/// [patternStored] is carried through **only** when it is a non-empty string
/// within the length cap; a `null`, non-string, empty, or over-long value drops
/// the setting all the way back to [DateFormatSetting.system] so a corrupted
/// custom value can never leave dates rendering or parsing unexpectedly. (A
/// short-but-unparseable pattern is still carried so the settings screen can
/// show it back to the user with the inline warning; consumers treat it as
/// system via [DateFormatSetting.effectivePattern].)
DateFormatSetting dateFormatSettingFromStored(
  Object? prefStored,
  Object? patternStored,
) {
  final pref = dateFormatPrefFromStored(prefStored);
  if (pref != DateFormatPref.custom) return DateFormatSetting(pref);
  if (patternStored is! String ||
      patternStored.isEmpty ||
      patternStored.length > kMaxCustomDatePatternLength) {
    return DateFormatSetting.system;
  }
  return DateFormatSetting(DateFormatPref.custom, customPattern: patternStored);
}

/// Formats a program event [date] for on-screen display per [setting].
///
/// For [DateFormatPref.system] (and any invalid custom pattern) this defers to
/// the platform locale via [l10n] (`formatMediumDate`). For the fixed tokens and
/// a valid custom pattern it uses a dependency-free zero-padded pattern (no
/// `intl`).
String formatEventDate(
  DateTime date,
  DateFormatSetting setting,
  MaterialLocalizations l10n,
) {
  final fixed = formatDatePattern(date, setting);
  return fixed ?? l10n.formatMediumDate(date);
}

/// Returns the fixed zero-padded pattern for [date] under [setting], or `null`
/// for [DateFormatPref.system] and any invalid custom pattern (which have no
/// fixed pattern and defer to the platform locale). Pure and Flutter-free so the
/// fixed branches are directly unit-testable without a [MaterialLocalizations].
String? formatDatePattern(DateTime date, DateFormatSetting setting) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  switch (setting.pref) {
    case DateFormatPref.system:
      return null;
    case DateFormatPref.ymd:
      return '$y-$m-$d';
    case DateFormatPref.dmy:
      return '$d/$m/$y';
    case DateFormatPref.mdy:
      return '$m/$d/$y';
    case DateFormatPref.custom:
      final pattern = setting.effectivePattern;
      // Invalid/unrecognized custom pattern ⇒ null ⇒ caller falls back to the
      // platform locale (system default), matching the documented contract.
      return pattern == null ? null : formatWithCustomPattern(date, pattern);
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
