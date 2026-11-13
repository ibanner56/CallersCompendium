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

  final bool includeTitle;
  final bool includeCallerBand;
  final bool includeDateVenue;
}

/// Exposes the three set-list sharing toggles as live notifiers.
///
/// [of] rebuilds the caller when any toggle changes and returns all-on (the
/// pre-toggle behaviour) when no scope is mounted. The settings screen reads
/// the individual notifiers with [titleNotifierOf], [callerBandNotifierOf] and
/// [dateVenueNotifierOf] to change them.
class SetListShareScope extends InheritedNotifier<Listenable> {
  SetListShareScope({
    super.key,
    required this.title,
    required this.callerBand,
    required this.dateVenue,
    required super.child,
  }) : super(notifier: Listenable.merge([title, callerBand, dateVenue]));

  final ValueNotifier<bool> title;
  final ValueNotifier<bool> callerBand;
  final ValueNotifier<bool> dateVenue;

  static SetListShareOptions of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SetListShareScope>();
    if (scope == null) return const SetListShareOptions();
    return SetListShareOptions(
      includeTitle: scope.title.value,
      includeCallerBand: scope.callerBand.value,
      includeDateVenue: scope.dateVenue.value,
    );
  }

  static SetListShareScope _scopeOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SetListShareScope>();
    if (scope == null) {
      throw FlutterError(
        'SetListShareScope.notifierOf() called with a context that has no '
        'SetListShareScope ancestor.',
      );
    }
    return scope;
  }

  static ValueNotifier<bool> titleNotifierOf(BuildContext context) =>
      _scopeOf(context).title;
  static ValueNotifier<bool> callerBandNotifierOf(BuildContext context) =>
      _scopeOf(context).callerBand;
  static ValueNotifier<bool> dateVenueNotifierOf(BuildContext context) =>
      _scopeOf(context).dateVenue;
}
