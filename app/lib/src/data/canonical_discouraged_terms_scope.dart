import 'package:flutter/widgets.dart';

/// Exposes the default-on discouraged-term display preference to the widget tree.
class CanonicalDiscouragedTermsScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const CanonicalDiscouragedTermsScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether supported discouraged terms are converted in read-only displays.
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CanonicalDiscouragedTermsScope>();
    return scope?.notifier?.value ?? true;
  }

  /// Returns the preference notifier without registering a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<CanonicalDiscouragedTermsScope>();
    if (scope == null) {
      throw FlutterError(
        'CanonicalDiscouragedTermsScope.notifierOf() called with a context '
        'that has no CanonicalDiscouragedTermsScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
