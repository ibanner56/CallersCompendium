import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Persisted-settings key for the Experimental Suggestions toggle (#2343).
/// Stored as a `bool`; unset means off (the default).
const String kSuggestionsEnabledKey = 'suggestions_enabled';

/// Persisted-settings key for **Use in Perform's Swap this dance** (#2348),
/// under Settings ▸ Experimental ▸ Suggestions: whether Perform's swap sheet
/// orders its results by suggestions. Stored as a `bool`; unset means off
/// (the default), and it does nothing while [kSuggestionsEnabledKey] is off.
const String kSuggestionsInPerformSwapKey = 'suggestions_in_perform_swap';

/// Persisted-settings key for what suggestions look for (#2343): one JSON
/// object, read and written only by `suggestion_settings.dart` in
/// compendium_core ([readSuggestionSettings], [SuggestionSettings.toJson]).
/// Unset means the shipped defaults.
const String kSuggestionSettingsKey = 'suggestion_settings';

/// Reads a stored [kSuggestionSettingsKey] value for the live preference.
SuggestionSettingsRead decodeSuggestionSettings(Object? stored) =>
    readSuggestionSettings(stored);

/// The stored form of a live [kSuggestionSettingsKey] value.
Object? encodeSuggestionSettings(SuggestionSettingsRead value) =>
    value.settings.toJson();

/// Exposes the Suggestions toggle as a live [ValueNotifier]. When `true`, the
/// program builder's collection picker offers **Suggested** in its Sort menu.
class SuggestionsEnabledScope extends InheritedNotifier<ValueNotifier<bool>> {
  const SuggestionsEnabledScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether Suggestions is on. Registers a rebuild dependency. `false` with
  /// no ancestor: the off-by-default product behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SuggestionsEnabledScope>()
          ?.notifier
          ?.value ??
      false;

  /// The notifier, to change the setting. Does not register a dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<SuggestionsEnabledScope>();
    if (scope == null) {
      throw FlutterError(
        'SuggestionsEnabledScope.notifierOf() called with a context that has '
        'no SuggestionsEnabledScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Exposes **Use in Perform's Swap this dance** ([kSuggestionsInPerformSwapKey],
/// #2348) as a live [ValueNotifier]. Perform's swap sheet orders by
/// suggestions only while this and [SuggestionsEnabledScope] are both `true`.
class SuggestionsInPerformSwapScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const SuggestionsInPerformSwapScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The stored setting, whatever Suggestions is. Registers a rebuild
  /// dependency. `false` with no ancestor: the off-by-default behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SuggestionsInPerformSwapScope>()
          ?.notifier
          ?.value ??
      false;

  /// Whether Perform's swap sheet orders by suggestions: Suggestions and this
  /// setting both on. Registers a rebuild dependency on both.
  static bool activeOf(BuildContext context) =>
      SuggestionsEnabledScope.of(context) && of(context);

  /// The notifier, to change the setting. Does not register a dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<SuggestionsInPerformSwapScope>();
    if (scope == null) {
      throw FlutterError(
        'SuggestionsInPerformSwapScope.notifierOf() called with a context '
        'that has no SuggestionsInPerformSwapScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Exposes what suggestions look for as a live [ValueNotifier], with whether
/// the stored value came from a newer build
/// ([SuggestionSettingsRead.isNewer]), in which case the editor shows it
/// read-only.
class SuggestionSettingsScope
    extends InheritedNotifier<ValueNotifier<SuggestionSettingsRead>> {
  const SuggestionSettingsScope({
    super.key,
    required ValueNotifier<SuggestionSettingsRead> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static const SuggestionSettingsRead _defaults = (
    settings: SuggestionSettings.defaults,
    isNewer: false,
  );

  /// The current value. Registers a rebuild dependency. The defaults with no
  /// ancestor.
  static SuggestionSettingsRead of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SuggestionSettingsScope>()
          ?.notifier
          ?.value ??
      _defaults;

  /// The notifier, to change the value. Does not register a dependency.
  static ValueNotifier<SuggestionSettingsRead> notifierOf(
    BuildContext context,
  ) {
    final scope = context
        .getInheritedWidgetOfExactType<SuggestionSettingsScope>();
    if (scope == null) {
      throw FlutterError(
        'SuggestionSettingsScope.notifierOf() called with a context that has '
        'no SuggestionSettingsScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
