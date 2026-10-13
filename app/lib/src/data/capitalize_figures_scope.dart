import 'package:flutter/widgets.dart';

/// Persisted-settings key for the "Capitalize figures" display toggle. Stored as
/// a `bool`; unset means off (the default).
const String kCapitalizeFiguresKey = 'capitalize_figures';

/// Exposes the "Capitalize figures" display setting as a live [ValueNotifier]
/// to the widget tree.
///
/// When `true`, the first letter of each rendered figure is capitalized
/// (`Neighbors allemande left 1½`). When `false` (the default) figures are shown
/// as the renderer produced them (built-in figures start in lower case,
/// matching ContraDB); nothing is ever lower-cased. This is a *display-only*
/// preference applied by [capitalizeFirstLetter] at the on-screen figure
/// surfaces: the core renderer's canonical text (which feeds search/FTS/dedupe)
/// and the screen-reader semantics labels are never affected. Verbose text is
/// capitalized only when it is shown on screen.
/// Descendants that call [CapitalizeFiguresScope.of] rebuild automatically when
/// the setting changes (live update).
///
/// Use [CapitalizeFiguresScope.notifierOf] when you need to *change* the
/// setting (e.g. from the settings screen).
class CapitalizeFiguresScope extends InheritedNotifier<ValueNotifier<bool>> {
  const CapitalizeFiguresScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Whether rendered figures start with a capital letter. Registers a rebuild
  /// dependency so the caller rebuilds whenever the setting changes.
  ///
  /// Returns `false` (the off-by-default behavior) when there is no
  /// [CapitalizeFiguresScope] ancestor, so callers — and tests that don't wire
  /// the scope — get the product default: figures shown as written (built-in
  /// figures start in lower case).
  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CapitalizeFiguresScope>();
    return scope?.notifier?.value ?? false;
  }

  /// Returns the underlying notifier so callers can change the setting. Does
  /// *not* register a rebuild dependency — for read-and-mutate use only.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<CapitalizeFiguresScope>();
    if (scope == null) {
      throw FlutterError(
        'CapitalizeFiguresScope.notifierOf() called with a context that has '
        'no CapitalizeFiguresScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Returns [text] with its first character upper-cased when [capitalize] is
/// true; otherwise [text] unchanged.
///
/// Operates on the first Unicode code point (so a surrogate-pair letter is not
/// split) and leaves a leading digit, glyph or punctuation as it is, since
/// `toUpperCase` is a no-op there.
String capitalizeFirstLetter(String text, {required bool capitalize}) {
  if (!capitalize || text.isEmpty) return text;
  final first = String.fromCharCode(text.runes.first);
  return first.toUpperCase() + text.substring(first.length);
}
