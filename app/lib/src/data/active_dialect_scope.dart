import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Exposes the dialect each dance form is shown in ([DialectsByForm]) to the
/// widget tree, live. Descendants that call [ActiveDialectScope.of] rebuild
/// whenever any form's dialect changes.
///
/// Each dance form has its own dialect (ADR-006 §9.1, point 1), so a caller
/// picks the one for the dance it shows: `ActiveDialectScope.of(context)
/// .forDance(dance)`, or `.forForm(form)` where there is no dance.
///
/// The app mounts [ActiveDialectScope.byForm]. The default constructor shows
/// every form in one dialect, for tests and previews that need only one.
/// To change a form's dialect, use its library (`DialectLibraryScope`).
class ActiveDialectScope extends InheritedNotifier<Listenable> {
  /// Every form shown in [notifier]'s dialect.
  ActiveDialectScope({
    super.key,
    required ValueListenable<Dialect> notifier,
    required super.child,
  }) : _read = (() => DialectsByForm.all(notifier.value)),
       super(notifier: notifier);

  /// Each form shown in its own dialect, from [dialects].
  ActiveDialectScope.byForm({
    super.key,
    required ValueListenable<DialectsByForm> dialects,
    required super.child,
  }) : _read = (() => dialects.value),
       super(notifier: dialects);

  final DialectsByForm Function() _read;

  /// The dialect each form is shown in. Registers a rebuild dependency.
  static DialectsByForm of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ActiveDialectScope>();
    if (scope == null) {
      throw FlutterError(
        'ActiveDialectScope.of() called with a context that has no '
        'ActiveDialectScope ancestor.',
      );
    }
    return scope._read();
  }

  /// The dialect an entry with [payload] is shown in: that of the dance form
  /// it is made for ([glossaryEntryDanceForm]), so a figure, combination or
  /// term of your own made for English reads in your English dialect (#2294).
  /// An entry that names no form, or one this build does not know, reads in
  /// contra's. Registers a rebuild dependency.
  static Dialect entryOf(BuildContext context, Object? payload) =>
      of(context).forForm(glossaryEntryDanceForm(payload));

  /// Contra's dialect, for a surface that is built on contra's taxonomy alone
  /// and has no dance, form or entry of its own to pick by: the figure and
  /// layout defaults in Settings, parts of import review, and the matrix
  /// columns' and calling cards' settings. A surface that shows an entry of
  /// your own uses [entryOf]. Registers a rebuild dependency.
  static Dialect contraOf(BuildContext context) =>
      of(context).forForm(DanceForm.contra);

  /// Like [of], or `null` when no [ActiveDialectScope] is present. Use when a
  /// dialect is desirable but not required; callers fall back to
  /// [DialectsByForm.defaults].
  static DialectsByForm? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveDialectScope>()?._read();
}
