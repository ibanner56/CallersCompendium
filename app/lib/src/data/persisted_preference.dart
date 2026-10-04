import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/error_log.dart';
import 'regional_formats.dart';

/// A live preference value that also owns how it is stored: its settings [key],
/// its [defaultValue], and the [decode]/[encode] pair between the stored JSON
/// value and [T].
///
/// One descriptor holds what used to be copied across the field declaration,
/// the reset list and the loader. The reset and load iterate a single list of
/// descriptors, so a preference on that list is reset and loaded together. A
/// new preference still has to be added to that list (and to the restore test's
/// cases) by hand (audit finding D3).
///
/// Scopes still receive this as a plain `ValueNotifier<T>`; nothing about
/// `Scope.of` / `Scope.notifierOf` changes.
class PreferenceNotifier<T> extends ValueNotifier<T> {
  /// [initialValue] seeds the live value before the first load when it must
  /// differ from [defaultValue] (a constructor seam used by tests); a [reset]
  /// or [applyStored] always goes to / through [defaultValue] and [decode].
  PreferenceNotifier({
    required this.key,
    required this.defaultValue,
    required this.decode,
    required this.encode,
    T? initialValue,
  }) : super(initialValue ?? defaultValue);

  /// The `settings` table key. Pass a `const String k…Key` identifier, never an
  /// inline string, so the settings-classification walk can see it.
  final String key;

  final T defaultValue;

  /// Maps a stored value to [T]. Must return [defaultValue] for `null` and for
  /// a wrong-typed value: stored values are untrusted input.
  final T Function(Object? stored) decode;

  final Object? Function(T value) encode;

  /// Returns the live value to [defaultValue].
  void reset() => value = defaultValue;

  /// Assigns `decode(stored)`. Always assigns, so applying `null` (a key absent
  /// from a restored backup) resets the live value to its default instead of
  /// leaving the previous value in place.
  void applyStored(Object? stored) => value = decode(stored);

  /// Reads this preference's raw stored value. A read failure yields `null`, so
  /// one unreadable key leaves that preference at its default rather than
  /// failing startup.
  Future<Object?> read(SettingsRepository settings) =>
      _readGuarded(settings, key);

  /// Writes the current value. A failure is logged, not thrown. Does not
  /// reassign [value]: callers flip the notifier first so the UI reacts at
  /// once, then persist.
  Future<void> persist(SettingsRepository settings) => persistSetting(
    settings,
    key,
    encode(value),
    source: 'preference.persist.$key',
  );
}

/// Writes one setting, logging a failure instead of throwing it.
///
/// For a settings handler whose key has no [PreferenceNotifier] to call
/// [PreferenceNotifier.persist] on: a section-local setting, or a live
/// preference reached through a scope whose `notifierOf` is a plain
/// `ValueNotifier`. Keeps the "flip the live value first, then persist" order
/// of the callers; a failed write leaves the live value changed for this
/// session and is diagnosable in the log, rather than an unhandled async error.
///
/// [source] defaults to `settings.persist.<key>`.
Future<void> persistSetting(
  SettingsRepository settings,
  String key,
  Object? value, {
  String? source,
}) async {
  try {
    await settings.set(key, value);
  } catch (error, stackTrace) {
    logCaughtError(
      error,
      stackTrace,
      source: source ?? 'settings.persist.$key',
    );
  }
}

Future<Object?> _readGuarded(
  SettingsRepository settings,
  String key,
) => settings
    .get(key)
    .catchError(
      (_) => null,
    ); // diagnostics: silent — startup settings read failed; falls back to the preference's default.

/// The date-format preference, which spans two keys: the pref token under
/// [kDateFormatKey] and, for the custom variant, the raw pattern under
/// [kDateFormatCustomPatternKey]. [read] returns both stored values as a record
/// that [decode] resolves with [dateFormatSettingFromStored].
class DateFormatPreferenceNotifier
    extends PreferenceNotifier<DateFormatSetting> {
  DateFormatPreferenceNotifier()
    : super(
        key: kDateFormatKey,
        defaultValue: DateFormatSetting.system,
        decode: (Object? stored) => stored is (Object?, Object?)
            ? dateFormatSettingFromStored(stored.$1, stored.$2)
            : DateFormatSetting.system,
        encode: (setting) => setting.pref.token,
      );

  @override
  Future<Object?> read(SettingsRepository settings) async => (
    await _readGuarded(settings, kDateFormatKey),
    await _readGuarded(settings, kDateFormatCustomPatternKey),
  );
}
