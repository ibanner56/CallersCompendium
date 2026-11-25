import 'package:flutter/widgets.dart';

/// Persisted-settings key for the Experimental Event rules toggle (#2340).
/// Stored as a `bool`; unset means off (the default).
const String kEventRulesEnabledKey = 'event_rules_enabled';

/// Persisted-settings key for the rule picker's **Rule order** (#2341):
/// the name of an `EventRuleOrder` (`manual` or `mostUsed`), as a `String`.
/// Unset, or any other value, means `manual` (**My order**), the default.
/// Read when the picker opens; nothing else reads it.
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
