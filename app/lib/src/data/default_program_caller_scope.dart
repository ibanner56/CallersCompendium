import 'package:flutter/widgets.dart';

/// Exposes the "Default caller" program default (`kDefaultProgramCallerKey`) as
/// a live [ValueNotifier] to the widget tree. The value is the trimmed name, or
/// `''` when none is set.
///
/// The default caller also scopes calling history while "Track calling history
/// for all callers" is off (issue #583), so a screen that keeps its history
/// loaded — Collection, which lives in the shell's `IndexedStack` — must hear
/// when it changes, whether it was edited in Settings or arrived by sync
/// (PRES-4). Descendants that call [DefaultProgramCallerScope.maybeOf] rebuild
/// when it does.
///
/// Use [DefaultProgramCallerScope.notifierOf] to *change* the setting (from the
/// Program defaults section).
class DefaultProgramCallerScope
    extends InheritedNotifier<ValueNotifier<String>> {
  const DefaultProgramCallerScope({
    super.key,
    required ValueNotifier<String> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The default caller, or `null` when there is no
  /// [DefaultProgramCallerScope] ancestor. Registers a rebuild dependency.
  ///
  /// `null` is distinct from `''` (no default caller set): a widget test that
  /// does not wire the scope gets `null`, and should then read the stored
  /// setting itself rather than assume no caller is configured.
  static String? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DefaultProgramCallerScope>()
      ?.notifier
      ?.value;

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<String> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<DefaultProgramCallerScope>();
    if (scope == null) {
      throw FlutterError(
        'DefaultProgramCallerScope.notifierOf() called with a context '
        'that has no DefaultProgramCallerScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
