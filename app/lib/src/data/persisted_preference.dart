import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/error_log.dart';

/// A live preference value that also owns how it is stored: its settings [key],
/// its [defaultValue], and the [decode]/[encode] pair between the stored JSON
/// value and [T].
///
/// One descriptor replaces the copies of the same preference that used to live
/// in the reset list, the loader and the field declaration, so a new preference
/// cannot be added to one and forgotten in another (audit finding D3).
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
  Future<Object?> read(SettingsRepository settings) => settings
      .get(key)
      .catchError(
        (_) => null,
      ); // diagnostics: silent — startup settings read failed; falls back to the preference's default.

  /// Writes the current value. A failure is logged, not thrown.
  Future<void> persist(SettingsRepository settings) async {
    try {
      await settings.set(key, encode(value));
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'preference.persist.$key');
    }
  }
}
