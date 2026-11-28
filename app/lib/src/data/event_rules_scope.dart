import 'package:flutter/widgets.dart';

/// Persisted-settings key for the Experimental Event rules toggle (#2340).
/// Stored as a `bool`; unset means off (the default).
const String kEventRulesEnabledKey = 'event_rules_enabled';

/// Persisted-settings key for the rule picker's **Rule order** (#2341):
/// the name of an `EventRuleOrder` (`manual` or `mostUsed`), as a `String`.
/// Unset, or any other value, means `manual` (**My order**), the default.
/// Read when the picker opens, and read and set by its control in Settings ▸
/// Experimental.
const String kEventRuleOrderKey = 'event_rule_order';

/// Exposes the Event rules toggle as a live [ValueNotifier]. While it is
/// `true`, the program builder shows its Rules control, strip and slot
/// markers, and Settings ▸ Program links to Manage rules. While it is `false`
/// (the default) none of them appears and no rule is checked.
class EventRulesEnabledScope extends InheritedNotifier<ValueNotifier<bool>> {
  const EventRulesEnabledScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether Event rules is on. Registers a rebuild dependency. `false` with
  /// no ancestor: the off-by-default product behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<EventRulesEnabledScope>()
          ?.notifier
          ?.value ??
      false;

  /// The notifier, to change the setting. Does not register a dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<EventRulesEnabledScope>();
    if (scope == null) {
      throw FlutterError(
        'EventRulesEnabledScope.notifierOf() called with a context that has '
        'no EventRulesEnabledScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Persisted-settings key for **Check Perform's Swap this dance** (#2347),
/// under Settings ▸ Experimental ▸ Event rules: whether Perform's swap sheet
/// marks the dances that would break the program's applied rules. Stored as
/// a `bool`; unset means on (the default), and it does nothing while
/// [kEventRulesEnabledKey] is off.
const String kEventRulesCheckPerformSwapKey = 'event_rules_check_perform_swap';

/// Exposes **Check Perform's Swap this dance**
/// ([kEventRulesCheckPerformSwapKey], #2347) as a live [ValueNotifier].
/// Perform's swap sheet checks its results against the program's rules only
/// while this and [EventRulesEnabledScope] are both `true`.
class EventRulesCheckPerformSwapScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const EventRulesCheckPerformSwapScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The stored setting, whatever Event rules is. Registers a rebuild
  /// dependency. `true` with no ancestor: the on-by-default behaviour.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<EventRulesCheckPerformSwapScope>()
          ?.notifier
          ?.value ??
      true;

  /// Whether Perform's swap sheet checks its results: Event rules and this
  /// setting both on. Registers a rebuild dependency on both.
  static bool activeOf(BuildContext context) =>
      EventRulesEnabledScope.of(context) && of(context);

  /// The notifier, to change the setting. Does not register a dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<EventRulesCheckPerformSwapScope>();
    if (scope == null) {
      throw FlutterError(
        'EventRulesCheckPerformSwapScope.notifierOf() called with a context '
        'that has no EventRulesCheckPerformSwapScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
