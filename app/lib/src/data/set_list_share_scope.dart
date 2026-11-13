import 'package:flutter/widgets.dart';

/// Persisted-settings keys for the Program › Sharing toggles. Each is stored as
/// a `bool`; **unset means on** (`true`), which is what sharing a set list did
/// before the toggles existed.
const String kShareSetListIncludeTitleKey = 'share_set_list_include_title';
const String kShareSetListIncludeCallerBandKey =
    'share_set_list_include_caller_band';
const String kShareSetListIncludeDateVenueKey =
    'share_set_list_include_date_venue';

/// What a shared or copied set list (the text export) includes of the program's
/// header. Never consulted by the `.ccshare` / JSON bundle, which always carries
/// the whole program.
class SetListShareOptions {
  const SetListShareOptions({
    this.includeTitle = true,
    this.includeCallerBand = true,
    this.includeDateVenue = true,
  });

  /// The three toggles as they stand now. Registers a rebuild dependency on
  /// each, and returns all-on (the pre-toggle behaviour) for any scope that is
  /// not mounted.
  static SetListShareOptions of(BuildContext context) => SetListShareOptions(
    includeTitle: ShareSetListTitleScope.of(context),
    includeCallerBand: ShareSetListCallerBandScope.of(context),
    includeDateVenue: ShareSetListDateVenueScope.of(context),
  );

  final bool includeTitle;
  final bool includeCallerBand;
  final bool includeDateVenue;
}

/// Whether a shared or copied set list includes the program title. A live [ValueNotifier]; `true` (the default) when no scope is
/// mounted. Use [ShareSetListTitleScope.notifierOf] to change it from Settings.
class ShareSetListTitleScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ShareSetListTitleScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShareSetListTitleScope>();
    return scope?.notifier?.value ?? true;
  }

  /// The underlying notifier, without a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShareSetListTitleScope>();
    if (scope == null) {
      throw FlutterError(
        'ShareSetListTitleScope.notifierOf() called with a context that has no '
        'ShareSetListTitleScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Whether a shared or copied set list includes the caller and band. A live [ValueNotifier]; `true` (the default) when no scope is
/// mounted. Use [ShareSetListCallerBandScope.notifierOf] to change it from Settings.
class ShareSetListCallerBandScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const ShareSetListCallerBandScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShareSetListCallerBandScope>();
    return scope?.notifier?.value ?? true;
  }

  /// The underlying notifier, without a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShareSetListCallerBandScope>();
    if (scope == null) {
      throw FlutterError(
        'ShareSetListCallerBandScope.notifierOf() called with a context that has no '
        'ShareSetListCallerBandScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}

/// Whether a shared or copied set list includes the date and venue. A live [ValueNotifier]; `true` (the default) when no scope is
/// mounted. Use [ShareSetListDateVenueScope.notifierOf] to change it from Settings.
class ShareSetListDateVenueScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const ShareSetListDateVenueScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShareSetListDateVenueScope>();
    return scope?.notifier?.value ?? true;
  }

  /// The underlying notifier, without a rebuild dependency.
  static ValueNotifier<bool> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<ShareSetListDateVenueScope>();
    if (scope == null) {
      throw FlutterError(
        'ShareSetListDateVenueScope.notifierOf() called with a context that has no '
        'ShareSetListDateVenueScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
